// ============================================================================
// MODULE: Azure Firewall + Firewall Policy
// ============================================================================
//
// WHAT THIS IS:
//   Azure Firewall is a cloud-native, managed network security service. It sits
//   in the hub VNet and inspects ALL traffic flowing between spokes, to/from
//   the internet, and to/from on-premises. It's the central enforcement point
//   for network security in the landing zone.
//
// WHY AZURE FIREWALL (not a third-party NVA):
//   - Fully managed by Microsoft , no patching needed, no HA configuration, no sizing
//   - Native integration with Azure Monitor, Log Analytics, Azure Policy
//   - Built-in threat intelligence feed from Microsoft's security team
//   - Scales automatically with traffic (no manual scale-out)
//   - AZL standardizes on Azure-native services for managed clients
//
// HOW IT WORKS:
//   The firewall gets a public IP and a private IP (in AzureFirewallSubnet).
//   Route tables on spoke subnets force all traffic through the firewall's
//   private IP (0.0.0.0/0 → firewall private IP). The firewall then:
//   1. Checks DNAT rules (inbound from internet → translate to private IP)
//   2. Checks Network rules (L3/L4 — IP, port, protocol)
//   3. Checks Application rules (L7 — FQDN, URL filtering)
//   4. If no rule matches → deny (default behavior)
//
// FIREWALL POLICY:
//   Firewall Policy is a separate resource that holds all the rules. This
//   separation lets you reuse policies across firewalls or version them
//   independently. Rules are organized into:
//   - Rule Collection Groups (organizational container, has a priority)
//     - Rule Collections (a set of rules with same action type: Allow/Deny)
//       - Individual Rules (the actual match conditions)
//
// COST WARNING:
//   Azure Firewall Standard: ~€1.25/hour = ~€912/month (just for existing).
//   Plus data processing charges. This is why we have a deployFirewall toggle.
//   Deploy to verify your rules work, screenshot, tear down.
//
// ============================================================================

// -- Parameters --------------------------------------------------------------

@description('Name of the Azure Firewall. Convention: afw-{workload}-{region}') // "What should I name the firewall? Something like 'afw-prod-weu' or 'afw-dev-use'."
param firewallName string

@description('Name of the Firewall Policy. Convention: afwp-{workload}-{region}') // "What should I name the firewall policy? Something like 'afwp-prod-weu' or 'afwp-dev-use'."
param firewallPolicyName string

@description('Azure region.') // "Where should I create the firewall? Defaults to the resource group's region."
param location string = resourceGroup().location

@description('Resource ID of the AzureFirewallSubnet. Must be named exactly "AzureFirewallSubnet".') // "What's the resource ID of the AzureFirewallSubnet? This is needed to place the firewall in the correct subnet. It should look like '/subscriptions/{subscriptionId}/resourceGroups/{resourceGroupName}/providers/Microsoft.Network/virtualNetworks/{vnetName}/subnets/AzureFirewallSubnet'."
param firewallSubnetId string

@description('Deploy the firewall? Set false to save ~€912/month during dev/test.') // "Do you want to deploy the Azure Firewall? Set to false to skip deploying the firewall and save costs during development and testing. You can still deploy the Firewall Policy and review rules without the firewall."
param deployFirewall bool = false

@description('SKU tier. Standard has all features we need. Premium adds TLS inspection and IDPS.') // "Which SKU tier do you want for the Firewall Policy? 'Standard' has all the features we need. 'Premium' adds advanced features like TLS inspection and intrusion detection, but is more expensive. For most use cases, 'Standard' is sufficient."
@allowed([
  'Standard'
  'Premium'
])
param skuTier string = 'Standard'

@description('Tags for cost allocation and governance.') // "Tags are key-value pairs that help with cost allocation and governance. Please provide any tags you want to apply to the firewall and firewall policy resources. For example: { 'Environment': 'Prod', 'Project': 'AZLLandingZone' }."
param tags object

// -- Public IP ---------------------------------------------------------------
//
// Azure Firewall requires a public IP for outbound internet access and for
// DNAT rules (inbound from internet). Without a public IP, the firewall
// can still inspect internal traffic but can't route to/from the internet.
//
// We only create this if the firewall is being deployed.

resource firewallPublicIp 'Microsoft.Network/publicIPAddresses@2024-05-01' = if (deployFirewall) { // "Create a public IP address for the firewall. This is required for outbound internet access and inbound DNAT rules. We use static allocation to ensure the IP doesn't change, and the Standard SKU which is required for Azure Firewall."
  name: 'pip-${firewallName}'
  location: location
  tags: tags
  sku: {
    // Standard SKU is required for Azure Firewall. Basic won't work.
    // Standard provides zone-redundancy and static allocation.
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
  }
}

// -- Firewall Policy ---------------------------------------------------------
//
// The policy is always created (even if firewall isn't deployed) so you can
// define and review rules without incurring firewall costs.

resource firewallPolicy 'Microsoft.Network/firewallPolicies@2024-05-01' = { // "Create the Firewall Policy with the specified name, location, SKU tier, and tags. The policy will be created even if the firewall itself is not deployed, allowing you to define and review rules without incurring firewall costs."
  name: firewallPolicyName
  location: location
  tags: tags
  properties: {
    sku: {
      tier: skuTier
    }
    // Threat Intelligence: Microsoft maintains a feed of known malicious IPs.
    // 'Alert' mode logs the traffic but doesn't block it. Use 'Deny' in
    // production to auto-block known threats. We use 'Alert' during setup
    // so we can see what's being flagged without breaking things.
    threatIntelMode: 'Alert'
  }
}

// -- Rule Collection Groups --------------------------------------------------
//
// We organize rules into groups by purpose. Each group has a priority —
// lower number = evaluated first.

resource networkRuleCollectionGroup 'Microsoft.Network/firewallPolicies/ruleCollectionGroups@2024-05-01' = { // Network rules are L3/L4 rules that match on IP, port, protocol. They are
  parent: firewallPolicy
  name: 'DefaultNetworkRuleCollectionGroup'
  properties: {
    priority: 200
    ruleCollections: [
      {
        // SPOKE-TO-SPOKE RULES
        // By default, even though spokes peer with the hub, they can't reach
        // each other directly. These rules explicitly allow controlled
        // cross-spoke communication through the firewall.
        ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
        name: 'AllowSpokeToSpoke'
        priority: 100
        action: {
          type: 'Allow'
        }
        rules: [
          {
            ruleType: 'NetworkRule'
            name: 'AllowProdToDevHTTPS'
            description: 'Allow production apps to reach dev APIs for testing'
            ipProtocols: ['TCP']
            sourceAddresses: ['10.1.0.0/16']  // Prod spoke
            destinationAddresses: ['10.2.0.0/16']  // Dev spoke
            destinationPorts: ['443']
          }
          {
            ruleType: 'NetworkRule'
            name: 'AllowDevToProdHTTPS'
            description: 'Allow dev spoke to reach prod APIs (restricted)'
            ipProtocols: ['TCP']
            sourceAddresses: ['10.2.0.0/16']
            destinationAddresses: ['10.1.0.0/16']
            destinationPorts: ['443']
          }
        ]
      }
      {
        // DNS RULES
        // VMs need to resolve DNS. Azure DNS is at 168.63.129.16 (a special
        // virtual IP that Azure routes internally). Without this rule, DNS
        // resolution from spoke VMs would be blocked.
        ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
        name: 'AllowDNS'
        priority: 110
        action: {
          type: 'Allow'
        }
        rules: [
          {
            ruleType: 'NetworkRule'
            name: 'AllowDNSToAzure'
            description: 'Allow all VNets to reach Azure DNS'
            ipProtocols: ['TCP', 'UDP']
            sourceAddresses: ['10.0.0.0/8']  // All RFC1918 space we use
            destinationAddresses: ['168.63.129.16']  // Azure DNS
            destinationPorts: ['53']
          }
        ]
      }
    ]
  }
}

resource applicationRuleCollectionGroup 'Microsoft.Network/firewallPolicies/ruleCollectionGroups@2024-05-01' = { // Application rules are L7 rules that match on FQDNs. They are evaluated after network rules. If traffic matches a network rule, application rules are not evaluated.
  parent: firewallPolicy
  name: 'DefaultApplicationRuleCollectionGroup'
  // Must depend on the network rules group because only one rule collection
  // group can be deployed at a time (Azure limitation).
  dependsOn: [networkRuleCollectionGroup]
  properties: {
    priority: 300
    ruleCollections: [
      {
        // WINDOWS UPDATE
        // VMs need to pull updates from Microsoft. These FQDNs are the
        // standard Windows Update endpoints. Without this, your VMs will
        // never get security patches — a compliance nightmare for AZL.
        ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
        name: 'AllowWindowsUpdate'
        priority: 100
        action: {
          type: 'Allow'
        }
        rules: [
          {
            ruleType: 'ApplicationRule'
            name: 'WindowsUpdate'
            description: 'Allow Windows Update traffic'
            sourceAddresses: ['10.0.0.0/8']
            protocols: [
              { protocolType: 'Https', port: 443 }
              { protocolType: 'Http', port: 80 }
            ]
            // Azure Firewall application rules can match on FQDNs.
            // These are Microsoft's documented Windows Update endpoints.
            targetFqdns: [
              '*.windowsupdate.com'
              '*.update.microsoft.com'
              '*.windowsupdate.microsoft.com'
              '*.download.windowsupdate.com'
            ]
          }
        ]
      }
      {
        // AZURE MANAGEMENT
        // VMs with Azure Monitor Agent, Azure AD authentication, or other
        // Azure services need to reach Azure management endpoints.
        ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
        name: 'AllowAzureManagement'
        priority: 110
        action: {
          type: 'Allow'
        }
        rules: [
          {
            ruleType: 'ApplicationRule'
            name: 'AzureManagement'
            description: 'Allow traffic to Azure management plane'
            sourceAddresses: ['10.0.0.0/8']
            protocols: [
              { protocolType: 'Https', port: 443 }
            ]
            targetFqdns: [
              // Note: environment().resourceManager returns 'https://management.azure.com/'
              // but firewall FQDN rules need just the hostname. We suppress the linter warning
              // because the environment() values include protocol/path that break FQDN rules.
              #disable-next-line no-hardcoded-env-urls
              'management.azure.com'
              #disable-next-line no-hardcoded-env-urls
              'login.microsoftonline.com'
              '*.blob.${environment().suffixes.storage}'             // *.blob.core.windows.net
              '*.table.${environment().suffixes.storage}'            // *.table.core.windows.net
              '*.opinsights.azure.com'        // Log Analytics
              '*.ods.opinsights.azure.com'    // Log Analytics data
              '*.monitoring.azure.com'         // Azure Monitor
            ]
          }
        ]
      }
    ]
  }
}

// -- Azure Firewall ----------------------------------------------------------

resource firewall 'Microsoft.Network/azureFirewalls@2024-05-01' = if (deployFirewall) { // "Create the Azure Firewall with the specified name, location, tags, SKU, associated Firewall Policy, and IP configuration. The firewall will only be deployed if 'deployFirewall' is set to true to allow for cost savings during development and testing."
  name: firewallName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'AZFW_VNet'  // VNet-integrated mode (vs. AZFW_Hub for Virtual WAN)
      tier: skuTier
    }
    firewallPolicy: {
      id: firewallPolicy.id
    }
    ipConfigurations: [
      {
        name: 'AzureFirewallIpConfig'
        properties: {
          subnet: {
            id: firewallSubnetId
          }
          publicIPAddress: {
            id: firewallPublicIp.id
          }
        }
      }
    ]
  }
}

// -- Outputs -----------------------------------------------------------------

@description('Firewall private IP. Used in route tables to direct spoke traffic through the firewall.') // "What is the private IP address of the firewall? This is used in route tables to direct spoke traffic through the firewall. If the firewall is not deployed, this will be an empty string."
output firewallPrivateIp string = deployFirewall ? firewall!.properties.ipConfigurations[0].properties.privateIPAddress : ''

@description('Firewall public IP address. Used for DNAT rules and documentation.') // "What is the public IP address of the firewall? This is used for DNAT rules and documentation. If the firewall is not deployed, this will be an empty string."
output firewallPublicIpAddress string = deployFirewall ? firewallPublicIp!.properties.ipAddress : ''

@description('Firewall resource ID.') // "What is the resource ID of the firewall? This can be used for referencing the firewall in other modules or for documentation. If the firewall is not deployed, this will be an empty string."
output firewallId string = deployFirewall ? firewall.id : ''

@description('Firewall Policy resource ID. Always created even if firewall is not deployed.') // "What is the resource ID of the Firewall Policy? This is always created even if the firewall itself is not deployed, allowing you to define and review rules without incurring firewall costs."
output firewallPolicyId string = firewallPolicy.id
