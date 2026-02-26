// ============================================================================
// MODULE: Spoke Virtual Network (Reusable)
// ============================================================================
//
// WHAT THIS IS:
//   A spoke VNet hosts the actual workloads (web servers, app servers, databases).
//   It's connected to the hub via VNet peering and relies on the hub for:
//   - Internet egress (through Azure Firewall)
//   - Cross-spoke communication (through Azure Firewall)
//   - Management access (through Bastion in the hub)
//   - Shared services (Log Analytics, Key Vault, etc.)
//
// WHY IT'S REUSABLE:
//   We have two spokes: Production (10.1.0.0/16) and Development (10.2.0.0/16).
//   They have the same structure — WebSubnet, AppSubnet, DataSubnet — just with
//   different IP ranges and potentially different NSG rules. Instead of writing
//   two modules, we write one and parameterize the differences.
//
//   In a real InSpark engagement, you might add more spokes later (staging, test,
//   DMZ). This module handles that without any code changes — just new parameters.
//
// SUBNET TIERS (3-tier architecture):
//
//   WebSubnet  → Faces the internet (via Firewall). Hosts web frontends.
//                NSG allows: HTTP/HTTPS from Firewall. Denies everything else.
//
//   AppSubnet  → Middle tier. Hosts application logic, APIs.
//                NSG allows: traffic from WebSubnet only. No direct internet.
//
//   DataSubnet → Backend tier. Hosts databases or connects to PaaS via Private Endpoints.
//                NSG allows: traffic from AppSubnet only. Most restricted.
//                Private Endpoints go here so database traffic never leaves the VNet.
//
//   This is the classic N-tier security model. Each tier can only talk to its
//   adjacent tier. Web can't bypass App to reach Data directly.
//
// ============================================================================

// -- Parameters --------------------------------------------------------------

@description('Name of the spoke VNet') // "What should I name this VNet? Something like 'spoke-prod-vnet' or 'spoke-dev-vnet'."
param spokeVnetName string

@description('Azure region. Must match the hub VNet region for peering.') // "Where should I create this VNet? It must be in the same region as the hub VNet for peering to work."
param location string = resourceGroup().location

@description('Address space for this spoke.') // "What IP range should I use for this spoke VNet? For production,
param spokeAddressPrefix string

@description('Address prefix for the web tier subnet') // "What IP range should I use for the web subnet? For example, if the spoke is
param webSubnetPrefix string

@description('Address prefix for the app tier subnet') // "What IP range should I use for the app subnet? For example, if the spoke is
param appSubnetPrefix string

@description('Address prefix for the data tier subnet') // "What IP range should I use for the data subnet? For example, if the spoke is
param dataSubnetPrefix string

@description('Resource ID of the NSG for the web subnet.') // "What's the resource ID of the NSG we want to attach to the web subnet? This NSG will control traffic to/from the web tier."
param webSubnetNsgId string

@description('Resource ID of the NSG for the app subnet.') // "What's the resource ID of the NSG we want to attach to the app subnet? This NSG will control traffic to/from the app tier."
param appSubnetNsgId string

@description('Resource ID of the NSG for the data subnet.') // "What's the resource ID of the NSG we want to attach to the data subnet? This NSG will control traffic to/from the data tier."
param dataSubnetNsgId string

@description('Tags for cost allocation and governance.') // "What tags should I attach to this spoke VNet? E.g. { "Environment": "Prod", "CostCenter": "12345" }"
param tags object

// -- Resource ----------------------------------------------------------------

resource spokeVnet 'Microsoft.Network/virtualNetworks@2024-05-01' = { // "Create the spoke VNet with the specified name, location, address space, and tags. The subnets are defined inline within the VNet resource."
  name: spokeVnetName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        spokeAddressPrefix
      ]
    }
    subnets: [
      {
        // WEB TIER
        // This is the "front door" subnet. In production, Azure Firewall DNATs
        // external traffic to web servers here. The NSG is the second layer of
        // defense — even if firewall rules are misconfigured, the NSG blocks
        // unexpected traffic.
        name: 'snet-web'
        properties: {
          addressPrefix: webSubnetPrefix
          networkSecurityGroup: {
            id: webSubnetNsgId
          }
        }
      }
      {
        // APP TIER
        // Application servers, API backends, business logic. Only reachable
        // from the web tier. This tier typically runs things like .NET apps,
        // Java services, or containerized workloads.
        name: 'snet-app'
        properties: {
          addressPrefix: appSubnetPrefix
          networkSecurityGroup: {
            id: appSubnetNsgId
          }
        }
      }
      {
        // DATA TIER
        // Most restrictive subnet. Only the app tier can reach it.
        // Private Endpoints for Azure SQL, Storage, etc. go here so that
        // PaaS services are accessed over private IP, never over the internet.
        name: 'snet-data'
        properties: {
          addressPrefix: dataSubnetPrefix
          networkSecurityGroup: {
            id: dataSubnetNsgId
          }
        }
      }
    ]
  }
}

// -- Outputs -----------------------------------------------------------------

@description('Resource ID of the spoke VNet. Used for peering with the hub.') // "Here's the resource ID of the spoke VNet we created, which other resources can use to reference this VNet for peering with the hub and other configurations."
output spokeVnetId string = spokeVnet.id

@description('Name of the spoke VNet. Used for peering references.') // "Here's the name of the spoke VNet we created, which might be needed for display or peering references."
output spokeVnetName string = spokeVnet.name

@description('Resource ID of the web subnet.') // "Here's the resource ID of the web subnet, which other resources can use to reference this subnet for NSG rules, firewall configurations, etc."
output webSubnetId string = spokeVnet.properties.subnets[0].id

@description('Resource ID of the app subnet.') // "Here's the resource ID of the app subnet, which other resources can use to reference this subnet for NSG rules, firewall configurations, etc."
output appSubnetId string = spokeVnet.properties.subnets[1].id

@description('Resource ID of the data subnet.') // "Here's the resource ID of the data subnet, which other resources can use to reference this subnet for NSG rules, firewall configurations, Private Endpoint deployments, etc."
output dataSubnetId string = spokeVnet.properties.subnets[2].id
