// ============================================================================
// MODULE: Spoke-to-Hub VNet Peering (Reverse Direction)
// ============================================================================
//
// WHY THIS IS A SEPARATE MODULE:
//   Bicep error BCP165 prevents creating a child resource on a VNet that lives
//   in a different resource group (different scope). The main peering module
//   runs in the hub RG, so it can't create a peering on the spoke VNet.
//
//   The solution: deploy this module into the SPOKE's resource group, where
//   the spoke VNet lives. Then the spoke VNet is in the same scope, and we
//   can create a child peering resource on it.
//
// ============================================================================

@description('Name of the spoke VNet. Must exist in the current resource group.')
param spokeVnetName string

@description('Name of the hub VNet (used for peering name).')
param hubVnetName string

@description('Full resource ID of the hub VNet.')
param hubVnetId string

@description('Allow forwarded traffic (from NVA/Firewall). Default: true.')
param allowForwardedTraffic bool = true

@description('Spoke uses hub gateway for on-prem connectivity. Default: false.')
param useRemoteGateways bool = false

// -- Resources ---------------------------------------------------------------

// Reference the spoke VNet (exists in THIS resource group — same scope, no problem)
resource spokeVnet 'Microsoft.Network/virtualNetworks@2024-05-01' existing = {
  name: spokeVnetName
}

// PEERING: Spoke → Hub
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

@description('Resource ID of the spoke-to-hub peering.')
output spokeToHubPeeringId string = spokeToHubPeering.id
