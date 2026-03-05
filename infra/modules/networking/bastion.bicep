// ============================================================================
// MODULE: Azure Bastion
// ============================================================================
//
// WHAT THIS IS:
//   Azure Bastion provides secure RDP and SSH access to your VMs directly
//   from the Azure portal, without exposing any public IP on the VM.
//   You open the Azure portal → navigate to the VM → click "Connect" →
//   "Bastion" → enter credentials → you get an in-browser RDP/SSH session.
//
// WHY THIS MATTERS FOR AZL:
//   AZL manages client VMs 24/7. Their engineers need to RDP into VMs
//   for troubleshooting, patching, and configuration. Without Bastion, you'd
//   need to either:
//   a) Put a public IP on every VM (security nightmare — exposed to the internet)
//   b) Set up a VPN to the client's VNet (complex, maintenance overhead)
//   c) Use a jumpbox with a public IP (still one public IP exposed)
//
//   Bastion eliminates all of these. The connection goes:
//   Engineer's browser → Azure backbone (TLS) → Bastion → private IP of VM
//   Nothing is exposed to the internet. The VM has no public IP at all.
//
// HOW IT WORKS INTERNALLY:
//   Bastion deploys managed instances into AzureBastionSubnet. When you
//   click "Connect via Bastion" in the portal, Azure:
//   1. Establishes a TLS connection from your browser to the Bastion service
//   2. Bastion opens an RDP/SSH session to the VM's private IP
//   3. The session is streamed back to your browser as HTML5
//   You never install an RDP client. It's all in the browser.
//
// SUBNET REQUIREMENTS:
//   - Must be named exactly "AzureBastionSubnet"
//   - Minimum /26 (we use /26 = 64 addresses, 59 usable)
//   - No user-assigned NSG
//   - Bastion needs its own public IP (Standard SKU, static allocation)
//
// COST:
//   Basic SKU: ~€0.19/hour = ~€140/month. Deploy to verify, then tear down.
//
// ============================================================================

// -- Parameters --------------------------------------------------------------

@description('Name of the Bastion host. Convention: bas-{workload}-{region}') // "What should I name the Bastion host? Follow the convention 'bas-{workload}-{region}', e.g., 'bas-prod-weu' for a production Bastion in West Europe."
param bastionName string

@description('Azure region.') // "Where should I create the Bastion host? Defaults to the resource group's region."
param location string = resourceGroup().location

@description('Resource ID of the AzureBastionSubnet.') // "What is the resource ID of the AzureBastionSubnet where Bastion should be deployed? This subnet must be named 'AzureBastionSubnet' and meet the requirements outlined in the module documentation."
param bastionSubnetId string

@description('Deploy Bastion? Set false to save ~€140/month during dev/test.') // "Do you want to deploy the Bastion host? Set this to false to save approximately €140/month during development and testing. You can deploy the Bastion host later when you need it."
param deployBastion bool = false

@description('Tags for cost allocation and governance.') // "What tags should be applied to the Bastion host and its associated resources for cost allocation and governance? Provide a key-value object, e.g., { 'Environment': 'Production', 'Project': 'AZL' }."
param tags object

// -- Public IP ---------------------------------------------------------------
//
// Bastion requires its own dedicated public IP. This IP is used for the
// browser-to-Bastion TLS connection only — VMs behind Bastion still have
// no public IPs.

resource bastionPublicIp 'Microsoft.Network/publicIPAddresses@2024-05-01' = if (deployBastion) { // "Create the public IP address for the Bastion host with the specified name, location, tags, SKU, and properties. The public IP will only be deployed if 'deployBastion' is set to true to allow for cost savings during development and testing."
  name: 'pip-${bastionName}'
  location: location
  tags: tags
  sku: {
    name: 'Standard'  // Required for Bastion. Basic SKU won't work.
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
  }
}

// -- Bastion Host ------------------------------------------------------------

resource bastion 'Microsoft.Network/bastionHosts@2024-05-01' = if (deployBastion) { // "Create the Bastion host with the specified name, location, tags, SKU, and properties. The Bastion host will only be deployed if 'deployBastion' is set to true to allow for cost savings during development and testing."
  name: bastionName
  location: location
  tags: tags
  sku: {
    // Basic: RDP/SSH in browser. Good enough for our use case.
    // Standard: adds file upload/download, shareable links, IP-based connect.
    // We use Basic to minimize cost — upgrade to Standard if needed.
    name: 'Basic'
  }
  properties: {
    ipConfigurations: [
      {
        name: 'BastionIpConfig'
        properties: {
          subnet: {
            id: bastionSubnetId
          }
          publicIPAddress: {
            id: bastionPublicIp.id
          }
        }
      }
    ]
  }
}

// -- Outputs -----------------------------------------------------------------

@description('Bastion resource ID.') // "What is the resource ID of the Bastion host? This output will be empty if 'deployBastion' is set to false."
output bastionId string = deployBastion ? bastion.id : ''

@description('Bastion name.') // "What is the name of the Bastion host? This output will be empty if 'deployBastion' is set to false."
output bastionHostName string = deployBastion ? bastion.name : ''
