// ============================================================================
// MODULE: Hub Virtual Network
// ============================================================================
//
// WHAT THIS IS:
//   The hub VNet is the central network in a hub-spoke topology. ALL traffic
//   between spokes flows through the hub. Think of it as the airport hub
//   you don't fly direct from Amsterdam to a small town, you connect through
//   Schiphol. Same concept: spoke-prod doesn't talk directly to spoke-dev.
//   Traffic goes spoke → hub (firewall inspects it) → other spoke.
//
// WHY HUB-SPOKE:
//   - Centralized security: one firewall inspects all traffic
//   - Centralized management: one Bastion host, one jumpbox, one set of shared services
//   - Cost efficient: you don't need a firewall per spoke
//   - Isolation: spokes can't see each other unless the hub explicitly routes traffic
//
// SUBNETS IN THE HUB (and why each exists):
//
//   1. AzureFirewallSubnet (10.0.1.0/26)
//      - REQUIRED name. Azure Firewall will refuse to deploy if the subnet
//        isn't named exactly "AzureFirewallSubnet".
//      - Minimum /26 (64 IPs). Azure Firewall needs multiple private IPs for
//        its internal load balancer. /26 gives 59 usable IPs (Azure reserves 5).
//      - No NSG allowed. Azure manages security for this subnet internally.
//      - No other resources can be placed in this subnet.
//
//   2. AzureBastionSubnet (10.0.2.0/26)
//      - REQUIRED name. Same as firewall — Azure Bastion checks for this exact name.
//      - Minimum /26. Bastion needs IPs for its managed instances.
//      - No user-assigned NSG.
//      - Bastion provides RDP/SSH access to VMs through the Azure portal,
//        without exposing a public IP on the VM. This is how we access client VMs.
//
//   3. ManagementSubnet (10.0.3.0/24)
//      - For the jumpbox VM and any future management tooling.
//      - /24 gives 251 usable IPs — way more than we need now, but subnets
//        can't be resized easily, so we plan for growth.
//      - HAS an NSG: only allow inbound from Bastion + Azure internal traffic.
//
//   4. GatewaySubnet (10.0.4.0/27)
//      - REQUIRED name for VPN Gateway or ExpressRoute Gateway.
//      - /27 is the minimum. We're not deploying a gateway now, but reserving
//        the subnet means we don't need to restructure the VNet later.
//      - In production, this would connect to the on-premises network
//        via ExpressRoute (dedicated private connection) or VPN.
//
// IP ADDRESSING DESIGN:
//   Hub:  10.0.0.0/16  (65,536 addresses — the hub gets the first /16)
//   Prod: 10.1.0.0/16  (second /16)
//   Dev:  10.2.0.0/16  (third /16)
//
//   Why /16 each? It's generous, but IP space is free in a private network.
//   Being stingy with addressing causes painful re-addressing later when you
//   need more subnets.
//
// ============================================================================

// -- Parameters --------------------------------------------------------------

@description('Name of the hub VNet') // "What should I name this VNet? Something like 'hub-vnet' or 'core-network'."
param hubVnetName string

@description('Azure region. West Europe (Amsterdam)') // "Where should I create this VNet? Defaults to the resource group's region."
param location string = resourceGroup().location

@description('Address space for the hub VNet. Default: 10.0.0.0/16') // "What IP range should I use for the hub VNet? Default is
param hubAddressPrefix string = '10.0.0.0/16'

@description('Resource ID of the NSG to attach to the ManagementSubnet. Other hub subnets cannot have NSGs.') // "The ManagementSubnet is the only subnet in the hub where we place our own compute resources (like the jumpbox VM), so it needs an NSG for security. Please provide the resource ID of the NSG we should attach to this subnet."
param managementSubnetNsgId string

@description('Tags for cost allocation and governance.')
param tags object

// -- Subnet Definitions ------------------------------------------------------
//
// We define subnets inline rather than as separate resources because:
// 1. Azure VNet deploys subnets with no timing issues
// 2. Separate subnet resources can cause race conditions during deployment
// 3. It's the recommended pattern from Microsoft for new deployments

// -- Resource ----------------------------------------------------------------

resource hubVnet 'Microsoft.Network/virtualNetworks@2024-05-01' = { // "Create the hub VNet with the specified name, location, address space, and tags. The subnets are defined inline within the VNet resource."
  name: hubVnetName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        hubAddressPrefix
      ]
    }
    subnets: [
      {
        // AZURE FIREWALL SUBNET
        // Azure requires this exact name. Not "FirewallSubnet", not "fw-subnet".
        // If you rename it, deployment fails with a cryptic error.
        name: 'AzureFirewallSubnet'
        properties: {
          addressPrefix: '10.0.1.0/26'
          // No NSG — Azure will reject the deployment if you attach one.
          // No route table — Azure Firewall manages its own routing.
        }
      }
      {
        // AZURE BASTION SUBNET
        // Same deal — exact name required. Bastion is a PaaS service that
        // Microsoft manages, so they control the network security.
        name: 'AzureBastionSubnet'
        properties: {
          addressPrefix: '10.0.2.0/26'
          // No NSG — Azure manages Bastion's network security.
        }
      }
      {
        // MANAGEMENT SUBNET
        // This is where our jumpbox VM lives. It's the only subnet in the hub
        // where we place our own compute resources.
        name: 'snet-management'
        properties: {
          addressPrefix: '10.0.3.0/24'
          networkSecurityGroup: {
            id: managementSubnetNsgId
          }
        }
      }
      {
        // GATEWAY SUBNET
        // Reserved for future VPN or ExpressRoute gateway. We create it now
        // so the IP space is reserved. Deploying a gateway later into an
        // existing GatewaySubnet is non-disruptive.
        name: 'GatewaySubnet'
        properties: {
          addressPrefix: '10.0.4.0/27'
          // No NSG recommended — gateway traffic can break with NSG rules.
        }
      }
    ]
  }
}

// -- Outputs -----------------------------------------------------------------
//
// Outputs let other modules reference this VNet and its subnets.
// The main.bicep orchestrator will pass these outputs as parameters
// to the peering module, firewall module, bastion module, etc.

@description('Resource ID of the hub VNet. Used for peering and firewall deployment.') // "Here's the resource ID of the hub VNet we created, which other resources can use to reference this VNet for peering, firewall deployment, etc."
output hubVnetId string = hubVnet.id

@description('Name of the hub VNet. Used for peering references.') // "Here's the name of the hub VNet we created, which might be needed for display or peering references."
output hubVnetName string = hubVnet.name

@description('Resource ID of the AzureFirewallSubnet. Needed by the firewall module.') // "Here's the resource ID of the AzureFirewallSubnet, which the firewall module needs to know so it can deploy the firewall into this subnet."
output firewallSubnetId string = hubVnet.properties.subnets[0].id

@description('Resource ID of the AzureBastionSubnet. Needed by the bastion module.') // "Here's the resource ID of the AzureBastionSubnet, which the bastion module needs to know so it can deploy Bastion into this subnet."
output bastionSubnetId string = hubVnet.properties.subnets[1].id

@description('Resource ID of the ManagementSubnet. Needed by the jumpbox VM module.') // "Here's the resource ID of the ManagementSubnet, which the jumpbox VM module needs to know so it can deploy the jumpbox VM into this subnet."
output managementSubnetId string = hubVnet.properties.subnets[2].id

@description('Resource ID of the GatewaySubnet. Reserved for future gateway deployment.') // "Here's the resource ID of the GatewaySubnet, which we reserve for future VPN or ExpressRoute gateway deployment."
output gatewaySubnetId string = hubVnet.properties.subnets[3].id
