// ============================================================================
// MODULE: Jumpbox Virtual Machine
// ============================================================================
//
// WHAT THIS IS:
//   A jumpbox (or "jump server" or "bastion host" — not to be confused with
//   Azure Bastion the service) is a management VM that sits in the hub's
//   management subnet. Admins connect to this VM first, then from here they
//   can reach resources in any spoke VNet.
//
// WHY A JUMPBOX:
//   Even with Azure Bastion, you often need a persistent management
//   workstation inside the network. Reasons:
//   - Run PowerShell scripts that need to be inside the VNet
//   - Use tools that can't run through Bastion's browser session (e.g., SSMS)
//   - Troubleshoot networking by pinging/tracerouting from inside the VNet
//   - Act as a deployment agent for Azure DevOps self-hosted pipelines
//
// SECURITY DESIGN:
//   - NO public IP. Access only through Azure Bastion.
//   - Sits in ManagementSubnet which has an NSG allowing only Bastion traffic.
//   - Managed disk (encrypted at rest by default with platform-managed keys).
//   - Admin password stored in Key Vault (never in parameter files or code).
//   - Auto-shutdown tag for cost savings in dev/test.
//
// VM SIZE:
//   B2s (2 vCPUs, 4 GB RAM, ~€35/month). This is a burstable VM — it
//   accumulates CPU credits when idle and uses them when busy. Perfect for
//   a jumpbox that's mostly idle and occasionally runs scripts.
//
// ============================================================================

// -- Parameters --------------------------------------------------------------

@description('Name of the VM. Convention: vm-{role}-{env}-{number}. Max 15 chars for Windows (NetBIOS).')
@maxLength(15)
param vmName string

@description('Azure region.')
param location string = resourceGroup().location

@description('Resource ID of the subnet to place the VM in (ManagementSubnet).')
param subnetId string

@description('Admin username for the VM. Cannot be "admin", "administrator", or "root".')
param adminUsername string

@description('Admin password. Must be 12-123 chars with uppercase, lowercase, number, and special char. Passed from Key Vault — never hardcode this.')
@secure()
param adminPassword string

@description('VM size. B2s is cost-effective for a management jumpbox.')
param vmSize string = 'Standard_B2s'

@description('Resource ID of the Log Analytics workspace for monitoring agent.')
param logAnalyticsWorkspaceId string = ''

@description('Tags for cost allocation and governance.')
param tags object

// -- Network Interface -------------------------------------------------------
//
// Every VM needs a NIC (Network Interface Card) to connect to a subnet.
// The NIC gets a private IP from the subnet's address range (DHCP).
// We explicitly set no public IP — Bastion provides access.

resource nic 'Microsoft.Network/networkInterfaces@2024-05-01' = {
  name: 'nic-${vmName}'
  location: location
  tags: tags
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: subnetId
          }
          privateIPAllocationMethod: 'Dynamic'
          // No publicIPAddress property = no public IP. Intentional.
        }
      }
    ]
  }
}

// -- Virtual Machine ---------------------------------------------------------

resource vm 'Microsoft.Compute/virtualMachines@2024-07-01' = { // "Create the virtual machine with the specified name, location, tags, hardware profile, OS profile, storage profile, network profile, and diagnostics profile. The VM will be created in the specified subnet with no public IP address for security. The admin password should be securely stored in Key Vault and passed as a parameter to avoid hardcoding secrets." 
  name: vmName
  location: location
  tags: union(tags, {
    // Additional tags specific to this VM for operational automation
    AutoShutdown: 'true'     // PowerShell script targets this for cost savings
    BackupPolicy: 'Standard' // Recovery Vault uses this to assign backup policy
  })
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      adminPassword: adminPassword
      windowsConfiguration: {
        // Enable auto-updates. In a managed services environment, you want
        // VMs patched automatically. AZL would typically use Azure Update
        // Manager for controlled patching, but auto-updates are a safe default.
        enableAutomaticUpdates: true
        provisionVMAgent: true
        // Timezone set to Amsterdam 
        timeZone: 'W. Europe Standard Time'
      }
    }
    storageProfile: {
      imageReference: {
        // Windows Server 2022 Datacenter — the latest LTS Windows Server.
        // Azure edition includes Azure-specific optimizations (hotpatching,
        // SMB over QUIC, etc.)
        publisher: 'MicrosoftWindowsServer'
        offer: 'WindowsServer'
        sku: '2022-datacenter-azure-edition'
        version: 'latest'
      }
      osDisk: {
        name: 'osdisk-${vmName}'
        createOption: 'FromImage'
        managedDisk: {
          // Standard SSD is a good balance of cost/performance for a jumpbox.
          // Premium SSD is overkill, Standard HDD is too slow for Windows.
          storageAccountType: 'StandardSSD_LRS'
        }
        diskSizeGB: 128
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
        }
      ]
    }
    // Boot diagnostics help troubleshoot VM boot failures.
    // With managed storage, Azure stores the diagnostics automatically —
    // no need to point to a storage account.
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
      }
    }
  }
}

// -- Azure Monitor Agent Extension -------------------------------------------
//
// The Azure Monitor Agent (AMA) collects logs and metrics from the VM and
// sends them to Log Analytics. Without this, your VM is a black box —
// no CPU metrics, no event logs, no security logs in your central workspace.
//
// AMA replaced the legacy Log Analytics agent (MMA/OMS) in 2024.

resource monitoringExtension 'Microsoft.Compute/virtualMachines/extensions@2024-07-01' = if (!empty(logAnalyticsWorkspaceId)) { // "If a Log Analytics workspace ID is provided, deploy the Azure Monitor Agent extension to the VM. This will enable monitoring of the VM's performance and logs in the specified Log Analytics workspace. If 'logAnalyticsWorkspaceId' is empty, this extension will not be deployed, and the VM will not send monitoring data to Log Analytics."
  parent: vm
  name: 'AzureMonitorWindowsAgent'
  location: location
  tags: tags
  properties: {
    publisher: 'Microsoft.Azure.Monitor'
    type: 'AzureMonitorWindowsAgent'
    typeHandlerVersion: '1.0'
    autoUpgradeMinorVersion: true
    enableAutomaticUpgrade: true
  }
}

// -- Outputs -----------------------------------------------------------------

@description('Resource ID of the VM. Used for backup registration and monitoring.')
output vmId string = vm.id

@description('Name of the VM.')
output vmName string = vm.name

@description('Private IP address of the VM.')
output privateIpAddress string = nic.properties.ipConfigurations[0].properties.privateIPAddress
