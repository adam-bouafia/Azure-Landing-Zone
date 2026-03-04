// ============================================================================
// ORCHESTRATOR: main.bicep
// ============================================================================
//
// WHAT THIS FILE DOES:
//   This is the entry point for the entire landing zone deployment. It doesn't
//   create resources directly — it calls modules and wires them together.
//   Think of it as the conductor of an orchestra: it doesn't play instruments,
//   it tells each section when and how to play.
//
// TARGET SCOPE: SUBSCRIPTION
//   Most Bicep files default to 'resourceGroup' scope, meaning they deploy
//   into an existing resource group. But we set targetScope = 'subscription'
//   because we need to:
//   1. CREATE resource groups (you can't create an RG from inside an RG)
//   2. Deploy modules into DIFFERENT resource groups (hub, spoke-prod, spoke-dev)
//
//   When deploying, you use:
//     az deployment sub create --location westeurope --template-file infra/main.bicep
//   Note: "sub create" not "group create" — because we're targeting the subscription.
//
// DEPLOYMENT ORDER (Bicep resolves this via parameter dependencies):
//   1. Resource Groups
//   2. Log Analytics + Storage (shared services — needed by everything else)
//   3. NSGs (needed before VNets)
//   4. Hub VNet + Spoke VNets (reference NSGs)
//   5. VNet Peering (references both VNets)
//   6. Firewall + Bastion (reference hub subnets)
//   7. Key Vault (shared services)
//   8. Jumpbox VM (references subnet + Key Vault password)
//   9. Alerts (references VM)
//   10. Recovery Vault (shared services)
//
// ============================================================================

targetScope = 'subscription'

// -- Parameters --------------------------------------------------------------

@description('Environment name. Used in resource naming and tags.') // "Which environment are we deploying? This will be used in resource names and tags to differentiate between production and development environments."
@allowed([
  'dev'
  'prod'
])
param environment string

@description('Azure region for all resources. West Europe = Amsterdam datacenter.') // "Where should I deploy the resources? Default is 'westeurope' (Amsterdam datacenter). You can change this to another region if needed, but make sure to choose a region that supports all the services used in this landing zone."
param location string = 'westeurope'

@description('Tags applied to every resource. Defined in parameter files.') //  "What tags should I apply to all resources for cost allocation and governance? Provide a key-value object, for example { 'Environment': 'Production', 'Project': 'ALZ' }."
param tags object = {
  Environment: environment == 'prod' ? 'Production' : 'Development'
  ManagedBy: 'alzadmin'
  Project: 'ALZ'
  CostCenter: 'IT-Infra-001'
}

// -- Phase 2 Parameters ------------------------------------------------------

@description('Deploy Azure Firewall? Costs ~€912/month. Default false for cost savings.') // "Do you want to deploy Azure Firewall? Set this to false to save approximately €912/month during development and testing. You can deploy the firewall later when you need it."
param deployFirewall bool = false

@description('Deploy Azure Bastion? Costs ~€140/month. Default false for cost savings.') // "Do you want to deploy Azure Bastion? Set this to false to save approximately €140/month during development and testing. You can deploy the Bastion host later when you need it."
param deployBastion bool = false

@description('Admin username for the jumpbox VM.') // "What admin username should I set for the jumpbox VM? This username will be used to log in to the jumpbox VM. It cannot be 'admin', 'administrator', or 'root' due to Azure's security policies. A common convention is to use something like 'azureadmin' or 'jumpadmin'."
param jumpboxAdminUsername string = 'azureadmin'

@description('Admin password for the jumpbox VM. Must meet Azure complexity requirements.') // "Please provide a secure admin password for the jumpbox VM. The password must be between 12 and 123 characters and include uppercase letters, lowercase letters, numbers, and special characters. This password will be stored securely in Azure Key Vault and will not be hardcoded in any parameter files or code for security reasons."
@secure()
param jumpboxAdminPassword string

// -- Phase 3 Parameters ------------------------------------------------------

@description('Email address for infrastructure alert notifications.') // "What email address should I use for infrastructure alert notifications? This email will receive alerts triggered by the monitoring system, such as high CPU usage or low memory on the jumpbox VM. Make sure to provide an email that is monitored regularly by the operations team, for example 'ops@alz.nl'."
param alertEmailAddress string = 'ops@alz.nl'

@description('Object ID of the service principal for Key Vault RBAC. Leave empty to skip role assignment.') // "If you want to assign the Secrets Officer role to a service principal for managing Key Vault secrets, please provide the Object ID of that service principal. This allows the service principal to write secrets to Key Vault. If you don't have a service principal or don't want to assign this role, you can leave this parameter empty."
param deployerObjectId string = ''

// ============================================================================
// STEP 1: RESOURCE GROUPS
// ============================================================================
//
// Resource groups are logical containers. They don't cost anything — they're
// just organizational boundaries. We create separate RGs for:
// - Hub networking (shared infrastructure)
// - Each spoke (workload isolation)
// - Shared services (monitoring, backup, key vault)
//
// Why separate RGs? RBAC. You can give a developer Contributor access to
// rg-spoke-dev-weu without them being able to touch production or the hub.

resource rgHub 'Microsoft.Resources/resourceGroups@2024-03-01' = { // "Create a resource group named 'rg-hub-weu' in the specified location with the provided tags. This resource group will serve as the container for all hub networking resources, such as the hub VNet, Azure Firewall, and Azure Bastion. The naming convention 'rg-hub-weu' indicates that this is the hub resource group for the West Europe region."
  name: 'rg-hub-weu'
  location: location
  tags: tags
}

resource rgSpokeProd 'Microsoft.Resources/resourceGroups@2024-03-01' = { // "Create a resource group named 'rg-spoke-prod-weu' in the specified location with the provided tags. This resource group will serve as the container for all production workload resources, such as the spoke VNet, application servers, and databases. The naming convention 'rg-spoke-prod-weu' indicates that this is the production spoke resource group for the West Europe region."
  name: 'rg-spoke-prod-weu'
  location: location
  tags: tags
}

resource rgSpokeDev 'Microsoft.Resources/resourceGroups@2024-03-01' = { // "Create a resource group named 'rg-spoke-dev-weu' in the specified location with the provided tags. This resource group will serve as the container for all development workload resources, such as the spoke VNet and any development servers. The naming convention 'rg-spoke-dev-weu' indicates that this is the development spoke resource group for the West Europe region."
  name: 'rg-spoke-dev-weu'
  location: location
  tags: tags
}

resource rgShared 'Microsoft.Resources/resourceGroups@2024-03-01' = { //  "Create a resource group named 'rg-shared-weu' in the specified location with the provided tags. This resource group will serve as the container for all shared services resources, such as Log Analytics, Azure Key Vault, and Recovery Services Vault. The naming convention 'rg-shared-weu' indicates that this is the shared services resource group for the West Europe region."
  name: 'rg-shared-weu'
  location: location
  tags: tags
}

// ============================================================================
// STEP 2: SHARED SERVICES (Log Analytics + Storage)
// ============================================================================
//
// These deploy first because almost everything else sends logs here.
// Log Analytics is the central nervous system of the landing zone.

module logAnalytics 'modules/monitoring/log-analytics.bicep' = { // "Create a Log Analytics workspace named 'log-ALZ-{environment}' in the shared resource group with the specified location, retention period, and tags. The workspace will be used to collect and analyze logs from various resources in the landing zone. The retention period is set to 90 days for production environments and 30 days for development environments to balance cost and data availability."
  scope: rgShared
  name: 'deploy-log-analytics'
  params: {
    workspaceName: 'log-ALZ-${environment}'
    location: location
    retentionInDays: environment == 'prod' ? 90 : 30  // Save cost in dev
    tags: tags
  }
}

module diagnosticsStorage 'modules/storage/diagnostics-storage.bicep' = { // "Create a Storage Account named 'stdiagALZ{environment}001' in the shared resource group with the specified location, tags, and diagnostic settings. This storage account will be used to store diagnostic logs and metrics from various resources in the landing zone. The name must be globally unique and follow Azure's naming rules for storage accounts. The diagnostic settings will be configured to send data to the Log Analytics workspace created earlier."
  scope: rgShared
  name: 'deploy-diagnostics-storage'
  params: {
    // Storage account names: no dashes, lowercase only, globally unique.
    // We append environment to avoid collisions between dev and prod.
    storageAccountName: 'stdiagALZ${environment}001'
    location: location
    tags: tags
  }
}

// ============================================================================
// STEP 3: NETWORK SECURITY GROUPS
// ============================================================================
//
// NSGs must be deployed BEFORE VNets because VNet subnet definitions reference
// NSG resource IDs. If the NSG doesn't exist when the VNet tries to link to
// it, deployment fails.
//
// We create one NSG per subnet that needs one:
// - Hub: ManagementSubnet only (Firewall/Bastion/Gateway subnets can't have NSGs)
// - Each spoke: WebSubnet, AppSubnet, DataSubnet (3 per spoke)

// --- Hub NSG: Management Subnet ---
module nsgHubManagement 'modules/networking/nsg.bicep' = { // "Create a Network Security Group named 'nsg-management-hub' in the hub resource group with the specified location, tags, and security rules. This NSG will be attached to the ManagementSubnet in the hub VNet and will allow RDP and SSH traffic from the Azure Bastion subnet while denying all other inbound traffic for enhanced security."
  scope: rgHub
  name: 'deploy-nsg-management-hub'
  params: {
    nsgName: 'nsg-management-hub'
    location: location
    tags: tags
    securityRules: [
      {
        // Allow RDP from Azure Bastion service
        // Bastion connects to VMs over the Azure backbone using these ports.
        // Source: Bastion subnet. Destination: this subnet. Protocol: TCP.
        name: 'AllowBastionRDP'
        priority: 100
        direction: 'Inbound'
        access: 'Allow'
        protocol: 'Tcp'
        sourceAddressPrefix: '10.0.2.0/26'  // AzureBastionSubnet
        sourcePortRange: '*'
        destinationAddressPrefix: '10.0.3.0/24'  // ManagementSubnet
        destinationPortRange: '3389'  // RDP
      }
      {
        // Allow SSH from Bastion (for Linux VMs if we add any later)
        name: 'AllowBastionSSH'
        priority: 110
        direction: 'Inbound'
        access: 'Allow'
        protocol: 'Tcp'
        sourceAddressPrefix: '10.0.2.0/26'
        sourcePortRange: '*'
        destinationAddressPrefix: '10.0.3.0/24'
        destinationPortRange: '22'  // SSH
      }
      {
        // Deny all other inbound traffic.
        // This is technically redundant (Azure's default rule does this at 65500),
        // but we make it explicit at 4096 so it shows in the NSG rules list.
        // Makes auditing clearer: "we intentionally deny everything else."
        name: 'DenyAllInbound'
        priority: 4096
        direction: 'Inbound'
        access: 'Deny'
        protocol: '*'
        sourceAddressPrefix: '*'
        sourcePortRange: '*'
        destinationAddressPrefix: '*'
        destinationPortRange: '*'
      }
    ]
  }
}

// --- Spoke NSGs: Production ---
module nsgProdWeb 'modules/networking/nsg.bicep' = { // "Create a Network Security Group named 'nsg-web-prod' in the production spoke resource group with the specified location, tags, and security rules. This NSG will be attached to the WebSubnet in the production spoke VNet and will allow HTTP and HTTPS traffic from the Azure Firewall subnet while denying all other inbound traffic to enforce a secure perimeter for the web tier."
  scope: rgSpokeProd
  name: 'deploy-nsg-web-prod'
  params: {
    nsgName: 'nsg-web-prod'
    location: location
    tags: tags
    securityRules: [
      {
        // Allow HTTP from Azure Firewall subnet.
        // In the real flow: Internet → Firewall (DNAT) → WebSubnet.
        // The firewall translates the public IP to a private IP and forwards.
        name: 'AllowHTTPFromFirewall'
        priority: 100
        direction: 'Inbound'
        access: 'Allow'
        protocol: 'Tcp'
        sourceAddressPrefix: '10.0.1.0/26'  // AzureFirewallSubnet
        sourcePortRange: '*'
        destinationAddressPrefix: '10.1.1.0/24'  // WebSubnet prod
        destinationPortRange: '80'
      }
      {
        name: 'AllowHTTPSFromFirewall'
        priority: 110
        direction: 'Inbound'
        access: 'Allow'
        protocol: 'Tcp'
        sourceAddressPrefix: '10.0.1.0/26'
        sourcePortRange: '*'
        destinationAddressPrefix: '10.1.1.0/24'
        destinationPortRange: '443'
      }
      {
        name: 'DenyAllInbound'
        priority: 4096
        direction: 'Inbound'
        access: 'Deny'
        protocol: '*'
        sourceAddressPrefix: '*'
        sourcePortRange: '*'
        destinationAddressPrefix: '*'
        destinationPortRange: '*'
      }
    ]
  }
}

module nsgProdApp 'modules/networking/nsg.bicep' = { // "Create a Network Security Group named 'nsg-app-prod' in the production spoke resource group with the specified location, tags, and security rules. This NSG will be attached to the AppSubnet in the production spoke VNet and will allow HTTPS traffic from the WebSubnet while denying all other inbound traffic to enforce the N-tier architecture."
  scope: rgSpokeProd
  name: 'deploy-nsg-app-prod'
  params: {
    nsgName: 'nsg-app-prod'
    location: location
    tags: tags
    securityRules: [
      {
        // App tier only accepts traffic from Web tier.
        // This enforces the N-tier model: Web → App → Data
        name: 'AllowFromWebSubnet'
        priority: 100
        direction: 'Inbound'
        access: 'Allow'
        protocol: 'Tcp'
        sourceAddressPrefix: '10.1.1.0/24'  // WebSubnet prod
        sourcePortRange: '*'
        destinationAddressPrefix: '10.1.2.0/24'  // AppSubnet prod
        destinationPortRange: '443'
      }
      {
        name: 'DenyAllInbound'
        priority: 4096
        direction: 'Inbound'
        access: 'Deny'
        protocol: '*'
        sourceAddressPrefix: '*'
        sourcePortRange: '*'
        destinationAddressPrefix: '*'
        destinationPortRange: '*'
      }
    ]
  }
}

module nsgProdData 'modules/networking/nsg.bicep' = { // "Create a Network Security Group named 'nsg-data-prod' in the production spoke resource group with the specified location, tags, and security rules. This NSG will be attached to the DataSubnet in the production spoke VNet and will allow SQL Server traffic from the AppSubnet while denying all other inbound traffic to protect the data tier."
  scope: rgSpokeProd
  name: 'deploy-nsg-data-prod'
  params: {
    nsgName: 'nsg-data-prod'
    location: location
    tags: tags
    securityRules: [
      {
        // Data tier only accepts traffic from App tier.
        // Most locked-down subnet. Databases live here.
        name: 'AllowFromAppSubnet'
        priority: 100
        direction: 'Inbound'
        access: 'Allow'
        protocol: 'Tcp'
        sourceAddressPrefix: '10.1.2.0/24'  // AppSubnet prod
        sourcePortRange: '*'
        destinationAddressPrefix: '10.1.3.0/24'  // DataSubnet prod
        destinationPortRange: '1433'  // SQL Server default port
      }
      {
        name: 'DenyAllInbound'
        priority: 4096
        direction: 'Inbound'
        access: 'Deny'
        protocol: '*'
        sourceAddressPrefix: '*'
        sourcePortRange: '*'
        destinationAddressPrefix: '*'
        destinationPortRange: '*'
      }
    ]
  }
}

// --- Spoke NSGs: Development ---
// Same structure as prod, different IP ranges (10.2.x.x instead of 10.1.x.x)
module nsgDevWeb 'modules/networking/nsg.bicep' = { // "Create a Network Security Group named 'nsg-web-dev' in the development spoke resource group with the specified location, tags, and security rules. This NSG will be attached to the WebSubnet in the development spoke VNet and will allow HTTP and HTTPS traffic from the Azure Firewall subnet while denying all other inbound traffic to enforce a secure perimeter for the web tier."
  scope: rgSpokeDev
  name: 'deploy-nsg-web-dev'
  params: {
    nsgName: 'nsg-web-dev'
    location: location
    tags: tags
    securityRules: [
      {
        name: 'AllowHTTPFromFirewall'
        priority: 100
        direction: 'Inbound'
        access: 'Allow'
        protocol: 'Tcp'
        sourceAddressPrefix: '10.0.1.0/26'
        sourcePortRange: '*'
        destinationAddressPrefix: '10.2.1.0/24'
        destinationPortRange: '80'
      }
      {
        name: 'AllowHTTPSFromFirewall'
        priority: 110
        direction: 'Inbound'
        access: 'Allow'
        protocol: 'Tcp'
        sourceAddressPrefix: '10.0.1.0/26'
        sourcePortRange: '*'
        destinationAddressPrefix: '10.2.1.0/24'
        destinationPortRange: '443'
      }
      {
        name: 'DenyAllInbound'
        priority: 4096
        direction: 'Inbound'
        access: 'Deny'
        protocol: '*'
        sourceAddressPrefix: '*'
        sourcePortRange: '*'
        destinationAddressPrefix: '*'
        destinationPortRange: '*'
      }
    ]
  }
}

module nsgDevApp 'modules/networking/nsg.bicep' = { // "Create a Network Security Group named 'nsg-app-dev' in the development spoke resource group with the specified location, tags, and security rules. This NSG will be attached to the AppSubnet in the development spoke VNet and will allow HTTPS traffic from the WebSubnet while denying all other inbound traffic to enforce the N-tier architecture."
  scope: rgSpokeDev
  name: 'deploy-nsg-app-dev'
  params: {
    nsgName: 'nsg-app-dev'
    location: location
    tags: tags
    securityRules: [
      {
        name: 'AllowFromWebSubnet'
        priority: 100
        direction: 'Inbound'
        access: 'Allow'
        protocol: 'Tcp'
        sourceAddressPrefix: '10.2.1.0/24'
        sourcePortRange: '*'
        destinationAddressPrefix: '10.2.2.0/24'
        destinationPortRange: '443'
      }
      {
        name: 'DenyAllInbound'
        priority: 4096
        direction: 'Inbound'
        access: 'Deny'
        protocol: '*'
        sourceAddressPrefix: '*'
        sourcePortRange: '*'
        destinationAddressPrefix: '*'
        destinationPortRange: '*'
      }
    ]
  }
}

module nsgDevData 'modules/networking/nsg.bicep' = { // "Create a Network Security Group named 'nsg-data-dev' in the development spoke resource group with the specified location, tags, and security rules. This NSG will be attached to the DataSubnet in the development spoke VNet and will allow SQL Server traffic from the AppSubnet while denying all other inbound traffic to protect the data tier."
  scope: rgSpokeDev
  name: 'deploy-nsg-data-dev'
  params: {
    nsgName: 'nsg-data-dev'
    location: location
    tags: tags
    securityRules: [
      {
        name: 'AllowFromAppSubnet'
        priority: 100
        direction: 'Inbound'
        access: 'Allow'
        protocol: 'Tcp'
        sourceAddressPrefix: '10.2.2.0/24'
        sourcePortRange: '*'
        destinationAddressPrefix: '10.2.3.0/24'
        destinationPortRange: '1433'
      }
      {
        name: 'DenyAllInbound'
        priority: 4096
        direction: 'Inbound'
        access: 'Deny'
        protocol: '*'
        sourceAddressPrefix: '*'
        sourcePortRange: '*'
        destinationAddressPrefix: '*'
        destinationPortRange: '*'
      }
    ]
  }
}

// ============================================================================
// STEP 4: VIRTUAL NETWORKS
// ============================================================================

module hubNetwork 'modules/networking/hub-vnet.bicep' = { // "Create a hub virtual network named 'vnet-hub-weu' in the hub resource group with the specified location, address space, NSG associations, and tags. The hub VNet will contain subnets for Azure Firewall, Azure Bastion, and management resources. The ManagementSubnet will be associated with the NSG created earlier to secure access to management resources."
  scope: rgHub
  name: 'deploy-hub-vnet'
  params: {
    hubVnetName: 'vnet-hub-weu'
    location: location
    hubAddressPrefix: '10.0.0.0/16'
    managementSubnetNsgId: nsgHubManagement.outputs.nsgId
    tags: tags
  }
}

module spokeProd 'modules/networking/spoke-vnet.bicep' = { // "Create a spoke virtual network named 'vnet-spoke-prod-weu' in the production spoke resource group with the specified location, address space, NSG associations, and tags. The spoke VNet will contain subnets for web, application, and data tiers. Each subnet will be associated with its respective NSG created earlier to enforce security boundaries between tiers."
  scope: rgSpokeProd
  name: 'deploy-spoke-prod'
  params: {
    spokeVnetName: 'vnet-spoke-prod-weu'
    location: location
    spokeAddressPrefix: '10.1.0.0/16'
    webSubnetPrefix: '10.1.1.0/24'
    appSubnetPrefix: '10.1.2.0/24'
    dataSubnetPrefix: '10.1.3.0/24'
    webSubnetNsgId: nsgProdWeb.outputs.nsgId
    appSubnetNsgId: nsgProdApp.outputs.nsgId
    dataSubnetNsgId: nsgProdData.outputs.nsgId
    tags: tags
  }
}

module spokeDev 'modules/networking/spoke-vnet.bicep' = { // "Create a spoke virtual network named 'vnet-spoke-dev-weu' in the development spoke resource group with the specified location, address space, NSG associations, and tags. The spoke VNet will contain subnets for web, application, and data tiers. Each subnet will be associated with its respective NSG created earlier to enforce security boundaries between tiers."
  scope: rgSpokeDev
  name: 'deploy-spoke-dev'
  params: {
    spokeVnetName: 'vnet-spoke-dev-weu'
    location: location
    spokeAddressPrefix: '10.2.0.0/16'
    webSubnetPrefix: '10.2.1.0/24'
    appSubnetPrefix: '10.2.2.0/24'
    dataSubnetPrefix: '10.2.3.0/24'
    webSubnetNsgId: nsgDevWeb.outputs.nsgId
    appSubnetNsgId: nsgDevApp.outputs.nsgId
    dataSubnetNsgId: nsgDevData.outputs.nsgId
    tags: tags
  }
}

// ============================================================================
// STEP 5: VNET PEERING
// ============================================================================
//
// Peering connects each spoke to the hub. Note that we scope both peering
// modules to the hub resource group. The peering module internally references
// the spoke VNet as an existing resource in its own RG.

module peeringProd 'modules/networking/peering.bicep' = { //  "Create virtual network peering between the hub VNet and the production spoke VNet. This module will create two peering connections: one from the hub to the spoke and one from the spoke to the hub. The peering will allow forwarded traffic and gateway transit, enabling communication between the hub and spoke VNets while maintaining isolation from the internet."
  scope: rgHub
  name: 'deploy-peering-prod'
  params: {
    hubVnetName: hubNetwork.outputs.hubVnetName
    spokeVnetName: spokeProd.outputs.spokeVnetName
    hubVnetId: hubNetwork.outputs.hubVnetId
    spokeVnetId: spokeProd.outputs.spokeVnetId
    spokeResourceGroupName: rgSpokeProd.name
    allowForwardedTraffic: true
    allowGatewayTransit: true
    useRemoteGateways: false
  }
}

module peeringDev 'modules/networking/peering.bicep' = { // "Create virtual network peering between the hub VNet and the development spoke VNet. This module will create two peering connections: one from the hub to the spoke and one from the spoke to the hub. The peering will allow forwarded traffic and gateway transit, enabling communication between the hub and spoke VNets while maintaining isolation from the internet."
  scope: rgHub
  name: 'deploy-peering-dev'
  params: {
    hubVnetName: hubNetwork.outputs.hubVnetName
    spokeVnetName: spokeDev.outputs.spokeVnetName
    hubVnetId: hubNetwork.outputs.hubVnetId
    spokeVnetId: spokeDev.outputs.spokeVnetId
    spokeResourceGroupName: rgSpokeDev.name
    allowForwardedTraffic: true
    allowGatewayTransit: true
    useRemoteGateways: false
  }
}

// ============================================================================
// STEP 6: AZURE FIREWALL + BASTION
// ============================================================================
//
// These go after VNets because they deploy INTO hub subnets.
// Both are conditionally deployed to manage costs.

module firewall 'modules/networking/firewall.bicep' = { // "Create an Azure Firewall named 'afw-hub-weu' in the hub resource group with the specified location, SKU, subnet association, and tags. The firewall will be deployed in the AzureFirewallSubnet of the hub VNet and will be used to control inbound and outbound traffic to and from the VNets. The deployment of the firewall is conditional based on the 'deployFirewall' parameter to allow for cost savings during development."
  scope: rgHub
  name: 'deploy-firewall'
  params: {
    firewallName: 'afw-hub-weu'
    firewallPolicyName: 'afwp-hub-weu'
    location: location
    firewallSubnetId: hubNetwork.outputs.firewallSubnetId
    deployFirewall: deployFirewall
    skuTier: 'Standard'
    tags: tags
  }
}

module bastion 'modules/networking/bastion.bicep' = { // "Create an Azure Bastion host named 'bas-hub-weu' in the hub resource group with the specified location, subnet association, and tags. The Bastion host will be deployed in the AzureBastionSubnet of the hub VNet and will provide secure RDP and SSH access to virtual machines in the hub and spoke VNets without exposing them to the public internet. The deployment of the Bastion host is conditional based on the 'deployBastion' parameter to allow for cost savings during development."
  scope: rgHub
  name: 'deploy-bastion'
  params: {
    bastionName: 'bas-hub-weu'
    location: location
    bastionSubnetId: hubNetwork.outputs.bastionSubnetId
    deployBastion: deployBastion
    tags: tags
  }
}

// ============================================================================
// STEP 7: KEY VAULT
// ============================================================================
//
// Key Vault stores secrets (like the jumpbox admin password).
// Deployed into the shared resource group because it serves all environments.

module keyVault 'modules/security/keyvault.bicep' = { // "Create an Azure Key Vault named 'kv-ALZ-{environment}-001' in the shared resource group with the specified location, tags, and access policies. The Key Vault will be used to securely store secrets such as the jumpbox admin password. If a 'deployerObjectId' is provided, it will be granted the Secrets Officer role to allow management of secrets. The Key Vault will also be configured to send diagnostic logs to the Log Analytics workspace created earlier for monitoring and auditing purposes."
  scope: rgShared
  name: 'deploy-keyvault'
  params: {
    keyVaultName: 'kv-ALZ-${environment}-001'
    location: location
    tags: tags
    logAnalyticsWorkspaceId: logAnalytics.outputs.workspaceId
    secretsOfficerObjectId: deployerObjectId
  }
}

// ============================================================================
// STEP 8: JUMPBOX VM
// ============================================================================
//
// The management VM in the hub. Access via Bastion only.
// Password is passed as a @secure() parameter — never visible in logs.

module jumpbox 'modules/compute/vm-jumpbox.bicep' = { // "Create a jumpbox virtual machine named 'vm-jump-hub-001' in the hub resource group with the specified location, size, subnet association, admin credentials, and tags. The jumpbox will be deployed in the ManagementSubnet of the hub VNet and will be used as a secure management VM for accessing resources in the hub and spoke VNets. The admin password will be stored securely in Azure Key Vault and will not be exposed in any logs or parameter files for security reasons."
  scope: rgHub
  name: 'deploy-jumpbox'
  params: {
    vmName: 'vm-jump-hub-001'
    location: location
    subnetId: hubNetwork.outputs.managementSubnetId
    adminUsername: jumpboxAdminUsername
    adminPassword: jumpboxAdminPassword
    vmSize: environment == 'prod' ? 'Standard_B2s' : 'Standard_B2s'  // Same for now, but parameterized for future
    logAnalyticsWorkspaceId: logAnalytics.outputs.workspaceId
    tags: tags
  }
}

// ============================================================================
// STEP 9: MONITORING ALERTS
// ============================================================================
//
// Alerts fire when VM metrics cross thresholds. Action group sends email
// to the operations team.

module alerts 'modules/monitoring/alerts.bicep' = { // "Create monitoring alerts for the jumpbox VM in the shared resource group with the specified location, email address for notifications, and tags. The alerts will be configured to trigger when certain performance metrics (such as CPU usage or memory usage) exceed defined thresholds. When an alert is triggered, an email notification will be sent to the specified 'alertEmailAddress' to inform the operations team of potential issues with the jumpbox VM."
  scope: rgShared
  name: 'deploy-alerts'
  params: {
    location: location
    alertEmailAddress: alertEmailAddress
    vmResourceId: jumpbox.outputs.vmId
    tags: tags
  }
}

// ============================================================================
// STEP 10: BACKUP
// ============================================================================
//
// Recovery Services Vault with a daily backup policy.
// Note: VM backup *registration* (assigning the VM to the policy) is a
// separate operation typically done via Azure CLI or portal after deployment.
// Bicep can't easily register a VM for backup in a cross-RG scenario.
//
// After deployment, run:
//   az backup protection enable-for-vm \
//     --vault-name rsv-ALZ-{env} \
//     --resource-group rg-shared-weu \
//     --vm vm-jump-hub-001 \
//     --policy-name policy-daily-30d

module recoveryVault 'modules/backup/recovery-vault.bicep' = { // "Create a Recovery Services Vault named 'rsv-ALZ-{environment}' in the shared resource group with the specified location, tags, and backup policy. The Recovery Services Vault will be used to manage backups for virtual machines in the landing zone. A daily backup policy with a retention period of 30 days will be created and associated with the vault. Note that VM backup registration (assigning VMs to the backup policy) is a separate operation that can be performed after deployment using Azure CLI or the Azure portal."
  scope: rgShared
  name: 'deploy-recovery-vault'
  params: {
    vaultName: 'rsv-ALZ-${environment}'
    location: location
    tags: tags
  }
}

// ============================================================================
// OUTPUTS
// ============================================================================
//
// These outputs are shown after deployment completes. Useful for debugging
// and for chaining with other tools (scripts, pipelines).

// Networking
output hubVnetId string = hubNetwork.outputs.hubVnetId
output spokeProdVnetId string = spokeProd.outputs.spokeVnetId
output spokeDevVnetId string = spokeDev.outputs.spokeVnetId
output peeringProdState string = peeringProd.outputs.peeringState
output peeringDevState string = peeringDev.outputs.peeringState

// Firewall (conditional)
output firewallPrivateIp string = firewall.outputs.firewallPrivateIp

// Shared services
output logAnalyticsWorkspaceId string = logAnalytics.outputs.workspaceId
output keyVaultName string = keyVault.outputs.keyVaultName
output recoveryVaultName string = recoveryVault.outputs.vaultName

// Compute
output jumpboxVmId string = jumpbox.outputs.vmId
output jumpboxPrivateIp string = jumpbox.outputs.privateIpAddress
