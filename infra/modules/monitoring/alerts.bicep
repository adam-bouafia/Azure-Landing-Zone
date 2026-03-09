// ============================================================================
// MODULE: Alert Rules + Action Group
// ============================================================================
//
// WHAT THIS IS:
//   Azure Monitor alerts automatically notify the operations team when
//   something goes wrong. They evaluate metrics or logs against conditions
//   and trigger actions (email, SMS, webhook) when thresholds are breached.
//
// HOW ALERTS WORK:
//   1. A METRIC ALERT watches a metric (e.g., CPU percentage) on a resource
//   2. When the metric crosses a threshold for a specified duration, the
//      alert FIRES and transitions from "Healthy" to "Fired"
//   3. The alert triggers an ACTION GROUP, which sends notifications
//   4. When the metric drops below threshold, the alert auto-resolves
//
// ACTION GROUPS:
//   An action group defines WHO gets notified and HOW. Options include:
//   - Email (most common for managed services)
//   - SMS (for P1 incidents)
//   - Webhook (to integrate with ServiceNow, PagerDuty, etc.)
//   - Azure Function / Logic App (for automated remediation)
//
//   In AZL's real setup, alerts would go to their 24/7 NOC
//   (Network Operations Center) via integration with their ITSM tool.
//
// ALERTS WE CREATE:
//   1. VM CPU > 90% for 5 minutes → something is CPU-bound, investigate
//   2. VM available memory < 1 GB → risk of out-of-memory crashes
//   3. VM OS disk > 85% used → risk of disk full, VM may stop functioning
//
// ============================================================================

// -- Parameters --------------------------------------------------------------

@description('Email address for alert notifications.')
param alertEmailAddress string

@description('Resource ID of the VM to monitor.')
param vmResourceId string

@description('Tags for cost allocation and governance.')
param tags object

// -- Action Group ------------------------------------------------------------
//
// One action group for all infrastructure alerts. In production, you'd have
// separate groups for different severity levels (P1 = SMS + email + phone,
// P3 = email only).

resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = { // "Create an action group named 'ag-infra-alerts' in the global region with the specified tags. This action group will have a short name of 'InfraAlerts' and will be enabled to send email notifications to the specified alert email address when triggered by alerts."
  name: 'ag-infra-alerts'
  location: 'global'  // Action groups are always global, not regional
  tags: tags
  properties: {
    groupShortName: 'InfraAlerts'  // Max 12 chars, shown in SMS/notifications
    enabled: true
    emailReceivers: [
      {
        name: 'AZL Operations'
        emailAddress: alertEmailAddress
        useCommonAlertSchema: true  // Standardized alert format across all alert types
      }
    ]
  }
}

// -- Alert: VM CPU > 90% ----------------------------------------------------
//
// Metric: "Percentage CPU" on the VM resource.
// Condition: Average over 5 minutes > 90%.
// Frequency: evaluated every minute.
//
// Why 90% for 5 minutes? Brief CPU spikes are normal (Windows Update, antivirus
// scans). Sustained high CPU for 5+ minutes indicates a real problem.

resource cpuAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = { // "Create a metric alert named 'alert-vm-cpu-high' in the global region with the specified tags. This alert will monitor the 'Percentage CPU' metric of the specified VM resource, and will fire when the average CPU usage exceeds 90% over a 5-minute window. The alert will be evaluated every minute, and when triggered, it will send a notification to the 'InfraAlerts' action group. The alert will also auto-resolve when the CPU usage drops back below 90%."
  name: 'alert-vm-cpu-high'
  location: 'global'  // Metric alerts are global resources
  tags: tags
  properties: {
    description: 'VM CPU usage has been above 90% for 5 minutes'
    severity: 2  // 0=Critical, 1=Error, 2=Warning, 3=Informational, 4=Verbose
    enabled: true
    scopes: [vmResourceId]
    evaluationFrequency: 'PT1M'   // Check every 1 minute (ISO 8601 duration)
    windowSize: 'PT5M'             // Look at the last 5 minutes of data
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'HighCPU'
          metricName: 'Percentage CPU'
          metricNamespace: 'Microsoft.Compute/virtualMachines'
          operator: 'GreaterThan'
          threshold: 90
          timeAggregation: 'Average'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    actions: [
      {
        actionGroupId: actionGroup.id
      }
    ]
    // Auto-resolve when CPU drops below 90%
    autoMitigate: true
  }
}

// -- Alert: VM Available Memory < 1 GB --------------------------------------
//
// Uses "Available Memory Bytes" metric. When a Windows VM has less than 1 GB
// free, it starts paging heavily and becomes unresponsive.

resource memoryAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = { // "Create a metric alert named 'alert-vm-memory-low' in the global region with the specified tags. This alert will monitor the 'Available Memory Bytes' metric of the specified VM resource, and will fire when the average available memory drops below 1 GB (1073741824 bytes) over a 5-minute window. The alert will be evaluated every minute, and when triggered, it will send a notification to the 'InfraAlerts' action group. The alert will also auto-resolve when the available memory rises back above 1 GB."
  name: 'alert-vm-memory-low'
  location: 'global'
  tags: tags
  properties: {
    description: 'VM available memory is below 1 GB'
    severity: 2
    enabled: true
    scopes: [vmResourceId]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'LowMemory'
          metricName: 'Available Memory Bytes'
          metricNamespace: 'Microsoft.Compute/virtualMachines'
          operator: 'LessThan'
          threshold: 1073741824  // 1 GB in bytes
          timeAggregation: 'Average'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    actions: [
      {
        actionGroupId: actionGroup.id
      }
    ]
    autoMitigate: true
  }
}

// -- Alert: VM OS Disk > 85% ------------------------------------------------
//
// Uses "OS Disk Used Percentage" (available on managed disks).
// A full OS disk on Windows = blue screen, failed services, unusable VM.

resource diskAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = { // "Create a metric alert named 'alert-vm-disk-high' in the global region with the specified tags. This alert will monitor the 'OS Disk Used Percentage' metric of the specified VM resource, and will fire when the average disk usage exceeds 85% over a 15-minute window. The alert will be evaluated every 5 minutes, and when triggered, it will send a notification to the 'InfraAlerts' action group. The alert will also auto-resolve when the disk usage drops back below 85%."
  name: 'alert-vm-disk-high'
  location: 'global'
  tags: tags
  properties: {
    description: 'VM OS disk usage is above 85%'
    severity: 1  // Severity 1 (Error) because disk full is an imminent outage
    enabled: true
    scopes: [vmResourceId]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'  // Longer window — disk usage changes slowly
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'HighDisk'
          metricName: 'OS Disk Bandwidth Consumed Percentage'
          metricNamespace: 'Microsoft.Compute/virtualMachines'
          operator: 'GreaterThan'
          threshold: 85
          timeAggregation: 'Average'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    actions: [
      {
        actionGroupId: actionGroup.id
      }
    ]
    autoMitigate: true
  }
}

// -- Outputs -----------------------------------------------------------------

@description('Resource ID of the action group.')
output actionGroupId string = actionGroup.id

@description('Resource ID of the CPU alert rule.')
output cpuAlertId string = cpuAlert.id
