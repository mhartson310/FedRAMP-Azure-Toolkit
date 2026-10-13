#Requires -Modules Microsoft.Graph.Authentication, Microsoft.Graph.Users
<#
.SYNOPSIS
    Read-only candidate inventory for periodic identity account review.
.DESCRIPTION
    Queries existing Microsoft Graph user records and classifies sign-in metadata
    for human review. DOES NOT send notifications, change users or certify AC-2.
    Unknown sign-in activity remains INSUFFICIENT_DATA and is not marked inactive.
.EXAMPLE
    Connect-MgGraph -Scopes 'User.Read.All','AuditLog.Read.All'
    ./90-day-review.ps1 -Environment NonProduction -InactivityThresholdDays 90
.NOTES
    This replaces an unsafe example that disabled accounts without verified
    independent manager approval. All actions now require a separate reviewed workflow.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Production','NonProduction','Dev')]
    [string]$Environment,
    [Parameter()]
    [ValidateRange(1,3650)]
    [int]$InactivityThresholdDays = 90,
    [Parameter()]
    [string]$OutputPath = './evidence/AC-2',
    [Parameter()]
    [switch]$SendNotifications,
    [Parameter()]
    [switch]$WhatIf
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'AccountReviewPolicy.ps1')

if ($SendNotifications) {
    throw 'Manager notifications are not implemented or validated. Export the candidates for an independently approved review workflow.'
}
if (-not (Get-MgContext)) {
    throw 'No Microsoft Graph session. Connect explicitly with read-only scopes before running.'
}
$now = [DateTimeOffset]::UtcNow
$users = @(Get-MgUser -All -Property @('id','userPrincipalName','accountEnabled','signInActivity') -ErrorAction Stop)

$results = @(
    foreach ($user in $users) {
        Get-AccountActivityReviewSignal -User $user -ObservedUtc $now -ThresholdDays $InactivityThresholdDays
    }
)
New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
$stamp = $now.ToString('yyyyMMddTHHmmssZ')
$file = Join-Path $OutputPath "account-review-candidates-$stamp.csv"
if ($results.Count -gt 0) {
    $results | Export-Csv -Path $file -NoTypeInformation -Encoding UTF8
}
$summary = [ordered]@{
    CollectedUtc = $now.ToString('o')
    Environment = $Environment
    Source = 'Microsoft Graph user metadata'
    RecordsReturned = $users.Count
    ReviewCandidates = @($results | Where-Object ReviewStatus -EQ 'REVIEW_CANDIDATE').Count
    UnknownActivity = @($results | Where-Object ReviewStatus -EQ 'INSUFFICIENT_DATA').Count
    NotificationsSent = 0
    AccountsModified = 0
    EvidenceStatus = 'NOT_ATTESTED'
    Note = 'Sign-in metadata alone cannot establish inactivity, manager approval, or AC-2 compliance.'
}
$summaryFile = Join-Path $OutputPath "account-review-summary-$stamp.json"
ConvertTo-Json -InputObject $summary -Depth 4 |
    Set-Content -Path $summaryFile -Encoding UTF8
Write-Host "Read-only candidate inventory complete. Returned users: $($users.Count); human-review candidates: $($summary.ReviewCandidates); missing activity evidence: $($summary.UnknownActivity)."
Write-Warning 'No manager notifications sent, no accounts disabled, and no compliance assessment performed. Protect exports as sensitive personnel data.'
