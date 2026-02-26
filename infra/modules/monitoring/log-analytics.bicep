// ============================================================================
// MODULE: Log Analytics Workspace
// ============================================================================
//
// WHAT THIS IS:
//   Log Analytics is the central log sink for the entire landing zone. Every
//   Azure resource sends its diagnostic logs and metrics here. It's where
//   InSpark's engineers go to investigate incidents, analyze performance,
//   and run security audits.
//
// HOW IT WORKS:
//   - Resources send data via "diagnostic settings" (configured per resource)
//   - VMs send data via the Azure Monitor Agent (installed as a VM extension)
//   - Data is stored in tables and queried using KQL (Kusto Query Language)
//   - Retention: 90 days of interactive query, then data can be archived
//
// WHY CENTRALIZED:
//   One workspace for the entire landing zone means:
//   - Cross-resource queries: "show me all denied NSG flows AND high CPU VMs"
//   - Single alert management: all alerts from one place
//   - Consistent retention policies
//   - Sentinel-ready: Azure Sentinel (SIEM) connects to this same workspace
//
// SOLUTIONS:
//   VMInsights: correlates VM performance data (CPU, memory, disk, network)
//   into a visual map. Shows dependencies between VMs and services.
//
// ============================================================================

// -- Parameters --------------------------------------------------------------

@description('Log Analytics workspace name')
param workspaceName string // "What should I name this workspace? Must be globally unique across Azure."

@description('Azure region.')
param location string = resourceGroup().location // "Where?" (defaults to the RG's region)

@description('Data retention in days. 90 is typical for managed services. Range: 30-730.')
@minValue(30)
@maxValue(730)
param retentionInDays int = 90 // "How long should I keep the data? 90 days is a good balance for most use cases."

@description('Tags for cost allocation and governance.')
param tags object // "What tags should I attach to this workspace? E.g. { "Environment": "Prod", "CostCenter": "12345" }"

// -- Resource ----------------------------------------------------------------

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = { // "Create a Log Analytics workspace with the specified name, location, retention, and tags."
  name: workspaceName
  location: location
  tags: tags
  properties: {
    sku: {
      // PerGB2018 = pay-per-GB pricing model. This is the default and best
      // choice for workspaces ingesting < 100 GB/day. For high-volume
      // workspaces, commitment tiers (100/200/300 GB/day) offer discounts.
      name: 'PerGB2018' // "Which pricing tier? PerGB2018 is pay-as-you-go, good for most use cases."
    }
    retentionInDays: retentionInDays 

    // Features
    features: {
      // Enable log search, which allows querying across workspaces
      enableLogAccessUsingOnlyResourcePermissions: true // "Allow users with RBAC permissions on the workspace to query logs, 
      // without needing additional permissions on the underlying storage account."
    }
  }
}

// -- VMInsights Solution -----------------------------------------------------
//
// This enables the "VM Insights" experience in the Azure portal.
// Without this solution, you only get raw Perf counters. With it, you get:
// - Performance charts (CPU, memory, disk, network) with trendlines
// - Dependency maps showing which VMs talk to which services
// - Health monitoring with predefined conditions

resource vmInsights 'Microsoft.OperationsManagement/solutions@2015-11-01-preview' = { // "Deploy the VM Insights solution into our workspace 
// to get enhanced VM monitoring and dependency mapping."
  name: 'VMInsights(${workspaceName})'
  location: location
  tags: tags
  plan: {
    name: 'VMInsights(${workspaceName})' // "The plan name must match the solution name for marketplace solutions."
    publisher: 'Microsoft' // "The publisher of the solution. For official Microsoft solutions, this is 'Microsoft'."
    product: 'OMSGallery/VMInsights' // "The product identifier for the solution. This tells Azure which solution to deploy. VMInsights is a popular choice for monitoring VMs."
    promotionCode: '' // "Optional promotion code for the solution. Usually left blank."
  }
  properties: {
    workspaceResourceId: workspace.id // "Link this solution to our Log Analytics workspace by providing its resource ID."
  }
}

// -- Outputs -----------------------------------------------------------------

@description('Resource ID of the Log Analytics workspace. Used by diagnostic settings and agents.') // "Here's the resource ID of the workspace we created
// which other resources can use to send data here."
output workspaceId string = workspace.id

@description('Name of the workspace.') // "Here's the name of the workspace we created
//in case we need it for display or other resources."
output workspaceName string = workspace.name

@description('Workspace customer ID (also called workspace ID). Used by agents to identify which workspace to send data to.') // "Here's the customer ID of the workspace, 
//which is needed for agents like the Azure Monitor Agent to send data to this workspace."
output workspaceCustomerId string = workspace.properties.customerId
