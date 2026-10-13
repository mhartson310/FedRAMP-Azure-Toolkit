#Requires -Modules Az.Accounts, Az.OperationalInsights
<#
.SYNOPSIS
    Collects limited, read-only Log Analytics workspace metadata for audit review.
.DESCRIPTION
    Does NOT validate FedRAMP compliance or prove log-source ingestion,
    immutability, retention for individual tables, or NIST AU-2 coverage.
    Requires existing Connect-AzAccount session.
.EXAMPLE
    ./collect-evidence.ps1 -ResourceGroupName "rg-lab" -WorkspaceName "law-lab"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName,
    [Parameter(Mandatory=$true)]
    [string]$WorkspaceName,
    [Parameter()]
    [string]$OutputPath = "./evidence/AU-2",
    [Parameter()]
    [string]$Month = (Get-Date -Format "yyyy-MM")
)
. (Join-Path $PSScriptRoot "AuditInventory.ps1")
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not (Get-AzContext)) {
    throw "No Azure context. Authenticate with Connect-AzAccount first."
}
if ($Month -notmatch '^\d{4}-(0[1-9]|1[0-2])$') {
    throw "Month must be yyyy-MM."
}
$workspace = Get-AzOperationalInsightsWorkspace -ResourceGroupName $ResourceGroupName -Name $WorkspaceName -ErrorAction Stop
New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null

$report = New-AuditWorkspaceInventory -Workspace $workspace -ResourceGroupName $ResourceGroupName -Month $Month -CollectedUtc ([DateTimeOffset]::UtcNow)
$filename = Join-Path $OutputPath "au2-workspace-inventory-$Month.json"
ConvertTo-Json -InputObject $report -Depth 4 |
    Set-Content -Path $filename -Encoding UTF8

Write-Host "Saved non-attesting workspace inventory: $filename"
Write-Warning "This report does not prove AU-2 event coverage, ingestion, retention compliance, or immutability."
[pscustomobject]$report
