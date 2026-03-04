// ============================================================================
// MODULE: VNet Peering (Bidirectional)
// ============================================================================
//
// WHAT THIS IS:
//   VNet peering connects two Virtual Networks so resources in each VNet can
//   communicate using private IP addresses. Without peering, two VNets are
//   completely isolated, even if they're in the same subscription and region.
//
// WHY BIDIRECTIONAL:
//   Peering is NOT automatic in both directions. If you create a peering from
//   Hub → Spoke, traffic can flow from Hub to Spoke. But Spoke → Hub traffic
//   will be BLOCKED until you also create a peering from Spoke → Hub.
//
//   This module creates BOTH directions in one deployment, because you always
//   want bidirectional connectivity.
//
// KEY PEERING SETTINGS:
//
//   allowForwardedTraffic:
//     When true, the VNet accepts traffic that was forwarded by a network
//     virtual appliance (NVA) — in our case, Azure Firewall. Without this,
//     the spoke would reject traffic that the firewall is routing to it.
//     Hub side: true (accepts traffic forwarded from spokes via firewall)
//     Spoke side: true (accepts traffic forwarded from hub via firewall)
//
//   allowGatewayTransit:
//     When true on the HUB side, it lets the hub share its VPN/ExpressRoute
//     gateway with the spokes. This means spokes can reach on-premises
//     networks through the hub's gateway without needing their own.
//     Only set on the HUB side of the peering.
//
//   useRemoteGateways:
//     The SPOKE side counterpart to allowGatewayTransit. When true, the spoke
//     uses the hub's gateway for on-premises connectivity.
//     Only set on the SPOKE side. Cannot be true if no gateway exists in hub.
//     We default to false since we haven't deployed a gateway yet.
//
//   allowVirtualNetworkAccess:
//     When true, resources in both VNets can communicate. This is basically
//     the "enable peering" flag. Almost always true.
//
// IMPORTANT GOTCHA:
//   This module deploys into the HUB's resource group because both peering
//   resources (hub→spoke and spoke→hub) are child resources of their
//   respective VNets. Since the spoke VNet lives in a different resource group,
//   we use the `existing` keyword to reference it across resource groups.
//
//   In main.bicep, this module is scoped to the hub resource group.
//
// ============================================================================

// -- Parameters --------------------------------------------------------------

@description('Name of the hub VNet. Must already exist in the current resource group.')
param hubVnetName string

@description('Name of the spoke VNet. Must already exist in its resource group.')
param spokeVnetName string

@description('Full resource ID of the hub VNet.')
param hubVnetId string

@description('Full resource ID of the spoke VNet.')
param spokeVnetId string

@description('Resource group name where the spoke VNet lives.')
param spokeResourceGroupName string

@description('Allow forwarded traffic (from NVA/Firewall). Default: true.')
param allowForwardedTraffic bool = true

@description('Allow hub to share its gateway with spokes. Default: true.')
param allowGatewayTransit bool = true

@description('Spoke uses hub gateway for on-prem connectivity. Default: false (no gateway deployed yet).')
param useRemoteGateways bool = false

// -- Resources ---------------------------------------------------------------

// Reference the hub VNet (already exists in the current resource group)
resource hubVnet 'Microsoft.Network/virtualNetworks@2024-05-01' existing = {
  name: hubVnetName
}

// Reference the spoke VNet (exists in a different resource group)
resource spokeVnet 'Microsoft.Network/virtualNetworks@2024-05-01' existing = {
  name: spokeVnetName
  scope: resourceGroup(spokeResourceGroupName)
}

// PEERING 1: Hub → Spoke
// This is a child resource of the hub VNet. The naming convention
// "peer-hub-to-spoke-prod" makes it immediately clear what direction this is.
resource hubToSpokePeering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-05-01' = {
  name: 'peer-${hubVnetName}-to-${spokeVnetName}'
  parent: hubVnet
  properties: {
    remoteVirtualNetwork: {
      id: spokeVnetId
    }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: allowForwardedTraffic
    // Hub side: allow gateway transit so spokes can use the hub's gateway
    allowGatewayTransit: allowGatewayTransit
    // Hub side: never "useRemoteGateways" — the hub IS the gateway hub
    useRemoteGateways: false
  }
}

// PEERING 2: Spoke → Hub
// This is a child resource of the spoke VNet. We need to use a module-level
// scope trick since the spoke VNet is in a different resource group.
// However, since we're deploying this module into the hub's resource group,
// we reference the spoke VNet as an existing resource in its own RG.
resource spokeToHubPeering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-05-01' = {
  name: 'peer-${spokeVnetName}-to-${hubVnetName}'
  parent: spokeVnet
  properties: {
    remoteVirtualNetwork: {
      id: hubVnetId
    }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: allowForwardedTraffic
    // Spoke side: never offer gateway transit — only the hub has the gateway
    allowGatewayTransit: false
    // Spoke side: use hub's gateway if available
    useRemoteGateways: useRemoteGateways
  }
}

// -- Outputs -----------------------------------------------------------------

@description('Resource ID of the hub-to-spoke peering.')
output hubToSpokePeeringId string = hubToSpokePeering.id

@description('Resource ID of the spoke-to-hub peering.')
output spokeToHubPeeringId string = spokeToHubPeering.id

@description('Peering state. Should be "Connected" after successful deployment.')
output peeringState string = hubToSpokePeering.properties.peeringState
