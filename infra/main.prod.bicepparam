// ============================================================================
// PARAMETER FILE: Production Environment
// ============================================================================
//
// HOW TO USE:
//   az deployment sub create \
//     --location westeurope \
//     --template-file infra/main.bicep \
//     --parameters infra/main.prod.bicepparam \
//     --parameters jumpboxAdminPassword='YourP@ssw0rd!'
//
// PRODUCTION DIFFERENCES FROM DEV:
//   - Firewall and Bastion are always-on (critical for client operations)
//   - Log Analytics retention is 90 days (vs 30 in dev)
//   - Backup policy retention is longer
//   - These are the settings admins would run for a real managed client
//
// ============================================================================

using './main.bicep'

param environment = 'prod'
param location = 'westeurope'
param tags = {
  Environment: 'Production'
  ManagedBy: 'alzadmin'
  Project: 'ALZ'
  CostCenter: 'IT-Infra-001'
}

// Phase 2: Production — all security resources deployed
param deployFirewall = true      // Always-on in prod. Central traffic inspection.
param deployBastion = true       // Always-on in prod. Secure VM access.
param jumpboxAdminUsername = 'azureadmin'

// Phase 3
param alertEmailAddress = 'ops@alz.nl'
param deployerObjectId = ''      // Set to your SP object ID for Key Vault RBAC
