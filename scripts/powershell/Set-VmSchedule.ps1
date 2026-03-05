<#
.SYNOPSIS
    Start or stop VMs based on tags. Used for dev/test cost optimization.

.DESCRIPTION
    This script is an InSpark cost optimization pattern. Dev/test VMs don't need
    to run 24/7. By tagging VMs with AutoShutdown=true and scheduling this script
    to run at 7 PM (stop) and 8 AM (start), clients save ~70% on compute costs
    for non-production workloads.

    HOW IT WORKS:
    1. Queries all VMs in resource groups matching the pattern
    2. Filters VMs that have the specified tag (default: AutoShutdown=true)
    3. Starts or stops them based on the -Action parameter
    4. Uses -NoWait for parallel execution (doesn't wait for each VM to finish)

    SCHEDULING:
    This script is designed to be called from:
    - Azure DevOps scheduled pipeline (see pipelines/scheduled/)
    - Azure Automation Account runbook
    - Cron job on a management VM

    SAFETY:
    - Only targets VMs with the opt-in tag. VMs without the tag are untouched.
    - Uses -Force on Stop-AzVM to skip the confirmation prompt.
    - Uses -NoWait so the script completes quickly (VMs stop in background).

.PARAMETER Action
    'Start' or 'Stop'. No default — you must explicitly choose.

.PARAMETER TagName
    The tag key to look for. Default: 'AutoShutdown'

.PARAMETER TagValue
    The tag value to match. Default: 'true'

.PARAMETER ResourceGroupPattern
    Wildcard pattern for target resource groups. Default: 'rg-spoke-dev-*'
    Only targets dev by default — you don't want to accidentally stop production VMs.

.EXAMPLE
    # Stop all dev VMs tagged for auto-shutdown
    .\Set-VmSchedule.ps1 -Action Stop

    # Start them back up in the morning
    .\Set-VmSchedule.ps1 -Action Start

    # Target a specific resource group
    .\Set-VmSchedule.ps1 -Action Stop -ResourceGroupPattern "rg-spoke-dev-weu"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Start', 'Stop')]
    [string]$Action,

    [Parameter()]
    [string]$TagName = "AutoShutdown",

    [Parameter()]
    [string]$TagValue = "true",

    [Parameter()]
    [string]$ResourceGroupPattern = "rg-spoke-dev-*"
)

Write-Host "=== VM Schedule: $Action ===" -ForegroundColor Cyan
Write-Host "Tag filter: $TagName=$TagValue"
Write-Host "Resource group pattern: $ResourceGroupPattern"
Write-Host ""

# Get VMs with their current power state.
# -Status flag retrieves power state (Running, Deallocated, etc.)
# Without -Status, you only get the VM config — not whether it's running.
$vms = Get-AzVM -Status | Where-Object {
    $_.ResourceGroupName -like $ResourceGroupPattern -and
    $_.Tags[$TagName] -eq $TagValue
}

if ($vms.Count -eq 0) {
    Write-Host "No VMs found matching criteria." -ForegroundColor Yellow
    exit 0
}

Write-Host "Found $($vms.Count) VMs matching criteria:" -ForegroundColor Green

$actioned = 0
$skipped = 0

foreach ($vm in $vms) {
    # PowerState values: 'VM running', 'VM deallocated', 'VM stopped', 'VM starting', etc.
    $powerState = $vm.PowerState

    if ($Action -eq 'Stop' -and $powerState -eq 'VM running') {
        Write-Host "  Stopping: $($vm.Name) (was: $powerState)" -ForegroundColor Yellow
        # -Force: skip "Are you sure?" prompt
        # -NoWait: don't block — fire and forget. The VM stops in the background.
        # This is important when you have 50 dev VMs — you don't want to wait
        # 2 minutes per VM sequentially.
        Stop-AzVM -Name $vm.Name -ResourceGroupName $vm.ResourceGroupName -Force -NoWait
        $actioned++
    }
    elseif ($Action -eq 'Start' -and $powerState -ne 'VM running') {
        Write-Host "  Starting: $($vm.Name) (was: $powerState)" -ForegroundColor Green
        Start-AzVM -Name $vm.Name -ResourceGroupName $vm.ResourceGroupName -NoWait
        $actioned++
    }
    else {
        Write-Host "  Skipped:  $($vm.Name) (already $powerState)" -ForegroundColor DarkGray
        $skipped++
    }
}

Write-Host ""
Write-Host "=== Summary ===" -ForegroundColor Cyan
Write-Host "Action: $Action"
Write-Host "VMs $($Action.ToLower())ed: $actioned"
Write-Host "VMs skipped (already in desired state): $skipped"
