<#
.SYNOPSIS
    Audits all NSG rules across resource groups and exports a CSV compliance report.

.DESCRIPTION
    This script is a core operational tool for AZL's managed services team.
    It retrieves every Network Security Group in the target resource groups, lists
    all security rules (both custom and default), and exports a flat CSV report.

    WHY THIS EXISTS:
    In a managed services environment, NSG rules change over time — developers
    request new ports, incidents require temporary rules, and before you know it
    you have 200 rules across 15 NSGs and nobody knows which ones are still needed.

    This audit script provides a single source of truth. Run it nightly via the
    compliance pipeline, review the CSV, and catch:
    - Rules allowing traffic from "Any" source (security risk)
    - Rules on unexpected ports (shadow IT)
    - Duplicate or conflicting rules (misconfiguration)
    - Rules with no clear naming convention (accountability gap)

.PARAMETER ResourceGroupPattern
    Wildcard pattern to match resource group names. Default: "rg-*-weu"
    This targets all our landing zone RGs in West Europe.

.PARAMETER OutputPath
    Path for the CSV output file. Default: ./reports/nsg-audit-{date}.csv

.EXAMPLE
    # Audit all NSGs in landing zone resource groups
    .\Invoke-NsgAudit.ps1

    # Audit only hub resource group
    .\Invoke-NsgAudit.ps1 -ResourceGroupPattern "rg-hub-*"

    # Custom output path
    .\Invoke-NsgAudit.ps1 -OutputPath "C:\reports\audit.csv"
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$ResourceGroupPattern = "rg-*-weu",

    [Parameter()]
    [string]$OutputPath = "./reports/nsg-audit-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"
)

# Ensure the output directory exists
$outputDir = Split-Path -Parent $OutputPath
if ($outputDir -and -not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    Write-Verbose "Created output directory: $outputDir"
}

Write-Host "=== NSG Audit Report ===" -ForegroundColor Cyan
Write-Host "Resource Group Pattern: $ResourceGroupPattern"
Write-Host "Output: $OutputPath"
Write-Host ""

# Get all NSGs matching the resource group pattern.
# We filter by RG name rather than getting all NSGs in the subscription
# to avoid auditing NSGs we don't manage (other teams, other clients).
$nsgs = Get-AzNetworkSecurityGroup | Where-Object {
    $_.ResourceGroupName -like $ResourceGroupPattern
}

if ($nsgs.Count -eq 0) {
    Write-Warning "No NSGs found matching pattern '$ResourceGroupPattern'"
    exit 0
}

Write-Host "Found $($nsgs.Count) NSGs to audit" -ForegroundColor Green

# Build the report: one row per rule per NSG.
# This flat structure makes it easy to filter in Excel: sort by Access=Allow,
# filter by SourceAddressPrefix=*, and you immediately see "allow from anywhere" rules.
$report = foreach ($nsg in $nsgs) {
    Write-Host "  Auditing: $($nsg.Name) ($($nsg.SecurityRules.Count) custom rules)"

    foreach ($rule in $nsg.SecurityRules) {
        [PSCustomObject]@{
            NSGName            = $nsg.Name
            ResourceGroup      = $nsg.ResourceGroupName
            RuleName           = $rule.Name
            Priority           = $rule.Priority
            Direction          = $rule.Direction
            Access             = $rule.Access
            Protocol           = $rule.Protocol
            SourceAddress      = ($rule.SourceAddressPrefix -join ',')
            SourcePortRange    = ($rule.SourcePortRange -join ',')
            DestinationAddress = ($rule.DestinationAddressPrefix -join ',')
            DestinationPort    = ($rule.DestinationPortRange -join ',')
            RuleType           = 'Custom'
        }
    }

    # Also audit default rules — they're usually fine but sometimes Azure
    # changes defaults, and it's good to have them in the report.
    foreach ($rule in $nsg.DefaultSecurityRules) {
        [PSCustomObject]@{
            NSGName            = $nsg.Name
            ResourceGroup      = $nsg.ResourceGroupName
            RuleName           = $rule.Name
            Priority           = $rule.Priority
            Direction          = $rule.Direction
            Access             = $rule.Access
            Protocol           = $rule.Protocol
            SourceAddress      = ($rule.SourceAddressPrefix -join ',')
            SourcePortRange    = ($rule.SourcePortRange -join ',')
            DestinationAddress = ($rule.DestinationAddressPrefix -join ',')
            DestinationPort    = ($rule.DestinationPortRange -join ',')
            RuleType           = 'Default'
        }
    }
}

# Export and summarize
$report | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8

# Quick risk summary — flag rules that allow traffic from "Any" source
$riskyRules = $report | Where-Object {
    $_.Access -eq 'Allow' -and
    $_.SourceAddress -eq '*' -and
    $_.RuleType -eq 'Custom'
}

Write-Host ""
Write-Host "=== Audit Summary ===" -ForegroundColor Cyan
Write-Host "Total NSGs audited: $($nsgs.Count)"
Write-Host "Total rules found: $($report.Count)"
Write-Host "  Custom rules: $(($report | Where-Object { $_.RuleType -eq 'Custom' }).Count)"
Write-Host "  Default rules: $(($report | Where-Object { $_.RuleType -eq 'Default' }).Count)"

if ($riskyRules.Count -gt 0) {
    Write-Host ""
    Write-Host "WARNING: $($riskyRules.Count) rules allow traffic from ANY source:" -ForegroundColor Yellow
    foreach ($r in $riskyRules) {
        Write-Host "  - $($r.NSGName) / $($r.RuleName): $($r.Protocol) port $($r.DestinationPort)" -ForegroundColor Yellow
    }
} else {
    Write-Host "No rules allowing traffic from 'Any' source found." -ForegroundColor Green
}

Write-Host ""
Write-Host "Report exported to: $OutputPath" -ForegroundColor Green
