# ALZ

A production Azure Landing Zone for a fictional managed services client, built entirely in Bicep and deployed through Azure DevOps. This project simulates the infrastructure that an Azure Dev delivers when onboarding a new enterprise client.

---

## Ⅰ. Tech Stack

Before diving into what we built, here's the tooling and why each was chosen:

| Tool                          | What it is                                                                                                                                            | Why we use it                                                                                                                                        |
| ----------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Bicep**                     | Azure's native Infrastructure as Code language. It compiles to ARM templates but is 10x more readable. You write `.bicep` files that describe what Azure resources you want, and Azure creates them. | Azure-native, no state file (unlike Terraform), first-class VS Code support.
| **Azure CLI**                 | Command-line tool to manage Azure. `az deployment sub create` deploys our Bicep. `az vm show` inspects resources.                                     | Needed for deployments, scripting, and pipeline tasks.                                                                                               |
| **Azure DevOps**              | Microsoft's CI/CD platform. Hosts our git repo, runs our pipelines, manages approvals.                                                                | Our example lives in the Microsoft ecosystem. Not GitHub, Azure DevOps is where their teams work.                                                       |
| **PowerShell 7**              | Scripting language with the `Az` module for Azure automation.                                                                                         | Operational scripts for auditing and cost management. Standard tool for Windows-heavy Azure environments.                                            |
| **KQL (Kusto Query Language)**| SQL-like language for querying Log Analytics. `Perf \| where CounterName == "% Processor Time"` finds high-CPU VMs.                                   | Used daily for 3rd-line support to investigate incidents.                                                                                   |

---

## Ⅱ. What We Provides in our Mock-Project

### 1. Hub-spoke network topology

Azure Firewall for centralized traffic inspection.

***What is Hub-spoke network topology?***

A network design where one central VNet (the "hub") connects to multiple isolated VNets (the "spokes") via peering. All traffic between spokes must flow through the hub, where Azure Firewall inspects it. Think of Schiphol airport, you don't fly direct between small cities, you connect through the hub. Same concept: spoke-prod doesn't talk directly to spoke-dev. Traffic goes spoke → hub (firewall inspects) → other spoke.

![Hub-spoke network topology](https://media.licdn.com/dms/image/v2/D4E12AQE6biI1T28YBw/article-cover_image-shrink_600_2000/article-cover_image-shrink_600_2000/0/1656349277712?e=2147483647&v=beta&t=NoD6tGrWEnZjWdZ4eyNoHqDALJLrWNvJNxrbPkTUAgQ)

---

### 2. Three VNets

Hub (shared services), Production spoke, Development spoke.

***What are VNets?***

A Virtual Network (VNet) is your private network in Azure. It's an isolated chunk of IP address space where you place your resources (VMs, databases, etc.). Resources inside a VNet can talk to each other by default. Resources in different VNets are completely isolated, they can't see each other unless you explicitly connect them with peering.

We have three:

- **Hub** (10.0.0.0/16), shared infrastructure: Firewall, Bastion, jumpbox VM
- **Spoke Prod** (10.1.0.0/16), production workloads
- **Spoke Dev** (10.2.0.0/16), development workloads

![VNets](https://aidanfinn.com/wp-content/uploads/2015/10/Azure-Virtual-Network-1024x522.png)

---

### 3. NSGs (Network Security Groups)

Web, App, and Data subnets with NSGs enforcing traffic flow.

***What are Network Security Groups?***

An NSG is a lightweight firewall at the subnet level. It contains rules that allow or deny traffic based on 5 things: source IP, source port, destination IP, destination port, and protocol. Rules are checked by priority (lowest number first). Once a match is found, processing stops.

We use NSGs to enforce the **N-tier security model**: each subnet can only talk to its direct neighbor.

```text
Internet → Firewall → [Web Subnet] → [App Subnet] → [Data Subnet]
                         ↑                ↑               ↑
                     NSG: allow       NSG: allow       NSG: allow
                     from Firewall    from Web only    from App only
```

Web can't skip App to reach Data. If a hacker compromises the web server, they still can't reach the database directly.

![NSGs](https://learn.microsoft.com/en-us/azure/azure-local/manage/media/create-network-security-groups/network-security-groups.png?view=azloc-2601#lightbox)

---

### 4. Azure Bastion

Secure VM access without public IPs.

***What is Azure Bastion?***

Bastion provides RDP/SSH access to VMs directly through the Azure portal browser, without exposing any public IP on the VM. You click "Connect → Bastion" in the portal, enter credentials, and get a browser-based session.

The connection goes: Your browser → TLS over Azure backbone → Bastion → VM's private IP. Nothing is exposed to the internet. The VM has no public IP at all. This is how engineers access client VMs daily.

![Azure Bastion](https://cdn.educba.com/academy/wp-content/uploads/2020/11/virtual-network.jpg)

---

### 5. Centralized Monitoring

Log Analytics workspace with diagnostic settings on all resources using Azure Monitor.

***What is Azure Monitor?***

Azure Monitor is the umbrella service for all monitoring in Azure. Under it, the key components we use:

- **Log Analytics Workspace** : the central database where every resource sends its logs. Firewall logs, NSG flow logs, VM metrics, Key Vault audit trails, all in one place, all queryable with KQL.
- **Diagnostic Settings** : the "pipes" that connect each resource to the workspace. Without them, resources generate data but don't send it anywhere.
- **Azure Monitor Agent** : installed on VMs to collect OS-level data (CPU, memory, event logs) and send it to the workspace.
- **Alert Rules** : "if CPU > 90% for 5 minutes, email the ops team." Automated incident detection.
- **Action Groups** : who gets notified and how (email, SMS, webhook to ServiceNow).

Without centralized monitoring, troubleshooting means checking each resource individually. With it, one KQL query searches across everything.

![Azure Monitor](https://learn.microsoft.com/en-us/azure/azure-monitor/logs/media/data-platform-logs/logs-structure.png)

---

### 6. Automated Backup

Recovery Services Vault with daily backup policies.

  - ***What is Azure Recovery Services Vault?***
   
![Azure Recovery Services Vault](https://learn.microsoft.com/en-us/azure/backup/media/backup-azure-vms-introduction/vmbackup-architecture.png)


A vault that stores backup copies of your VMs. Azure takes a snapshot of the VM's disks on a schedule (we set daily at 2 AM), compresses and encrypts it, and stores it in the vault. If ransomware hits, someone deletes the wrong data, or a disk corrupts, you restore from the vault.

Key concepts:

- **RPO (Recovery Point Objective)** : how much data can you afford to lose? Our daily backup = max 24 hours of data loss.
- **RTO (Recovery Time Objective)** : how fast can you restore? Depends on VM size, typically 30-60 minutes.
- **Retention** : how long backups are kept. We keep daily backups for 30 days, weekly for 12 weeks.
- First backup is full (copies everything). After that, only changed blocks are copied (incremental). This is why the first backup takes hours but subsequent ones take minutes.

---

### 7. Key Vault

Secrets management with RBAC authorization.

***What is Azure Key Vault?***

![Azure Key Vault](https://learn.microsoft.com/en-us/azure/key-vault/media/azure-key-vault.png)


A secure vault for passwords, API keys, connection strings, and certificates. Instead of putting the jumpbox admin password in a config file (which ends up in git), you store it in Key Vault and reference it at deployment time.

Why RBAC authorization (instead of the older "access policies"):

- Same permission model as every other Azure resource, one consistent system
- Granular roles: `Key Vault Secrets User` (read only) vs `Key Vault Secrets Officer` (read + write)
- All permission changes show up in Azure Activity Log

Key safety features:

- **Soft delete** : "deleted" secrets are recoverable for 90 days
- **Purge protection** : even soft-deleted secrets can't be permanently removed during the retention period

---

### 8. Azure Policies

Tag enforcement, location restriction, and public IP denial.

***What are Azure Policies?***

![Azure Key Vault](https://kodekloud.com/kk-media/image/upload/v1752881781/notes-assets/images/Microsoft-Azure-Security-Technologies-AZ-500-Configure-Azure-Initiatives/azure-policy-use-cases-infographic.jpg)

Rules that Azure enforces automatically on every resource operation (create, update). They're governance on autopilot. Even if someone goes into the Azure portal and tries to create a resource manually, the policy blocks it if it violates the rules.

Our three policies:

| Policy              | What it does                                                                                  | Why                                                                                                      |
| ------------------- | --------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------- |
| **require-tags**    | Denies resource creation without `Environment`, `ManagedBy`, `CostCenter`, `Project` tags     | Without tags, you can't track costs or ownership. Untagged resources are invisible to cost reports.       |
| **allowed-locations** | Only allows West Europe (Amsterdam) and North Europe (Dublin)                                | Data sovereignty. Dutch clients need data in the EU. Prevents accidental deployment to US or Asia.       |
| **deny-public-ip**  | Blocks public IP creation on spoke resource groups                                            | A public IP on a spoke VM bypasses the Firewall entirely. All internet access must go through the hub.   |

---

### 9. Operational Automation

PowerShell scripts for NSG auditing and VM cost optimization.

***What do these scripts do?***

![Azure Key Vault](https://wmatthyssen.com/wp-content/uploads/2022/08/featured_image-9.jpg?w=950)


These are the kind of scripts managed services team runs daily:

**NSG Audit (`Invoke-NsgAudit.ps1`)** : Exports every NSG rule across all resource groups to a CSV. Used to catch: rules allowing traffic from "Any" source (security risk), rules on unexpected ports (shadow IT), duplicate rules (misconfiguration). Runs nightly via the compliance pipeline.

**VM Schedule (`Set-VmSchedule.ps1`)** : Starts or stops VMs based on tags. VMs tagged `AutoShutdown=true` get stopped at 7 PM and started at 8 AM. Dev VMs don't need to run 24/7, this saves ~70% on compute costs. That's real money: 10 dev VMs x 35/month x 70% = 245/month saved.

---

### 10. CI/CD Pipeline

Multi-stage Azure DevOps pipeline with validation, what-if preview, and approval gates.

***What does the pipeline do?***


![Azure CI/CD](https://juliocasal.com/assets/images/ci-cd-pipeline.jpg)

Instead of deploying from your laptop with `az deployment`, you push code to the repo and the pipeline handles everything:

```text
Push to main
    ↓
Stage 1: VALIDATE
    Lint all Bicep files (catch syntax errors)
    Compile to ARM (catch type errors)
    ↓
Stage 2: WHAT-IF (dev)
    Show exactly what WOULD change, without changing anything
    "These 3 resources will be created, this 1 will be modified"
    ↓
Stage 3: DEPLOY (dev)
    Actually deploy to dev environment
    ↓
Stage 4: WHAT-IF (prod)
    Preview production changes
    ↓
Stage 5: DEPLOY (prod) ← PAUSES HERE
    Waits for manual approval from a human
    Engineer reviews the what-if output
    Clicks "Approve" → deployment proceeds
```

The approval gate on prod is critical. You never deploy to production without a human reviewing what's about to change. This is how we prevents "oops I deleted the client's firewall" incidents.
