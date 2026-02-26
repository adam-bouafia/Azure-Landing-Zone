// N.B:
// NSG.bicep is a module to create a Network Security Group with rules and tags.
// let's think of it as a template and main.bicep is the caller that uses this template to create an NSG.


// ============================================================================
// MODULE: Network Security Group (NSG)
// ============================================================================
//
// WHAT THIS IS:
//   An NSG is basically a firewall at the subnet level. It contains a list of
//   security rules that allow or deny network traffic to/from resources in a
//   subnet. Think of it as a bouncer for your subnet — it checks every packet
//   against the rules and either lets it in or blocks it.
//
// WHY IT'S A SEPARATE MODULE:
//   Every subnet in our landing zone (except AzureFirewallSubnet, AzureBastionSubnet,
//   and GatewaySubnet) needs an NSG. By making it a reusable module, we can call
//   it once per subnet with different rules, instead of copy-pasting NSG definitions
//   everywhere.
//
// HOW RULES WORK:
//   - Rules are evaluated by PRIORITY (lowest number = highest priority).
//   - Once a match is found, processing stops. So a "deny all" at priority 4096
//     catches everything that wasn't explicitly allowed by higher-priority rules.
//   - Direction: "Inbound" = traffic coming INTO the subnet, "Outbound" = going OUT.
//   - Azure has default rules (priority 65000+) that you can't delete:
//     - Allow VNet-to-VNet inbound/outbound
//     - Allow Azure Load Balancer inbound
//     - Deny all other inbound
//     These defaults are why you see "AllowVnetInBound" in the portal even on a
//     brand new NSG.
//
// IMPORTANT CONSTRAINTS:
//   - AzureFirewallSubnet and AzureBastionSubnet: CANNOT have a user-assigned NSG. Azure manages it. 
//   - GatewaySubnet: CAN have an NSG but Microsoft recommends against it to
//     avoid breaking VPN/ExpressRoute traffic.
//
// ============================================================================



// Parameters
@description('NSG Name')
param nsgName string  // "What should I name this NSG?"

@description('Azure region')
param location string = resourceGroup().location // "Where?" (defaults to the RG's region)

@description('security rules')
param securityRules array = []        // "What rules do we want?"

@description('Tags')
param tags object      // "What tags to attach?"



// Resources 
resource nsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: nsgName
  location: location 
  tags: tags
  properties: {
    // The security rules array is mapped from our parameter.
    // Each rule becomes a child resource of the NSG.
    //
    // Priority ranges we use by convention:
    //   100-199  = Allow rules for specific trusted sources
    //   200-299  = Allow rules for internal subnet-to-subnet traffic
    //   300-399  = Allow rules for management traffic (Bastion, monitoring)
    //   4000-4096 = Explicit deny-all catch rules

    securityRules: [for rule in securityRules: { // "Let's loop through the rules and create them."
      name: rule.name
      properties: {
        priority: rule.priority
        direction: rule.direction // "Inbound or Outbound?" 
        access: rule.access   // "Allow or Deny?"   
        protocol: rule.protocol // "TCP, UDP, or * for Any?" 
        sourceAddressPrefix: rule.sourceAddressPrefix // "Where is the traffic coming from?"
        sourcePortRange: rule.sourcePortRange // "Which port is the traffic coming from?"
        destinationAddressPrefix: rule.destinationAddressPrefix // "Where is the traffic going to?"
        destinationPortRange: rule.destinationPortRange // "Which port is the traffic going to?"
      }
    }]
  }
}




// Outputs

@description('Resource ID')
output nsgId string = nsg.id // "Here's the ID of the NSG we created, in case we need it for other resources."

@description('Name of the created NSG.')
output nsgName string = nsg.name // "Just confirming, the NSG we created is named: ${nsg.name}."
