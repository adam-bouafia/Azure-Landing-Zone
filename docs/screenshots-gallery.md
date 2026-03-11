# Screenshots Gallery

This page contains every screenshot captured during the deployment of both the **dev** and
**prod** environments. They are organized by category so we can quickly find what we need.

In total we captured **67 screenshots** across four categories: portal views, resource topology
diagrams, CLI verification outputs, and early dev-only captures.

---

## Azure Portal - Resource Groups and Overview

These screenshots show the Azure Portal views of our resource groups and their contents.

### All Resource Groups

![All Resource Groups - Portal](screenshots/01-portal-resource-groups-list.png)

![Resource Groups - Portal (prod deployed)](screenshots/portal-resource-groups-list.png)

![Resource Groups - Portal (all resources view)](screenshots/portal-all-resources-list.png)

![Resource Groups - after prod deploy](screenshots/portal-resource-groups-list.png)

### Hub Resource Group (rg-hub-weu)

Contains the Firewall, Bastion, Jumpbox VM, VNet, NSGs, public IPs, and NIC.

![Hub RG - Resources List](screenshots/03-rg-hub-weu-resources.png)

![Hub RG - Overview with resource count](screenshots/18-rg-hub-weu-overview-with-resources.png)

### Shared Resource Group (rg-shared-weu)

Contains Key Vault, Log Analytics, Recovery Services Vaults, Storage Accounts, Alerts, and VMInsights.

![Shared RG - Resources List](screenshots/04-rg-shared-weu-resources.png)

![Shared RG - Overview](screenshots/17-rg-shared-weu-overview-small.png)

### Spoke Dev Resource Group (rg-spoke-dev-weu)

Contains NSGs for web, app, and data subnets, plus the spoke VNet.

![Spoke Dev RG - Resources](screenshots/05-rg-spoke-dev-weu-resources.png)

![Spoke Dev RG - Overview with NSGs](screenshots/19-rg-spoke-dev-weu-overview-with-nsgs.png)

### Spoke Prod Resource Group (rg-spoke-prod-weu)

![Spoke Prod RG - Initial (before prod deploy)](screenshots/20-rg-spoke-prod-weu-empty-failed.png)

### NetworkWatcherRG

This resource group is auto-created by Azure when Network Watcher is enabled.

![Network Watcher RG](screenshots/21-rg-networkwatcher-overview.png)

![Network Watcher Overview](screenshots/02-network-watcher-overview.png)

### Recent Resources (All RGs)

![Recent Resources - All Resource Groups](screenshots/22-recent-resources-all-rgs.png)

---

## Azure Portal - Networking

### Hub VNet (vnet-hub-weu)

![Hub VNet - Overview](screenshots/13-vnet-hub-weu-overview.png)

![Hub VNet - Capabilities](screenshots/portal-hub-vnet-overview-capabilities.png)

![Hub VNet - Address Space and Peerings](screenshots/portal-hub-vnet-address-space-peerings.png)

![Hub VNet - Connected Devices](screenshots/portal-hub-vnet-connected-devices.png)

![Hub VNet - Peering to Prod (Connected)](screenshots/portal-hub-vnet-peering-prod-connected.png)

### Azure Firewall (afw-hub-weu)

![Firewall - Overview](screenshots/portal-firewall-overview.png)

### Firewall Policy (afwp-hub-weu)

![Firewall Policy - Overview](screenshots/portal-firewall-policy-overview.png)

![Firewall Policy - Properties](screenshots/portal-firewall-policy-properties.png)

![Firewall Policy - Analytics](screenshots/portal-firewall-policy-analytics.png)

![Firewall Policy - Hub Overview (dev)](screenshots/12-firewall-policy-hub-overview.png)

### Azure Bastion (bas-hub-weu)

![Bastion - Overview](screenshots/portal-bastion-overview.png)

### NSG Rules

![NSG App Dev - Rules](screenshots/06-nsg-app-dev-rules.png)

![NSG Data Dev - Rules](screenshots/07-nsg-data-dev-rules.png)

---

## Azure Portal - Compute

### Jumpbox VM (vm-jump-hub-001)

![Jumpbox VM - Overview](screenshots/portal-jumpbox-vm-overview.png)

---

## Azure Portal - Shared Services

### Key Vault (kv-alz-dev-001)

![Key Vault - Dev Overview](screenshots/08-keyvault-dev-overview.png)

![Key Vault - Overview](screenshots/portal-keyvault-overview.png)

### Log Analytics

![Log Analytics - Dev Overview](screenshots/09-log-analytics-dev-overview.png)

![Log Analytics - Overview](screenshots/portal-log-analytics-overview.png)

### Storage Account

![Storage Account - Dev Overview](screenshots/10-storage-account-dev-overview.png)

### VMInsights

![VMInsights - Dev Overview](screenshots/11-vminsights-dev-overview.png)

### Recovery Services Vault

![Recovery Services Vault - Prod](screenshots/portal-recovery-services-vault-prod.png)

---

## Resource Topology Diagrams

These are captured from Azure's **Resource Visualizer**, which shows how resources are
connected to each other. These diagrams are invaluable for understanding the relationships
between VNets, subnets, NICs, public IPs, firewalls, and NSGs.

### Full Landing Zone Topology

The complete view of all resources across all resource groups:

![Full Landing Zone Topology](screenshots/topology-full-landing-zone.png)

### Hub Resource Group Topology

![Hub RG - VM, Firewall, NSG, VNet](screenshots/topology-hub-rg-vm-firewall-nsg-vnet.png)

### Hub VNet and Peerings

![Hub VNet - Peering to both spokes with NSGs](screenshots/topology-hub-vnet-peering-spokes-nsg.png)

### Firewall Components

![Firewall - with Public IP and Policy](screenshots/topology-firewall-with-publicip-and-policy.png)

![Firewall Policy - link to Firewall](screenshots/topology-firewall-policy-to-firewall.png)

### Bastion Components

![Bastion - with Public IP](screenshots/topology-bastion-with-publicip.png)

### Jumpbox VM Components

![Jumpbox VM - NIC and OS Disk](screenshots/topology-jumpbox-vm-nic-disk.png)

![OS Disk - Jumpbox](screenshots/topology-osdisk-jumpbox.png)

### Spoke Prod Topology

![Spoke Prod - VNet, NSGs, and Hub connection](screenshots/topology-spoke-prod-vnet-nsgs-hub.png)

![Spoke Prod - VNet and NSGs](screenshots/topology-spoke-prod-vnet-nsgs.png)

![Spoke Prod - VNet and NSGs (alternate view)](screenshots/topology-spoke-prod-vnet-nsgs-alt.png)

### Spoke Dev Topology

![Spoke Dev - VNet and NSGs](screenshots/topology-spoke-dev-vnet-nsgs.png)

![Spoke Dev - VNet and NSGs (alternate view)](screenshots/topology-spoke-dev-vnet-nsgs-alt.png)

### Monitoring Components

![Alert - CPU High](screenshots/topology-alert-cpu-high.png)

![Alert - Disk High](screenshots/topology-alert-disk-high.png)

![Alert - Memory Low](screenshots/topology-alert-memory-low.png)

![VMInsights + Log Analytics - Prod](screenshots/topology-vminsights-log-analytics-prod.png)

### Other Resources

![Recovery Services Vault - Prod topology](screenshots/topology-recovery-services-vault-prod.png)

![Storage Account - Prod topology](screenshots/topology-storage-account-prod.png)

### Resource Visualizer - Per Resource Group

![Resource Visualizer - Hub RG](screenshots/14-resource-visualizer-rg-hub.png)

![Resource Visualizer - Shared RG](screenshots/15-resource-visualizer-rg-shared.png)

![Resource Visualizer - Spoke Dev RG](screenshots/16-resource-visualizer-rg-spoke-dev.png)

---

## CLI Verification Screenshots

These screenshots show the Azure CLI commands we ran to verify the deployment was successful.
Each command is scoped to a specific resource group to avoid errors from stale resources.

![CLI - Resource Groups List](screenshots/23-cli-resource-groups-list.png)

![CLI - VNet List](screenshots/24-cli-vnet-list-all.png)

![CLI - Key Vault List](screenshots/25-cli-keyvault-list.png)

![CLI - Log Analytics List](screenshots/26-cli-log-analytics-list.png)

![CLI - Backup Vault List](screenshots/27-cli-backup-vault-list.png)

![CLI - VM List (Jumpbox)](screenshots/28-cli-vm-list-jumpbox.png)

![CLI - Firewall List (Succeeded)](screenshots/29-cli-firewall-list-succeeded.png)

![CLI - Bastion List](screenshots/30-cli-bastion-list.png)

![CLI - Resource Groups after Prod Deploy](screenshots/31-cli-resource-groups-prod-deploy.png)

![CLI - NSG Audit Results](screenshots/32-cli-nsg-audit-results.png)

![CLI - Deployment Status Succeeded](screenshots/33-cli-deployment-status-succeeded.png)

---

## Exported CSV Data

We also exported resource data from the Azure Portal as CSV files. This data is referenced
throughout the documentation.

### All Resources (32 total)

Exported from the Azure Portal "All resources" view:

| Name | Type | Resource Group |
|------|------|---------------|
| afw-hub-weu | Firewall | rg-hub-weu |
| afwp-hub-weu | Firewall Policy | rg-hub-weu |
| ag-infra-alerts | Action group | rg-shared-weu |
| alert-vm-cpu-high | Metric alert rule | rg-shared-weu |
| alert-vm-disk-high | Metric alert rule | rg-shared-weu |
| alert-vm-memory-low | Metric alert rule | rg-shared-weu |
| bas-hub-weu | Bastion | rg-hub-weu |
| kv-alz-dev-001 | Key vault | rg-shared-weu |
| log-alz-dev | Log Analytics workspace | rg-shared-weu |
| log-alz-prod | Log Analytics workspace | rg-shared-weu |
| NetworkWatcher_westeurope | Network Watcher | NetworkWatcherRG |
| nic-vm-jump-hub-001 | Network Interface | rg-hub-weu |
| nsg-app-dev | Network security group | rg-spoke-dev-weu |
| nsg-app-prod | Network security group | rg-spoke-prod-weu |
| nsg-data-dev | Network security group | rg-spoke-dev-weu |
| nsg-data-prod | Network security group | rg-spoke-prod-weu |
| nsg-management-hub | Network security group | rg-hub-weu |
| nsg-web-dev | Network security group | rg-spoke-dev-weu |
| nsg-web-prod | Network security group | rg-spoke-prod-weu |
| osdisk-vm-jump-hub-001 | Disk | rg-hub-weu |
| pip-afw-hub-weu | Public IP address | rg-hub-weu |
| pip-bas-hub-weu | Public IP address | rg-hub-weu |
| rsv-alz-dev | Recovery Services vault | rg-shared-weu |
| rsv-alz-prod | Recovery Services vault | rg-shared-weu |
| stdiagalzdev001 | Storage account | rg-shared-weu |
| stdiagalzprod001 | Storage account | rg-shared-weu |
| vm-jump-hub-001 | Virtual machine | rg-hub-weu |
| VMInsights(log-alz-dev) | Solution | rg-shared-weu |
| VMInsights(log-alz-prod) | Solution | rg-shared-weu |
| vnet-hub-weu | Virtual network | rg-hub-weu |
| vnet-spoke-dev-weu | Virtual network | rg-spoke-dev-weu |
| vnet-spoke-prod-weu | Virtual network | rg-spoke-prod-weu |

### Hub VNet Subnets

| Subnet | Address Prefix | Connected Device | NSG |
|--------|---------------|-----------------|-----|
| AzureFirewallSubnet | 10.0.1.0/26 | afw-hub-weu | - |
| AzureBastionSubnet | 10.0.2.0/26 | bas-hub-weu | - |
| snet-management | 10.0.3.0/24 | nic-vm-jump-hub-001 | nsg-management-hub |
| GatewaySubnet | 10.0.4.0/27 | - | - |

### Hub VNet Peerings

| Peering Name | Status | Remote VNet | Gateway |
|-------------|--------|-------------|---------|
| peer-vnet-hub-weu-to-vnet-spoke-prod-weu | Connected (Fully Synchronized) | vnet-spoke-prod-weu | Enabled |
| peer-vnet-hub-weu-to-vnet-spoke-dev-weu | Connected (Fully Synchronized) | vnet-spoke-dev-weu | Enabled |

### Hub VNet Connected Devices

| Device | Type | IP Address | Subnet |
|--------|------|-----------|--------|
| afw-hub-weu | Firewall | 10.0.1.4 | AzureFirewallSubnet |
| nic-vm-jump-hub-001 | Network interface | 10.0.3.4 | snet-management |
| bas-hub-weu | Bastion | - | AzureBastionSubnet |
