// ============================================================================
// MODULE: Diagnostic Settings (Reusable)
// ============================================================================
//
// WHAT THIS IS:
//   Diagnostic settings tell an Azure resource WHERE to send its logs and
//   metrics. Without diagnostic settings, a resource generates data but
//   doesn't send it anywhere — it's lost.
//
// WHY REUSABLE:
//   Every resource needs diagnostic settings: VNets, NSGs, Firewall, Key Vault,
//   Storage Accounts, etc. Instead of writing diagnostic settings inline in
//   every module, we create a reusable module that takes a resource ID and
//   connects it to Log Analytics.
//
// WHAT GETS SENT:
//   - Logs: audit events, operations, security events (varies by resource type)
//   - Metrics: CPU, memory, throughput, latency (varies by resource type)
//
//   We use 'categoryGroup: allLogs' to capture everything. In production,
//   you might selectively disable noisy categories to reduce ingestion cost.
//
// HOW TO USE THIS MODULE:
//   Call it once per resource you want to monitor. Example:
//
//   module hubVnetDiag 'modules/monitoring/diagnostics.bicep' = {
//     params: {
//       resourceId: hubVnet.outputs.hubVnetId
//       resourceName: 'vnet-hub-weu'
//       logAnalyticsWorkspaceId: logAnalytics.outputs.workspaceId
//     }
//   }
//
// ============================================================================

// -- Parameters --------------------------------------------------------------

@description('Resource ID of the resource to enable diagnostics on.')
param resourceId string

@description('Friendly name for the diagnostic setting. Convention: diag-{resourceName}')
param resourceName string

@description('Resource ID of the Log Analytics workspace to send data to.')
param logAnalyticsWorkspaceId string

@description('Enable log collection. Default: true.')
param enableLogs bool = true

@description('Enable metrics collection. Default: true.')
param enableMetrics bool = true

// -- Resource ----------------------------------------------------------------
//
// Diagnostic settings are a special resource type. They're "extension resources"
// that attach to another resource. The 'scope' keyword in the module call
// or the resource ID in the name determines which resource they attach to.
//
// Note: we use the 'existing' + scope pattern here. The caller passes the
// resource ID and this module creates the diagnostic setting as a child.

resource diagnosticSetting 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = { // "Create a diagnostic setting with the specified name and properties. This setting will send logs and metrics from the target resource (identified by 'resourceId') to the specified Log Analytics workspace. The 'enableLogs' and 'enableMetrics' parameters control whether logs and metrics are collected, respectively. The diagnostic setting will be attached to the target resource using the 'scope' keyword, allowing it to collect data from that resource."
  name: 'diag-${resourceName}'
  // The 'scope' is set by the caller via the module's scope parameter.
  // This attaches the diagnostic setting to the target resource.
  scope: any(resourceId)  // Using any() because the scope needs the actual resource reference
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: enableLogs ? [
      {
        categoryGroup: 'allLogs'
        enabled: true
        retentionPolicy: {
          enabled: false  // Retention managed at workspace level
          days: 0
        }
      }
    ] : []
    metrics: enableMetrics ? [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
    ] : []
  }
}

// -- Outputs -----------------------------------------------------------------

@description('Resource ID of the diagnostic setting.')
output diagnosticSettingId string = diagnosticSetting.id
