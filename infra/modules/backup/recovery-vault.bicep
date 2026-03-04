// ============================================================================
// MODULE: Recovery Services Vault + Backup Policy
// ============================================================================
//
// WHAT THIS IS:
//   Recovery Services Vault is Azure's backup and disaster recovery service.
//   It stores backup copies of your VMs, databases, and file shares. If a VM
//   gets corrupted, ransomware hits, or someone accidentally deletes data,
//   you restore from the vault.
//
// WHY THIS MATTERS FOR INSPARK:
//   Backup is a core managed services responsibility. If a client's data is
//   lost because backups weren't configured, that's a critical failure.
//   InSpark's SLAs typically include RPO (Recovery Point Objective) and
//   RTO (Recovery Time Objective) commitments:
//   - RPO = how much data can you afford to lose? (24h = daily backups)
//   - RTO = how fast must you recover? (depends on VM size and data volume)
//
// HOW VM BACKUP WORKS:
//   1. Azure takes a snapshot of the VM's managed disks
//   2. The snapshot is transferred to the vault (encrypted, compressed)
//   3. Snapshots are retained according to the backup policy
//   4. To restore: create a new VM from the backup, or replace existing disks
//
//   The first backup is a FULL copy. Subsequent backups are incremental
//   (only changed blocks). This is why the first backup takes hours but
//   daily backups take minutes.
//
// BACKUP POLICY DESIGN:
//   - Daily backup at 2:00 AM (off-peak hours for Dutch clients)
//   - Retain daily backups for 30 days
//   - Retain weekly backups (every Sunday) for 12 weeks
//   - This gives you: any day in the last month, or any week in last 3 months
//
// COST:
//   ~€10/month for a single VM with 128 GB disk. Very cheap insurance.
//
// ============================================================================

// -- Parameters --------------------------------------------------------------

@description('Name of the Recovery Services Vault. Convention: rsv-{workload}-{env}')
param vaultName string

@description('Azure region. Must match the VMs being backed up.') // "Where should I create the Recovery Services Vault? This should be the same region as the VMs you plan to back up, e.g., 'westeurope' for West Europe."
param location string = resourceGroup().location

@description('Tags for cost allocation and governance.')
param tags object

// -- Recovery Services Vault -------------------------------------------------

resource vault 'Microsoft.RecoveryServices/vaults@2024-04-01' = { // "Create a Recovery Services Vault with the specified name, location, tags, and SKU. The vault will have Geo-Redundant Storage (GRS) for backup data, ensuring that backups are replicated to a paired region for disaster recovery. The vault will also have public network access enabled to allow backup and restore operations from Azure VMs."
  name: vaultName
  location: location
  tags: tags
  sku: {
    name: 'RS0'      // Standard tier — only option for Recovery Services
    tier: 'Standard'
  }
  properties: {
    // GRS = Geo-Redundant Storage: backups are replicated to a paired region
    // (West Europe → North Europe). If the entire Amsterdam datacenter burns
    // down, your backups survive in Dublin.
    // For dev/test, you'd use LRS (locally redundant) to save cost.
    publicNetworkAccess: 'Enabled'
  }
}

// -- Backup Policy -----------------------------------------------------------
//
// The policy defines WHEN to backup and HOW LONG to keep it.
// Multiple VMs can share the same policy.

resource backupPolicy 'Microsoft.RecoveryServices/vaults/backupPolicies@2024-04-01' = { // "Create a backup policy named 'policy-daily-30d' in the Recovery Services Vault. This policy will schedule daily backups at 2:00 AM UTC, retain daily backups for 30 days, and retain weekly backups (every Sunday) for 12 weeks. The policy will also have an Instant Recovery Point retention of 2 days, allowing for fast recovery from recent snapshots. The time zone for the backup schedule is set to 'W. Europe Standard Time' to align with the local time in Amsterdam."
  parent: vault
  name: 'policy-daily-30d'
  properties: {
    backupManagementType: 'AzureIaasVM'  // For Azure VMs
    // Schedule: daily at 2:00 AM UTC (3:00 AM Amsterdam time in winter)
    schedulePolicy: {
      schedulePolicyType: 'SimpleSchedulePolicy'
      scheduleRunFrequency: 'Daily'
      scheduleRunTimes: [
        '2026-01-01T02:00:00Z'  // Only the time matters, date is ignored
      ]
    }
    // Retention: how long to keep backups
    retentionPolicy: {
      retentionPolicyType: 'LongTermRetentionPolicy'
      // Keep daily backups for 30 days
      dailySchedule: {
        retentionTimes: [
          '2026-01-01T02:00:00Z'
        ]
        retentionDuration: {
          count: 30
          durationType: 'Days'
        }
      }
      // Keep weekly backup (Sunday) for 12 weeks
      weeklySchedule: {
        daysOfTheWeek: ['Sunday']
        retentionTimes: [
          '2026-01-01T02:00:00Z'
        ]
        retentionDuration: {
          count: 12
          durationType: 'Weeks'
        }
      }
    }
    // InstantRP retention: how long to keep the fast-recovery snapshot.
    // Instant recovery uses the disk snapshot directly (fast, ~minutes).
    // After this period, restore goes through the vault (slower, ~hours).
    instantRpRetentionRangeInDays: 2
    timeZone: 'W. Europe Standard Time'
  }
}

// -- Outputs -----------------------------------------------------------------

@description('Resource ID of the Recovery Services Vault.')
output vaultId string = vault.id

@description('Name of the vault.')
output vaultName string = vault.name

@description('Resource ID of the backup policy.')
output backupPolicyId string = backupPolicy.id
