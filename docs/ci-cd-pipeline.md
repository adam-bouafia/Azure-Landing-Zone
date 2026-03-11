# CI/CD Pipeline

## Overview -- What CI/CD Means and Why It Matters

**CI/CD** stands for **Continuous Integration / Continuous Deployment**. It is the practice of
automating everything that happens between writing code and that code running in production.

- **Continuous Integration (CI)** means every time someone pushes code, it is automatically
  validated -- linted, compiled, and tested. If something is broken, the team finds out in
  minutes, not days.

- **Continuous Deployment (CD)** means once code passes validation, it is automatically (or
  semi-automatically) deployed to the target environment. No one logs into Azure and clicks
  buttons. No one runs `az deployment` from their laptop.

### Why not deploy from our laptop?

In a managed services engagement, deploying infrastructure from a developer's laptop is a
serious risk. Here is why:

1. **No audit trail.** If something breaks, we have no record of who deployed what, when,
   or why. A pipeline logs every step.
2. **No consistency.** Developer A might have Azure CLI 2.50, Developer B has 2.61. The pipeline
   uses the same version every time.
3. **No approval process.** A tired engineer at 11 PM can push to production with a typo in a
   parameter file. A pipeline enforces review gates.
4. **No rollback visibility.** If we deploy from our laptop, the team has no idea what changed.
   A pipeline's what-if output shows exactly what will be modified before it happens.
5. **Credentials on personal machines.** Our laptop has Azure Owner credentials? That is a
   security incident waiting to happen. The pipeline uses a service principal with scoped
   permissions.

The rule in managed services: **the pipeline is the only thing that touches production.**

---

## Pipeline Architecture

Our Azure Landing Zone uses a **5-stage pipeline** in Azure DevOps. Every change flows through
these stages in order:

```
Push to main --> Validate --> What-If (dev) --> Deploy (dev) --> What-If (prod) --> Deploy (prod)
                                                                                       ^
                                                                                       |
                                                                                Manual Approval
```

Here is what each stage does:

| Stage | Name | Purpose | Automatic? |
|-------|------|---------|------------|
| 1 | **Validate** | Lint, compile, and validate Bicep against Azure API | Yes |
| 2 | **What-If (dev)** | Preview what would change in the dev environment | Yes |
| 3 | **Deploy (dev)** | Actually deploy to dev | Yes |
| 4 | **What-If (prod)** | Preview what would change in production | Yes |
| 5 | **Deploy (prod)** | Deploy to production | **Manual approval required** |

The pipeline only triggers when files in the `infra/` folder change. Documentation edits
or script changes do not trigger a deployment -- only infrastructure code changes do.

---

## Stage 1: Validate

The Validate stage is the first line of defense. It catches problems before any deployment
is attempted. It runs two checks:

1. **Lint and Build** -- Runs our `validate-bicep.sh` script, which calls `az bicep lint` and
   `az bicep build` on every `.bicep` file. This catches syntax errors, unused variables,
   missing parameter decorators, and other code quality issues. This step does not need Azure
   credentials because it runs entirely locally on the build agent.

2. **ARM Validation** -- Calls `az deployment sub validate`, which sends the compiled template
   to Azure's Resource Manager API and asks "would this deployment work?" Azure checks that
   all resource types exist, API versions are valid, parameter types match, and there are no
   conflicts with existing resources. This step needs Azure credentials because it talks to
   the real Azure API (but it does not create anything).

### Template: `bicep-validate.yml`

```yaml
parameters:
  - name: serviceConnection
    type: string

stages:
  - stage: Validate
    displayName: 'Validate Bicep'
    jobs:
      - job: LintAndBuild
        displayName: 'Lint, Build & Validate'
        steps:
          # Step 1: Lint and compile locally
          # This catches syntax errors without needing Azure credentials.
          - task: AzureCLI@2
            displayName: 'Bicep Lint & Build'
            inputs:
              azureSubscription: ${{ parameters.serviceConnection }}
              scriptType: 'bash'
              scriptLocation: 'scriptPath'
              scriptPath: 'scripts/bash/validate-bicep.sh'

          # Step 2: Validate against Azure API
          # This goes further than lint -- it checks that resource types exist,
          # API versions are valid, and parameter types match. Requires Azure
          # credentials because it calls the ARM validation endpoint.
          - task: AzureCLI@2
            displayName: 'ARM Validation (dev)'
            inputs:
              azureSubscription: ${{ parameters.serviceConnection }}
              scriptType: 'bash'
              inlineScript: |
                echo "Validating Bicep against Azure API..."
                az deployment sub validate \
                  --location westeurope \
                  --template-file infra/main.bicep \
                  --parameters infra/main.dev.bicepparam \
                  --parameters jumpboxAdminPassword='ValidationOnly123!'
                echo "##vso[task.complete result=Succeeded;]Validation passed"
```

**Why validate with dev parameters?** We use the dev parameter file for validation because it
is cheaper (Firewall and Bastion disabled). The goal here is to check syntax and types, not to
test the full production configuration. If the Bicep compiles and validates with dev params,
the prod params will work too (they use the same template, just with different values).

---

## Stage 2 and 4: What-If

The What-If stage is where the pipeline answers the question: "What would actually change if
I deployed this?" Azure's what-if operation compares our template against the current state
of our subscription and produces a detailed report.

### What the output looks like

The what-if output uses symbols to show what would happen to each resource:

```
Resource and calculation changes:
  + Microsoft.Network/virtualNetworks/vnet-hub-weu           [Create]
  ~ Microsoft.Network/networkSecurityGroups/nsg-web-prod      [Modify]
    - properties.securityRules[0].properties.sourceAddressPrefix: "10.0.1.0/26" => "*"
  = Microsoft.Resources/resourceGroups/rg-hub-weu             [NoChange]
  - Microsoft.Compute/virtualMachines/vm-old-test             [Delete]
```

| Symbol | Meaning | Action |
|--------|---------|--------|
| `+` | **Create** | A new resource will be created |
| `~` | **Modify** | An existing resource will be changed (details shown below) |
| `=` | **NoChange** | Resource exists and matches the template -- nothing happens |
| `-` | **Delete** | Resource will be removed |

This output is critical for managed services. Before approving a production deployment, an
engineer reviews the what-if output in the pipeline logs to make sure there are no surprises
-- no accidental deletions, no unexpected modifications.

### Template: `bicep-whatif.yml`

```yaml
parameters:
  - name: serviceConnection
    type: string
  - name: environment
    type: string
    default: 'dev'
  - name: dependsOn
    type: string
    default: 'Validate'

stages:
  - stage: WhatIf${{ parameters.environment }}
    displayName: 'What-If (${{ parameters.environment }})'
    dependsOn: ${{ parameters.dependsOn }}
    jobs:
      - job: WhatIf
        displayName: 'Preview Changes'
        steps:
          - task: AzureCLI@2
            displayName: 'What-If Analysis'
            inputs:
              azureSubscription: ${{ parameters.serviceConnection }}
              scriptType: 'bash'
              inlineScript: |
                echo "=== What-If Preview for ${{ parameters.environment }} ==="
                echo ""
                az deployment sub what-if \
                  --location westeurope \
                  --template-file infra/main.bicep \
                  --parameters infra/main.${{ parameters.environment }}.bicepparam \
                  --parameters jumpboxAdminPassword='$(jumpboxAdminPassword)' \
                  --result-format FullResourcePayloads
```

Notice the template is parameterized with `environment`. The main pipeline calls this template
twice -- once with `environment: 'dev'` and once with `environment: 'prod'`. The stage name
becomes `WhatIfdev` or `WhatIfprod` dynamically, which is how Azure DevOps tracks them as
separate stages.

The `--result-format FullResourcePayloads` flag tells Azure to include the complete resource
details in the output, not just the property names. This makes it easier to review exactly
what values are changing.

---

## Stage 3 and 5: Deploy

The Deploy stage is where resources are actually created or updated in Azure. This stage uses
a **deployment job** instead of a regular job, which gives us two important features:

1. **Environment tracking** -- The deployment is linked to an Azure DevOps "environment"
   (dev or prod). This gives us a deployment history, showing every deployment to that
   environment with timestamps, who triggered it, and which commit was deployed.

2. **Approval gates** -- For the `prod` environment, we configure an approval check in Azure
   DevOps. The pipeline pauses at the Deploy (prod) stage and sends a notification to the
   designated approvers. They review the what-if output from Stage 4, and only when they click
   "Approve" does the deployment proceed.

### Template: `bicep-deploy.yml`

```yaml
parameters:
  - name: serviceConnection
    type: string
  - name: environment
    type: string
  - name: dependsOn
    type: string

stages:
  - stage: Deploy${{ parameters.environment }}
    displayName: 'Deploy (${{ parameters.environment }})'
    dependsOn: ${{ parameters.dependsOn }}
    jobs:
      - deployment: Deploy
        displayName: 'Deploy Infrastructure'
        # This environment reference triggers the approval gate (if configured)
        environment: ${{ parameters.environment }}
        strategy:
          runOnce:
            deploy:
              steps:
                # checkout: self is required in deployment jobs because they
                # run in a clean workspace -- the code isn't automatically available
                - checkout: self

                - task: AzureCLI@2
                  displayName: 'Deploy Bicep'
                  inputs:
                    azureSubscription: ${{ parameters.serviceConnection }}
                    scriptType: 'bash'
                    inlineScript: |
                      echo "=== Deploying to ${{ parameters.environment }} ==="
                      echo "Build: $(Build.BuildNumber)"
                      echo ""

                      az deployment sub create \
                        --location westeurope \
                        --template-file infra/main.bicep \
                        --parameters infra/main.${{ parameters.environment }}.bicepparam \
                        --parameters jumpboxAdminPassword='$(jumpboxAdminPassword)' \
                        --name "deploy-$(Build.BuildNumber)"

                      echo ""
                      echo "=== Deployment Complete ==="

                # Post-deployment: show what was deployed
                - task: AzureCLI@2
                  displayName: 'Verify Deployment'
                  inputs:
                    azureSubscription: ${{ parameters.serviceConnection }}
                    scriptType: 'bash'
                    inlineScript: |
                      echo "=== Deployment Outputs ==="
                      az deployment sub show \
                        --name "deploy-$(Build.BuildNumber)" \
                        --query properties.outputs \
                        --output table
```

### Key details in this template

- **`deployment:` vs `job:`** -- A deployment job automatically creates a deployment record in
  Azure DevOps. Regular jobs do not. This is important for audit trails and compliance.

- **`strategy: runOnce`** -- We deploy to all targets at once. This is the right choice because
  we have a single Azure subscription. Other strategies like `rolling` (deploy in batches) or
  `canary` (deploy to a subset first) are designed for multi-server application deployments.

- **`checkout: self`** -- Deployment jobs run in a clean workspace. Unlike regular jobs, the
  source code is not automatically checked out. We need this line to make the Bicep files
  available.

- **`--name "deploy-$(Build.BuildNumber)"`** -- Each deployment gets a unique name based on the
  pipeline build number. This makes it easy to find a specific deployment in Azure's deployment
  history and correlate it with the pipeline run that created it.

---

## Main Pipeline: `azure-pipelines.yml`

This is the orchestrator that wires everything together. It defines when the pipeline runs,
what variables are shared across stages, and calls each template in the correct order with the
correct dependencies.

```yaml
trigger:
  branches:
    include:
      - main
  paths:
    include:
      - infra/*

pr:
  branches:
    include:
      - main

pool:
  vmImage: 'ubuntu-latest'

variables:
  - name: serviceConnection
    value: 'azure-azl-sc'
  - name: location
    value: 'westeurope'

stages:
  # Stage 1: Validate all Bicep files
  - template: templates/bicep-validate.yml
    parameters:
      serviceConnection: $(serviceConnection)

  # Stage 2: What-if for dev
  - template: templates/bicep-whatif.yml
    parameters:
      serviceConnection: $(serviceConnection)
      environment: 'dev'

  # Stage 3: Deploy to dev (depends on what-if completing)
  - template: templates/bicep-deploy.yml
    parameters:
      serviceConnection: $(serviceConnection)
      environment: 'dev'
      dependsOn: 'WhatIfdev'

  # Stage 4: What-if for prod (only after dev succeeds)
  - template: templates/bicep-whatif.yml
    parameters:
      serviceConnection: $(serviceConnection)
      environment: 'prod'
      dependsOn: 'Deploydev'

  # Stage 5: Deploy to prod (requires manual approval on 'prod' environment)
  - template: templates/bicep-deploy.yml
    parameters:
      serviceConnection: $(serviceConnection)
      environment: 'prod'
      dependsOn: 'WhatIfprod'
```

### How the stages connect

The `dependsOn` parameter controls the execution order. Each stage waits for the previous one
to succeed before starting:

```
Validate --> WhatIfdev --> Deploydev --> WhatIfprod --> Deployprod
```

If any stage fails, everything after it is skipped. A linting error in Stage 1 prevents
deployment to both dev and prod. A failed dev deployment prevents the pipeline from even
attempting prod.

### Trigger configuration

```yaml
trigger:
  branches:
    include:
      - main
  paths:
    include:
      - infra/*
```

This means the pipeline only runs when:

- A commit is pushed to the `main` branch, **and**
- That commit includes changes to files in the `infra/` directory

Editing documentation, scripts, or pipeline YAML itself does not trigger a deployment. This
prevents unnecessary deployments when we are only updating a README or fixing a comment in
a PowerShell script.

The `pr:` section means the Validate stage also runs on pull requests targeting main, so we
get feedback on whether our Bicep is valid before the PR is merged.

---

## Nightly Compliance Pipeline

In addition to the deployment pipeline, we run a **scheduled compliance pipeline** every night.
This is a core managed services pattern: automated checks that run regardless of code changes,
because someone might have modified resources manually through the Azure portal.

### What it checks

1. **NSG Audit** -- Exports every Network Security Group rule across all resource groups to a
   CSV file. This gives the team a complete snapshot of firewall rules that they can review,
   compare day-over-day, and use for compliance reporting.

2. **VM Schedule Report** -- Checks for development VMs that are tagged with `AutoShutdown=true`
   but are still running. This catches the common scenario where a developer manually starts a
   VM for testing and forgets to shut it down. Dev VMs with Firewall and Bastion disabled can
   still cost money if the VMs themselves are running 24/7.

3. **Publish Artifacts** -- The NSG audit CSV is published as a downloadable pipeline artifact.
   Anyone on the team can download the latest compliance report from the Azure DevOps pipeline
   run.

### Full pipeline: `nightly-compliance.yml`

```yaml
schedules:
  - cron: '0 2 * * *'
    displayName: 'Nightly compliance check'
    branches:
      include:
        - main
    always: true

pool:
  vmImage: 'ubuntu-latest'

steps:
  - task: AzurePowerShell@5
    displayName: 'NSG Audit'
    inputs:
      azureSubscription: 'azure-azl-sc'
      ScriptType: 'FilePath'
      ScriptPath: 'scripts/powershell/Invoke-NsgAudit.ps1'
      ScriptArguments: '-OutputPath "$(Build.ArtifactStagingDirectory)/nsg-audit.csv"'
      azurePowerShellVersion: 'LatestVersion'

  - task: AzurePowerShell@5
    displayName: 'VM Schedule Report'
    inputs:
      azureSubscription: 'azure-azl-sc'
      ScriptType: 'InlinePowerShell'
      Inline: |
        # Report VMs that are running but tagged for auto-shutdown
        # (catches VMs that were manually started and never stopped)
        $runningDevVms = Get-AzVM -Status | Where-Object {
            $_.ResourceGroupName -like "rg-spoke-dev-*" -and
            $_.PowerState -eq 'VM running' -and
            $_.Tags['AutoShutdown'] -eq 'true'
        }
        if ($runningDevVms.Count -gt 0) {
            Write-Host "##vso[task.logissue type=warning]$($runningDevVms.Count) dev VMs are running with AutoShutdown=true"
            $runningDevVms | ForEach-Object { Write-Host "  - $($_.Name) in $($_.ResourceGroupName)" }
        } else {
            Write-Host "All auto-shutdown VMs are properly deallocated."
        }
      azurePowerShellVersion: 'LatestVersion'

  # Publish the NSG audit CSV as a pipeline artifact for download
  - task: PublishBuildArtifacts@1
    displayName: 'Publish Compliance Reports'
    inputs:
      PathtoPublish: '$(Build.ArtifactStagingDirectory)'
      ArtifactName: 'compliance-reports'
    condition: always()
```

### Understanding the schedule

The cron expression `0 2 * * *` breaks down as:

| Field | Value | Meaning |
|-------|-------|---------|
| Minute | `0` | At minute 0 |
| Hour | `2` | At 2:00 AM |
| Day of month | `*` | Every day |
| Month | `*` | Every month |
| Day of week | `*` | Every day of the week |

This runs at **2:00 AM UTC**, which is **3:00 AM Amsterdam time** (CET/CEST). We choose the
middle of the night because the compliance checks query Azure APIs and we want them to run
during off-peak hours.

The `always: true` setting is important. Without it, Azure DevOps would skip the scheduled run
if no code has changed since the last run. But compliance checks need to run every night
regardless, because someone could have changed a resource manually in the Azure portal.

---

## Key Concepts Explained

### Service Connection: `azure-azl-sc`

A **service connection** is how Azure DevOps authenticates to our Azure subscription. Instead
of using a personal account (which would break when that person leaves the company), we create
a **service principal** -- a dedicated identity for the pipeline -- and register it as a service
connection in Azure DevOps.

The service connection `azure-azl-sc` (Azure Landing Zone Service Connection) is configured
once in **Azure DevOps Project Settings > Service Connections**. It stores:

- The Azure subscription ID
- The service principal's client ID and secret (or certificate)
- The Azure AD tenant ID

Every `AzureCLI@2` and `AzurePowerShell@5` task references this connection via the
`azureSubscription` parameter. The pipeline agent uses it to authenticate before running
any Azure commands.

### Approval Gates

Approval gates are **not configured in YAML**. They are set up in the Azure DevOps web
interface:

1. Go to **Pipelines > Environments**
2. Click on the `prod` environment
3. Click **Approvals and checks**
4. Add an **Approvals** check and select the approvers

When the pipeline reaches the `Deploy (prod)` stage, it pauses and sends a notification (email,
Teams, or Slack) to the configured approvers. They can review the what-if output from Stage 4,
check the pipeline logs, and then click **Approve** or **Reject**.

This separation is intentional. The YAML defines *what* to deploy. The environment configuration
defines *who* can approve it. This means we can change approvers without modifying the pipeline
code.

### Pipeline Artifacts

The nightly compliance pipeline publishes its reports as **pipeline artifacts**. These are files
attached to a pipeline run that anyone on the team can download.

To access them:

1. Go to the pipeline run in Azure DevOps
2. Click the **Artifacts** button (or the "1 published" link)
3. Download the `compliance-reports` artifact
4. Inside we will find `nsg-audit.csv` and any other reports

Artifacts are retained according to our Azure DevOps retention policy (default: 30 days).
This gives us 30 days of nightly compliance snapshots to compare.

### Trigger: Only `infra/*` Changes

The pipeline trigger is scoped to the `infra/` directory:

```yaml
trigger:
  paths:
    include:
      - infra/*
```

This means the deployment pipeline is **not triggered** by changes to:

- `docs/` -- Documentation changes do not affect infrastructure
- `scripts/` -- Operational scripts run independently
- `pipelines/` -- Pipeline YAML changes are picked up on the next triggered run
- `policies/` -- Azure Policy definitions are managed separately
- `README.md`, `DECISIONS.md`, etc.

Only changes to Bicep files, parameter files, and modules inside `infra/` trigger the
pipeline. This avoids unnecessary deployments and keeps the pipeline focused on
infrastructure changes.

---

## File Reference

All pipeline files live in the `pipelines/` directory:

```
pipelines/
  azure-pipelines.yml                    # Main 5-stage orchestrator
  templates/
    bicep-validate.yml                   # Stage 1: lint, build, validate
    bicep-whatif.yml                     # Stage 2 & 4: preview changes
    bicep-deploy.yml                     # Stage 3 & 5: deploy infrastructure
  scheduled/
    nightly-compliance.yml               # Nightly NSG audit + VM schedule check
```
