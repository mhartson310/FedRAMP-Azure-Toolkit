$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '../control-automation/AC-2-account-management/AccountReviewPolicy.ps1')
. (Join-Path $PSScriptRoot '../control-automation/AU-2-audit-logging/AuditInventory.ps1')

function Assert-Equal {
    param([object]$Actual, [object]$Expected, [string]$Message)
    if ($Actual -ne $Expected) { throw "$Message. Expected [$Expected], found [$Actual]" }
    Write-Host "PASS: $Message"
}
$now = [DateTimeOffset]::Parse('2026-10-01T12:00:00Z')

function Test-User {
    param(
        [AllowNull()][object]$SignIn = $now.AddDays(-120),
        [bool]$Enabled = $true
    )
    [pscustomobject]@{
        Id = 'user-test'
        UserPrincipalName = 'synthetic@example.invalid'
        AccountEnabled = $Enabled
        SignInActivity = [pscustomobject]@{ LastSignInDateTime = $SignIn }
    }
}

$old = Get-AccountActivityReviewSignal -User (Test-User) -ObservedUtc $now -ThresholdDays 90
Assert-Equal $old.ReviewStatus 'REVIEW_CANDIDATE' 'Old sign-in becomes human review candidate'
Assert-Equal $old.DisableAuthorized $false 'Old sign-in never authorizes account disable'
Assert-Equal $old.ApprovalVerified $false 'No manager approval is invented'
Assert-Equal $old.ControlAssessed $false 'No compliance assertion is made'

$recent = Get-AccountActivityReviewSignal -User (Test-User -SignIn $now.AddDays(-2)) -ObservedUtc $now -ThresholdDays 90
Assert-Equal $recent.ReviewStatus 'NO_CANDIDATE_SIGNAL' 'Recent activity not flagged'

$boundary = Get-AccountActivityReviewSignal -User (Test-User -SignIn $now.AddDays(-90)) -ObservedUtc $now -ThresholdDays 90
Assert-Equal $boundary.ReviewStatus 'REVIEW_CANDIDATE' 'Exact threshold is review candidate'

$unknown = Get-AccountActivityReviewSignal -User (Test-User -SignIn $null) -ObservedUtc $now -ThresholdDays 90
Assert-Equal $unknown.ReviewStatus 'INSUFFICIENT_DATA' 'Missing activity is not proof of inactivity'

$future = Get-AccountActivityReviewSignal -User (Test-User -SignIn $now.AddDays(1)) -ObservedUtc $now -ThresholdDays 90
Assert-Equal $future.ReviewStatus 'INSUFFICIENT_DATA' 'Future timestamps are not trusted'

$disabled = Get-AccountActivityReviewSignal -User (Test-User -Enabled $false) -ObservedUtc $now -ThresholdDays 90
Assert-Equal $disabled.ReviewStatus 'ALREADY_DISABLED' 'Disabled account never placed in active-account review'

$workspace = [pscustomobject]@{
    Name = 'workspace-lab'
    ResourceId = '/subscriptions/test/resourceGroups/rg-lab/providers/Microsoft.OperationalInsights/workspaces/workspace-lab'
    RetentionInDays = 730
}
$inventory = New-AuditWorkspaceInventory -Workspace $workspace -ResourceGroupName 'rg-lab' -Month '2026-09' -CollectedUtc $now
Assert-Equal $inventory.AssessmentResult 'NOT_ASSESSED' 'High retention cannot establish FedRAMP compliance'
Assert-Equal $inventory.DataIngestionVerified $false 'Ingestion is not inferred from configuration'
Assert-Equal $inventory.ControlCoverageVerified $false 'AU-2 coverage is not inferred'
Assert-Equal $inventory.ImmutabilityVerified $false 'Immutability is not inferred'
Assert-Equal $inventory.PerTableRetentionChecked $false 'Per-table retention is not inferred'

$workspace.RetentionInDays = 30
$inventory2 = New-AuditWorkspaceInventory -Workspace $workspace -ResourceGroupName 'rg-lab' -Month '2026-09' -CollectedUtc $now
Assert-Equal $inventory2.AssessmentResult 'NOT_ASSESSED' 'Low retention also remains unassessed'

$invalidMonthRejected = $false
try { $null = New-AuditWorkspaceInventory -Workspace $workspace -ResourceGroupName 'rg-lab' -Month '2026-13' -CollectedUtc $now }
catch { $invalidMonthRejected = $true }
Assert-Equal $invalidMonthRejected $true 'Invalid calendar month rejected'

Write-Host 'PASS: All synthetic FedRAMP review/inventory tests completed without Graph or Azure connections.'
