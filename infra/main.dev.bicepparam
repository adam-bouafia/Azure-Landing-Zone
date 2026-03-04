// ============================================================================
// PARAMETER FILE: Development Environment
// ============================================================================
//
// WHAT THIS IS:
//   A .bicepparam file provides values for parameters defined in the Bicep template.
//   Instead of passing --parameters environment=dev on the command line, you put
//   all values in this file. This ensures consistent deployments — every time you
//   deploy dev, it uses the same parameters.
//
// HOW TO USE:
//   az deployment sub create \
//     --location westeurope \
//     --template-file infra/main.bicep \
//     --parameters infra/main.dev.bicepparam \
//     --parameters jumpboxAdminPassword='YourP@ssw0rd!'
//
// NOTE ON SECURE PARAMETERS:
//   jumpboxAdminPassword is @secure() — it CANNOT be stored in this file.
//   Always pass it at deployment time via command line or Key Vault reference.
//
// ============================================================================

using './main.bicep'

param environment = 'dev'
param location = 'westeurope'
param tags = {
  Environment: 'Development'
  ManagedBy: 'alzadmin'
  Project: 'ALZ'
  CostCenter: 'IT-Infra-001'
}

// Phase 2: Cost-saving defaults for dev
param deployFirewall = false     // ~€912/month — only deploy to test, then tear down
param deployBastion = false      // ~€140/month — deploy when you need VM access
param jumpboxAdminUsername = 'azureadmin'

// Phase 3
param alertEmailAddress = 'ops@alz.nl'
param deployerObjectId = ''      // Set to your SP object ID for Key Vault RBAC
