// ============================================================================
// MODULE: Azure Key Vault
// ============================================================================
//
// WHAT THIS IS:
//   Key Vault is Azure's secret management service. It securely stores and
//   controls access to secrets (passwords, connection strings), encryption
//   keys, and certificates. Think of it as a hardware security module (HSM)
//   in the cloud.
//
// WHY WE NEED IT:
//   Our jumpbox VM has an admin password. That password should NEVER be:
//   - Hardcoded in Bicep files (they're in source control)
//   - Stored in pipeline variables (visible in logs)
//   - Written in a parameter file (committed to git)
//
//   Instead, we store it in Key Vault and reference it at deployment time.
//   The Bicep deployment reads the secret from Key Vault and passes it to
//   the VM module as a @secure() parameter — it never appears in plain text.
//
// RBAC VS ACCESS POLICIES:
//   See ADR-003 in DECISIONS.md. We use RBAC authorization because:
//   - Consistent with how we manage permissions for every other Azure resource
//   - Granular built-in roles (Secrets User, Crypto Officer, etc.)
//   - Azure Activity Log captures all permission changes
//
// SOFT DELETE + PURGE PROTECTION:
//   - Soft delete: when you "delete" a secret or the vault, it's retained for
//     90 days. You can recover it. This prevents accidental data loss.
//   - Purge protection: even with soft delete, someone could "purge" (permanently
//     delete) a soft-deleted vault. Purge protection prevents this for the
//     retention period. Once enabled, it CANNOT be disabled.
//   Both are enabled because this is a managed services environment — accidental
//   deletion of secrets could cause outages for the client.
//
// NAMING CONSTRAINT:
//   Key Vault names must be globally unique across all of Azure (like storage
//   accounts). They're 3-24 characters, alphanumeric + dashes only.
//
// ============================================================================

// -- Parameters --------------------------------------------------------------

@description('Name of the Key Vault. Must be globally unique, 3-24 chars. Convention: kv-{workload}-{env}-{unique}')
@minLength(3)
@maxLength(24)
param keyVaultName string

@description('Azure region.')
param location string = resourceGroup().location

@description('Tags for cost allocation and governance.')
param tags object

@description('Resource ID of the Log Analytics workspace for diagnostic logs.')
param logAnalyticsWorkspaceId string = ''

@description('Object ID of the principal (user or service principal) that should have Secrets Officer role. This allows the deployer to write secrets.')
@secure()
param secretsOfficerObjectId string = ''

// -- Key Vault ---------------------------------------------------------------

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    tenantId: subscription().tenantId
    sku: {
      // Standard tier: software-protected keys. Good for secrets and certs.
      // Premium tier: adds HSM-backed keys. Overkill for our use case.
      family: 'A'
      name: 'standard'
    }

    // RBAC authorization — see ADR-003
    enableRbacAuthorization: true

    // Soft delete: retained for 90 days after deletion.
    // This is actually enabled by default since Feb 2025 and can't be
    // disabled on new vaults, but we're explicit about it.
    enableSoftDelete: true
    softDeleteRetentionInDays: 90

    // Purge protection: prevents permanent deletion during retention period.
    enablePurgeProtection: true

    // Network ACLs: by default, allow access from all networks.
    // In production with Private Endpoints, you'd set defaultAction to 'Deny'
    // and add the hub VNet as an allowed network. We keep it open initially
    // so the deployment pipeline can write secrets.
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'  // Allow Azure services (backup, monitoring) to reach KV
    }
  }
}

// -- RBAC Role Assignment: Secrets Officer -----------------------------------
//
// The "Key Vault Secrets Officer" role lets the assigned principal read, write,
// and delete secrets. We assign this to the deployer so the pipeline can
// store the jumpbox admin password.
//
// Built-in role IDs (these are the same across all Azure tenants):
//   Key Vault Secrets Officer: b86a8fe4-44ce-4948-aee5-eccb2c155cd7
//   Key Vault Secrets User:    4633458b-17de-408a-b874-0445c86b69e6
//   Key Vault Administrator:   00482a5a-887f-4fb3-b363-3b7fe8e74483

resource secretsOfficerRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(secretsOfficerObjectId)) {
  // Role assignment names must be GUIDs. We generate a deterministic one
  // from the Key Vault ID and principal ID so it's idempotent (running
  // the deployment twice doesn't create a duplicate assignment).
  name: guid(keyVault.id, secretsOfficerObjectId, 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7')
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7')
    principalId: secretsOfficerObjectId
    principalType: 'ServicePrincipal'
  }
}

// -- Diagnostic Settings -----------------------------------------------------
//
// Send Key Vault audit logs to Log Analytics. This captures:
// - Every secret read/write/delete
// - Every authentication attempt
// - Every permission change
// Essential for security auditing in a managed services environment.

resource diagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (!empty(logAnalyticsWorkspaceId)) {
  name: 'diag-${keyVaultName}'
  scope: keyVault
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
        retentionPolicy: {
          enabled: false  // Retention is managed at the workspace level
          days: 0
        }
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
    ]
  }
}

// -- Outputs -----------------------------------------------------------------

@description('Resource ID of the Key Vault.')
output keyVaultId string = keyVault.id

@description('Name of the Key Vault.')
output keyVaultName string = keyVault.name

@description('URI of the Key Vault. Used by applications to reference secrets.')
output keyVaultUri string = keyVault.properties.vaultUri
