# Troubleshooting - Errors We Hit and How We Fixed Them

Deploying an Azure Landing Zone from scratch is never error-free. This page documents every
error we encountered across four rounds of debugging, what caused each one, and the exact fix
we applied. If there is one page in this project worth reading carefully, it is this one - real
deployments have real problems, and understanding why something broke teaches more than getting
it right the first time ever could.

The errors are grouped by the stage in which they appeared:

1. **Local Bicep build** - caught by our `validate-bicep.sh` script before anything touches Azure
2. **Azure API validation** - caught by `az deployment sub validate` before any resources are created
3. **Deployment** - only surfaced during an actual `az deployment sub create`
4. **Post-deployment** - issues found when verifying or operating the deployed resources

---

## Round 1: Local Bicep Build Errors

These errors were caught by running our local validation script:

```bash
bash scripts/bash/validate-bicep.sh
```

This script runs `az bicep lint` and `az bicep build` against every `.bicep` file in the project.
It is fast, free, and catches most syntax and structural problems before we ever talk to Azure.

---

### Error 1: BCP165 - Scope Mismatch in Peering Module

**Error message:**

```
A resource's computed scope "resourceGroup" must match the scope of the Bicep file "resourceGroup"
```

**File:** `infra/modules/networking/peering.bicep`

**What happened:**

VNet peering in Azure is a two-sided relationship. If the hub VNet lives in resource group A
and the spoke VNet lives in resource group B, we need to create a peering resource in both
resource groups - one pointing hub-to-spoke and one pointing spoke-to-hub.

Our original `peering.bicep` module tried to do both sides in a single file. It deployed into
the hub's resource group but then attempted to create a child resource on the spoke VNet, which
lives in a different resource group. Bicep does not allow cross-scope child resources within the
same module - each module can only operate within the scope it was deployed to.

Think of it like a filing clerk who is assigned to one department. They can file papers in their
own department's cabinet, but they cannot reach into another department's cabinet from where they
are standing. They would need a colleague in the other department to do that.

**Fix:**

We split the peering into two separate modules, each deployed to its own resource group:

- `peering.bicep` - creates the hub-to-spoke peering (deployed to the hub resource group)
- `peering-spoke-to-hub.bicep` - creates the spoke-to-hub peering (deployed to the spoke resource group)

In `main.bicep`, the orchestrator calls each module with the correct `scope:` set to the
appropriate resource group.

---

### Error 2: Unused Parameter in alerts.bicep

**Error message:**

```
Parameter "location" is declared but never used
```

**File:** `infra/modules/monitoring/alerts.bicep`

**What happened:**

The `location` parameter was declared at the top of the module, but none of the resources inside
the module referenced it. Azure Monitor alert rules are global resources - they use
`location: 'global'` rather than a specific Azure region. The parameter was simply never needed.

Bicep treats unused parameters as errors (not just warnings) because they indicate dead code that
confuses anyone reading the module. If a parameter exists, the reader assumes it matters.

**Fix:**

Removed the unused `location` parameter from `alerts.bicep` and removed the corresponding
`location:` argument from every place in `main.bicep` that called the alerts module.

---

### Error 3: Hardcoded URLs in firewall.bicep

**Error message:**

```
A value of "management.azure.com" is hardcoded - use environment() instead
```

**File:** `infra/modules/networking/firewall.bicep`

**What happened:**

The Bicep linter flagged hardcoded Azure management URLs in our firewall FQDN (Fully Qualified
Domain Name) rules. The linter's reasoning is sound: Azure exists in multiple clouds (public,
government, China), and each cloud has different hostnames. Hardcoding `management.azure.com`
would break in Azure Government where the URL is `management.usgovcloudapi.net`.

The linter suggests using `environment().resourceManager` instead, which returns the correct URL
for whichever cloud the deployment is running in.

We initially followed the linter's advice and switched to `environment()` functions. However,
this later caused a deployment error (see Error 9 below) because `environment().resourceManager`
returns the full URL including the protocol - `https://management.azure.com/` - while Azure
Firewall FQDN rules expect just the hostname - `management.azure.com`.

**Final fix:**

We reverted to plain hostnames and suppressed the linter warning on each line. This is one of
those cases where the linter rule does not apply to our specific context:

```bicep
targetFqdns: [
  #disable-next-line no-hardcoded-env-urls
  'management.azure.com'
  #disable-next-line no-hardcoded-env-urls
  'login.microsoftonline.com'
]
```

The `#disable-next-line` comment tells Bicep "yes, we know, and we have a good reason." This is
preferable to disabling the rule project-wide, because we still want the linter to catch
hardcoded URLs elsewhere.

---

### Error 4: BCP318 - Nullable Resource Access

**Error message:**

```
The expression of type "resource" may be null. Use non-null assertion (!) to access properties
```

**File:** `infra/modules/networking/firewall.bicep`

**What happened:**

The Azure Firewall and its public IP address are conditionally deployed - they only exist when
`deployFirewall` is `true`. This saves significant cost in dev environments (Azure Firewall costs
approximately EUR 912 per month).

However, the module's `output` section tried to read properties from these conditional resources.
Bicep correctly warns that when `deployFirewall` is `false`, these resources will not exist, so
accessing their properties would fail.

This is similar to how a programming language warns about potential null pointer exceptions. If a
variable might not exist, we need to tell the compiler we have handled that case.

**Fix:**

We added the `!` non-null assertion operator combined with a ternary check:

```bicep
output firewallPrivateIp string = deployFirewall ? firewall!.properties.ipConfigurations[0].properties.privateIPAddress : ''
```

This reads as: "If the firewall was deployed, access its private IP (and we promise it is not
null). Otherwise, return an empty string." The `!` after `firewall` is the non-null assertion  - 
it tells Bicep "trust me, if we got past the `deployFirewall` check, this resource exists."

---

### Error 5: Missing @secure() Decorator

**Error message:**

```
Parameter name "secretsOfficerObjectId" suggests it may contain sensitive data - add @secure()
```

**File:** `infra/modules/security/keyvault.bicep`

**What happened:**

Bicep's linter scans parameter names for keywords that suggest sensitive data - words like
"secret", "password", "key", and "token". The parameter `secretsOfficerObjectId` triggered this
rule because of the word "secrets" in its name.

When a parameter is marked `@secure()`, Bicep ensures its value is never logged in deployment
outputs or visible in the Azure portal's deployment history. This is important for passwords and
connection strings. In our case, the value is just an Azure AD object ID (a GUID), which is not
truly sensitive - but following the linter's advice is harmless and keeps our code consistent.

**Fix:**

Added the `@secure()` decorator above the parameter declaration:

```bicep
@secure()
param secretsOfficerObjectId string
```

---

## Round 2: Azure API Validation Errors

These errors were caught by running validation against the Azure API:

```bash
az deployment sub validate \
  --location westeurope \
  --template-file infra/main.bicep \
  --parameters infra/main.dev.bicepparam \
  --parameters jumpboxAdminPassword='ValidationOnly123!'
```

This command sends our compiled template to Azure for validation without creating any resources.
Azure checks things that the local linter cannot - like whether resource types exist, whether API
versions are valid, and whether parameter files are complete.

---

### Error 6: BCP258 - Missing Parameter in .bicepparam

**Error message:**

```
The following parameters are declared in the Bicep file but missing in the params file: "jumpboxAdminPassword"
```

**What happened:**

This is a subtle but important distinction in Bicep parameter files. When a `.bicepparam` file
uses the `using` keyword to reference a `.bicep` file, it must provide values for ALL parameters
declared in that Bicep file. We cannot mix `.bicepparam` with CLI `--parameters` overrides - the
two approaches are mutually exclusive.

We were trying to pass `jumpboxAdminPassword` via the CLI while providing all other parameters
through the `.bicepparam` file. Bicep rejected this because the `.bicepparam` file claims to be
the complete source of parameter values (via the `using` keyword), but it was missing one.

**Fix:**

We added `readEnvironmentVariable()` to both parameter files so the password comes from an
environment variable at deployment time:

```bicep
param jumpboxAdminPassword = readEnvironmentVariable('JUMPBOX_ADMIN_PASSWORD')
```

Before deploying, we set the environment variable:

```bash
export JUMPBOX_ADMIN_PASSWORD='YourStrongPassword123!'
```

This approach keeps the password out of source code and out of CLI history, which is good
security practice. The password only exists in the shell session's memory.

---

### Error 7: Unused Parameters in peering.bicep

**Error message:**

Warnings about `hubVnetId`, `spokeResourceGroupName`, and `useRemoteGateways` being declared but
never used.

**What happened:**

When we split the peering module into two files in Round 1 (Error 1), we removed the
spoke-to-hub logic from `peering.bicep` but forgot to remove the parameters that only the
spoke-to-hub side needed. These orphaned parameters were left behind like tools on a workbench
after the job that needed them moved to a different room.

**Fix:**

Removed the unused parameters from `peering.bicep` and cleaned up all the corresponding
arguments at every call site in `main.bicep`. This is a common follow-up task after any
refactoring - always check for leftover references.

---

## Round 3: Deployment Errors

These errors only appeared during an actual deployment:

```bash
az deployment sub create \
  --location westeurope \
  --template-file infra/main.bicep \
  --parameters infra/main.dev.bicepparam
```

Local validation and API validation both passed, but the real deployment hit issues that can only
be discovered when Azure actually tries to create resources.

---

### Error 8: MissingSubscriptionRegistration

**Error message:**

```
The subscription is not registered to use namespace 'Microsoft.Network'
```

**What happened:**

Azure organizes its services into "resource providers" - `Microsoft.Network` handles VNets and
firewalls, `Microsoft.Compute` handles VMs, `Microsoft.KeyVault` handles key vaults, and so on.
A subscription must explicitly register each provider before it can create resources of that type.

Brand new subscriptions (or lab/sandbox subscriptions) often have very few providers registered
by default. When our deployment tried to create a VNet, Azure said "I do not know what
Microsoft.Network is" because that provider was not registered.

Think of it like enabling features on a phone plan. The phone can technically make international
calls, but the carrier needs to enable that feature on the account first.

**Fix:**

We registered all the resource providers our landing zone needs:

```bash
az provider register --namespace Microsoft.Network
az provider register --namespace Microsoft.Compute
az provider register --namespace Microsoft.KeyVault
az provider register --namespace Microsoft.RecoveryServices
az provider register --namespace Microsoft.OperationalInsights
az provider register --namespace Microsoft.Insights
```

Registration takes a minute or two per provider. We can check the status with:

```bash
az provider show --namespace Microsoft.Network --query "registrationState"
```

It should return `"Registered"` when ready.

---

### Error 9: FirewallPolicyApplicationRuleInvalidTargetFqdn

**Error message:**

```
Target FQDN 'https://management.azure.com/' is invalid
```

**What happened:**

This is the follow-up to Error 3. After the linter told us to use `environment().resourceManager`
instead of hardcoded hostnames, we dutifully made the change. The linter was happy. Local
validation passed. API validation passed.

But when Azure Firewall actually tried to apply the rule, it rejected the value. Here is why:

- `environment().resourceManager` returns `https://management.azure.com/` (full URL with protocol
  and trailing slash)
- Azure Firewall FQDN rules expect just the hostname: `management.azure.com` (no protocol, no
  trailing slash)

These are different formats for different purposes. An FQDN rule matches DNS names, not full URLs.
Including `https://` in an FQDN rule is like putting a street name where a city name is expected.

**Fix:**

We reverted to plain hostnames with linter suppression (see Error 3 for the final code). This is
a good example of why automated tools should be trusted but verified - the linter gave advice
that was correct in general but wrong for this specific resource type.

---

### Error 10: SkuNotAvailable - Standard_B2s

**Error message:**

```
The requested VM size Standard_B2s is not available in westeurope
```

**What happened:**

Azure VM sizes (called SKUs) are not available in every region at all times. Microsoft
periodically retires older SKUs and replaces them with newer versions. The `Standard_B2s` SKU
had been retired or restricted in the West Europe region by the time we deployed.

This is one of those errors that works fine for months and then suddenly fails when Microsoft
updates their infrastructure. It is not a code error - it is an availability issue.

**Fix:**

First, we checked which B2-series SKUs were available in our region:

```bash
az vm list-skus --location westeurope --size Standard_B2 --output table
```

This showed that `Standard_B2s_v2` was available. We updated the default VM size in
`vm-jumpbox.bicep` and the corresponding value in `main.bicep`.

The lesson here is to always verify SKU availability before choosing a VM size, especially when
deploying to a new region or after a long gap between deployments.

---

## Round 4: Post-Deployment Issues

These issues appeared after the infrastructure was successfully deployed, while verifying and
operating the environment.

---

### Issue 11: ResourceGroupNotFound - LabResourceGroup

**Error message:**

```
Resource group 'LabResourceGroup' could not be found
```

**What happened:**

After deployment, we ran `az network vnet list` to verify our VNets were created. The command
returned an error about a resource group we never created called `LabResourceGroup`.

The problem is that `az network vnet list` without a `--resource-group` flag queries ALL
resource groups in the subscription. If the subscription has stale or orphaned resource groups
from previous lab exercises or Azure Sandbox environments, the CLI will try to query those too  - 
and fail if they are in a broken state.

This is not a problem with our deployment. It is a problem with how we queried Azure.

**Fix:**

Always scope list commands to a specific resource group:

```bash
# Wrong - queries all resource groups, including stale ones
az network vnet list --output table

# Right - scoped to the resource group we care about
az network vnet list --resource-group rg-hub-weu --output table
```

This is a good habit in general. Scoped queries are faster, return less noise, and avoid errors
from unrelated resources in the subscription.

---

### Issue 12: Get-AzNetworkSecurityGroup Not Recognized

**Error message:**

```
The term 'Get-AzNetworkSecurityGroup' is not recognized
```

**What happened:**

We tried to run the NSG audit script (`scripts/powershell/Invoke-NsgAudit.ps1`), but PowerShell
did not recognize the `Get-AzNetworkSecurityGroup` cmdlet. This cmdlet comes from the **Az
PowerShell module**, which is separate from both PowerShell itself and the Azure CLI.

Having Azure CLI installed does not mean the Az PowerShell module is installed - they are
completely independent tools that happen to manage the same platform. Azure CLI is a standalone
program (`az`). The Az PowerShell module is a set of cmdlets that run inside PowerShell (`pwsh`).

**Fix:**

Install the Az PowerShell module:

```bash
pwsh -Command "Install-Module -Name Az -Scope CurrentUser -Force"
```

This installs the module for the current user only (`-Scope CurrentUser`), which does not require
administrator privileges. The `-Force` flag skips confirmation prompts.

After installation, the NSG audit script runs successfully:

```bash
pwsh scripts/powershell/Invoke-NsgAudit.ps1 -OutputPath ./nsg-audit.csv
```

---

## Lessons Learned

These twelve errors taught us several principles that apply to any Azure deployment:

1. **Always validate locally first.** Running `validate-bicep.sh` catches most errors in seconds
   and costs nothing. Do not skip this step.

2. **Then validate against the Azure API.** The local linter cannot check whether resource types
   exist, whether API versions are valid, or whether parameter files are complete.
   `az deployment sub validate` catches these.

3. **Register resource providers early.** Before the first deployment to a new subscription, register
   all the providers the project needs. This avoids confusing errors during deployment.

4. **Scope CLI commands to specific resource groups.** Always use `--resource-group` on list commands.
   Unscoped queries are slower and can fail on stale resources.

5. **Test `environment()` function outputs.** Functions like `environment().resourceManager` return
   full URLs with protocols, not bare hostnames. Always verify what a function actually returns
   before using it in a context that expects a specific format.

6. **Check VM SKU availability.** VM sizes get retired over time. Always verify availability with
   `az vm list-skus` before choosing a size, especially after a gap between deployments.

7. **Read error messages carefully.** Azure error messages are verbose but usually tell us exactly
   what went wrong. The error `Target FQDN 'https://management.azure.com/' is invalid` tells us
   the value includes a protocol that should not be there - if we read it closely enough.

8. **Clean up after refactoring.** When we split a module or move logic between files, always check
   for orphaned parameters, unused variables, and stale references at call sites.
