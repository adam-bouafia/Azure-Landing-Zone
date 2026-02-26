// ============================================================================
// MODULE: Diagnostics Storage Account
// ============================================================================
//
// WHAT THIS IS:
//   A storage account used for diagnostic data that doesn't go to Log Analytics:
//   - VM boot diagnostics (screenshots of the boot process for troubleshooting)
//   - NSG flow logs (raw network flow data — who talked to who)
//   - Long-term log archival (cheaper than keeping data in Log Analytics forever)
//
// WHY A SEPARATE STORAGE ACCOUNT:
//   Diagnostic data is high-volume and rarely accessed. Mixing it with
//   application storage makes cost tracking harder and can hit storage
//   account performance limits. A dedicated account with cool/archive
//   tiers keeps costs down.
//
// NAMING CONSTRAINT:
//   Storage account names must be globally unique, 3-24 characters,
//   lowercase letters and numbers ONLY. No dashes, no underscores.
//   This is why storage accounts break every naming convention ever created.
//
// ============================================================================

// -- Parameters --------------------------------------------------------------

@description('Name of the storage account. Must be globally unique, 3-24 chars, lowercase + numbers only.') // "What should I name this storage account? 
// Remember, it must be globally unique and can only contain lowercase letters and numbers."
@minLength(3)
@maxLength(24)
param storageAccountName string

@description('Azure region.') // "Where should I create this storage account? Defaults to the resource group's region."
param location string = resourceGroup().location

@description('Tags for cost allocation and governance.') // "What tags should I attach to this storage account?
param tags object

// -- Resource ----------------------------------------------------------------

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = { // "Create a storage account with the specified 
// name, location, tags, and properties optimized for diagnostics data."
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    // LRS = Locally Redundant Storage (3 copies in one datacenter).
    // For diagnostics data, LRS is fine — if we lose it, we can regenerate.
    // Production application data would use GRS (geo-redundant) or ZRS (zone).
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'  // General-purpose v2 — supports all storage services and tiers
  properties: {
    // TLS 1.2 minimum. TLS 1.0 and 1.1 have known vulnerabilities.
    minimumTlsVersion: 'TLS1_2'

    // Disable public blob access. Diagnostic data should never be publicly
    // accessible. Resources access it via private network or service endpoints.
    allowBlobPublicAccess: false

    // HTTPS only. No unencrypted HTTP traffic to/from storage.
    supportsHttpsTrafficOnly: true

    accessTier: 'Cool'  // Cheaper for infrequently accessed data
  }
}

// -- Outputs -----------------------------------------------------------------

@description('Resource ID of the storage account.') // "Here's the resource ID of the storage account we created, in case we need it for other resources or outputs."
output storageAccountId string = storageAccount.id

@description('Name of the storage account.') // "Here's the name of the storage account we created, which might be needed for configuring diagnostic settings on other resources."
output storageAccountName string = storageAccount.name
