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
//   export JUMPBOX_ADMIN_PASSWORD='YourP@ssw0rd!'
//   az deployment sub create \
//     --location westeurope \
//     --parameters infra/main.dev.bicepparam
//
// NOTE ON SECURE PARAMETERS:
//   jumpboxAdminPassword is @secure() — it CANNOT be hardcoded in this file.
//   It reads from the JUMPBOX_ADMIN_PASSWORD environment variable at deploy time.
//   Set it before deploying:
//     export JUMPBOX_ADMIN_PASSWORD='YourP@ssw0rd!'
//     az deployment sub create \
//       --location westeurope \
//       --parameters infra/main.dev.bicepparam
//
// ============================================================================

using './main.bicep'

param environment = 'dev'
param location = 'westeurope'
param tags = {
  Environment: 'Development'
  ManagedBy: 'alzadmin'
  Project: 'alz'
  CostCenter: 'IT-Infra-001'
}

// Phase 2: Cost-saving defaults for dev
param deployFirewall = false     // ~€912/month — only deploy to test, then tear down
param deployBastion = false      // ~€140/month — deploy when you need VM access
param jumpboxAdminUsername = 'azureadmin'
// Password is read from env var — set it before deploying:
//   export JUMPBOX_ADMIN_PASSWORD='YourP@ssw0rd!'
param jumpboxAdminPassword = readEnvironmentVariable('JUMPBOX_ADMIN_PASSWORD')

// Phase 3
param alertEmailAddress = 'ops@alz.nl'
param deployerObjectId = ''      // Set to your SP object ID for Key Vault RBAC
