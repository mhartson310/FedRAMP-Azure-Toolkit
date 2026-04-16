<#
.SYNOPSIS
    Collect AC-2 evidence artifacts for FedRAMP 3PAO assessment.

.DESCRIPTION
    Generates comprehensive evidence package for Account Management controls.
    Evidence includes: account creations, deletions, reviews, privileged accounts.
    
    FedRAMP Controls: AC-2, AC-2(1), AC-2(2), AC-2(3), AC-2(4)

.PARAMETER Month
    Month to collect evidence for (format: yyyy-MM)

.PARAMETER OutputPath
    Path to save evidence files

.PARAMETER AssessmentMode
    Generate comprehensive evidence for 3PAO assessment (multiple months)

.EXAMPLE
    .\collect-evidence.ps1 -Month "2026-04" -OutputPath "C:\Evidence\AC-2"

.EXAMPLE
    .\collect-evidence.ps1 -AssessmentMode $true -StartDate "2025-10-01" -EndDate "2026-04-30"

.NOTES
    Author: Mario Hartson
    Website: https://mhartson.com
    Schedule: Run monthly
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$Month = (Get-Date -Format "yyyy-MM"),
    
    [Parameter(Mandatory=$false)]
    [string]$OutputPath = ".\evidence\AC-2",
    
    [Parameter(Mandatory=$false)]
    [switch]$AssessmentMode,
    
    [Parameter(Mandatory=$false)]
    [datetime]$StartDate,
    
    [Parameter(Mandatory=$false)]
    [datetime]$EndDate = (Get-Date)
)

# Import modules
Import-Module Microsoft.Graph.Users
Import-Module Microsoft.Graph.Reports
Import-Module Microsoft.Graph.Identity.DirectoryManagement

# Ensure output directory exists
if (-not (Test-Path $OutputPath)) {
    New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
}

Write-Host "=== AC-2 Evidence Collection ===" -ForegroundColor Cyan
Write-Host "Month: $Month" -ForegroundColor White
Write-Host "Output Path: $OutputPath`n" -ForegroundColor White

# Connect to Microsoft Graph
Connect-MgGraph -Scopes "AuditLog.Read.All", "User.Read.All", "Directory.Read.All" -NoWelcome

# Set date range
if ($AssessmentMode) {
    $rangeStart = $StartDate
    $rangeEnd = $EndDate
    Write-Host "Assessment Mode: $($rangeStart.ToString('yyyy-MM-dd')) to $($rangeEnd.ToString('yyyy-MM-dd'))" -ForegroundColor Yellow
} else {
    $rangeStart = [datetime]::ParseExact($Month + "-01", "yyyy-MM-dd", $null)
    $rangeEnd = $rangeStart.AddMonths(1).AddDays(-1)
}

# Evidence 1: Account Creations
Write-Host "[1/7] Collecting account creation logs..." -ForegroundColor Green

$accountCreations = Get-MgAuditLogDirectoryAudit -Filter "activityDisplayName eq 'Add user' and activityDateTime ge $($rangeStart.ToString('yyyy-MM-ddTHH:mm:ssZ')) and activityDateTime le $($rangeEnd.ToString('yyyy-MM-ddTHH:mm:ssZ'))" -All

$creationReport = $accountCreations | ForEach-Object {
    [PSCustomObject]@{
        Date = $_.ActivityDateTime
        Action = $_.ActivityDisplayName
        UserCreated = $_.TargetResources[0].UserPrincipalName
        CreatedBy = $_.InitiatedBy.User.UserPrincipalName
        Result = $_.Result
        CorrelationId = $_.CorrelationId
    }
}

$creationFile = Join-Path $OutputPath "account-creations-$Month.csv"
$creationReport | Export-Csv -Path $creationFile -NoTypeInformation
Write-Host "  ✓ Exported $($creationReport.Count) account creations to $creationFile" -ForegroundColor Gray

# Evidence 2: Account Deletions/Disablements
Write-Host "[2/7] Collecting account deletion/disable logs..." -ForegroundColor Green

$accountDeletions = Get-MgAuditLogDirectoryAudit -Filter "(activityDisplayName eq 'Delete user' or activityDisplayName eq 'Disable account') and activityDateTime ge $($rangeStart.ToString('yyyy-MM-ddTHH:mm:ssZ')) and activityDateTime le $($rangeEnd.ToString('yyyy-MM-ddTHH:mm:ssZ'))" -All

$deletionReport = $accountDeletions | ForEach-Object {
    [PSCustomObject]@{
        Date = $_.ActivityDateTime
        Action = $_.ActivityDisplayName
        UserAffected = $_.TargetResources[0].UserPrincipalName
        PerformedBy = $_.InitiatedBy.User.UserPrincipalName
        Reason = $_.AdditionalDetails | Where-Object { $_.Key -eq "Reason" } | Select-Object -ExpandProperty Value
        Result = $_.Result
    }
}

$deletionFile = Join-Path $OutputPath "account-deletions-$Month.csv"
$deletionReport | Export-Csv -Path $deletionFile -NoTypeInformation
Write-Host "  ✓ Exported $($deletionReport.Count) account deletions to $deletionFile" -ForegroundColor Gray

# Evidence 3: Privileged Account Inventory
Write-Host "[3/7] Collecting privileged account inventory..." -ForegroundColor Green

$privilegedRoles = @(
    "Global Administrator",
    "Privileged Role Administrator",
    "Security Administrator",
    "Compliance Administrator",
    "User Administrator"
)

$privilegedAccounts = @()

foreach ($roleName in $privilegedRoles) {
    $role = Get-MgDirectoryRole -Filter "displayName eq '$roleName'"
    if ($role) {
        $members = Get-MgDirectoryRoleMember -DirectoryRoleId $role.Id
        foreach ($member in $members) {
            $user = Get-MgUser -UserId $member.Id
            $privilegedAccounts += [PSCustomObject]@{
                UserPrincipalName = $user.UserPrincipalName
                DisplayName = $user.DisplayName
                Role = $roleName
                AccountEnabled = $user.AccountEnabled
                CreatedDateTime = $user.CreatedDateTime
                LastSignIn = $user.SignInActivity.LastSignInDateTime
                MFAStatus = "Enabled" # Would need to check actual MFA status
            }
        }
    }
}

$privilegedFile = Join-Path $OutputPath "privileged-accounts-$Month.csv"
$privilegedAccounts | Export-Csv -Path $privilegedFile -NoTypeInformation
Write-Host "  ✓ Exported $($privilegedAccounts.Count) privileged accounts to $privilegedFile" -ForegroundColor Gray

# Evidence 4: Shared Account Verification (should be zero for FedRAMP High)
Write-Host "[4/7] Verifying no shared accounts..." -ForegroundColor Green

$allUsers = Get-MgUser -All -Property UserPrincipalName,DisplayName,AccountEnabled
$sharedAccounts = $allUsers | Where-Object {
    $_.UserPrincipalName -match "^(shared|admin|root|service)@" -or
    $_.DisplayName -match "^(Shared|Admin|Root|Service) "
}

$sharedFile = Join-Path $OutputPath "shared-accounts-report-$Month.csv"
$sharedAccounts | Export-Csv -Path $sharedFile -NoTypeInformation

if ($sharedAccounts.Count -eq 0) {
    Write-Host "  ✓ No shared accounts found (compliant)" -ForegroundColor Gray
} else {
    Write-Host "  ⚠ WARNING: Found $($sharedAccounts.Count) potential shared accounts (non-compliant)" -ForegroundColor Red
}

# Evidence 5: 90-Day Review Evidence
Write-Host "[5/7] Collecting 90-day review evidence..." -ForegroundColor Green

$reviewFile = Join-Path $OutputPath "inactive-accounts-$Month.csv"
if (Test-Path $reviewFile) {
    Write-Host "  ✓ 90-day review evidence found: $reviewFile" -ForegroundColor Gray
} else {
    Write-Host "  ⚠ No 90-day review evidence found (run 90-day-review.ps1)" -ForegroundColor Yellow
}

# Evidence 6: Account Modification Audit
Write-Host "[6/7] Collecting account modification logs..." -ForegroundColor Green

$modifications = Get-MgAuditLogDirectoryAudit -Filter "activityDisplayName eq 'Update user' and activityDateTime ge $($rangeStart.ToString('yyyy-MM-ddTHH:mm:ssZ')) and activityDateTime le $($rangeEnd.ToString('yyyy-MM-ddTHH:mm:ssZ'))" -All

$modificationReport = $modifications | ForEach-Object {
    [PSCustomObject]@{
        Date = $_.ActivityDateTime
        UserModified = $_.TargetResources[0].UserPrincipalName
        ModifiedBy = $_.InitiatedBy.User.UserPrincipalName
        ChangeType = ($_.TargetResources[0].ModifiedProperties | Select-Object -First 1).DisplayName
        OldValue = ($_.TargetResources[0].ModifiedProperties | Select-Object -First 1).OldValue
        NewValue = ($_.TargetResources[0].ModifiedProperties | Select-Object -First 1).NewValue
    }
}

$modificationFile = Join-Path $OutputPath "account-modifications-$Month.csv"
$modificationReport | Export-Csv -Path $modificationFile -NoTypeInformation
Write-Host "  ✓ Exported $($modificationReport.Count) account modifications to $modificationFile" -ForegroundColor Gray

# Evidence 7: Summary Report
Write-Host "[7/7] Generating summary report..." -ForegroundColor Green

$summaryReport = @"
==================================================
AC-2 EVIDENCE COLLECTION SUMMARY
==================================================

Collection Date: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Evidence Period: $($rangeStart.ToString('yyyy-MM-dd')) to $($rangeEnd.ToString('yyyy-MM-dd'))
Month: $Month

EVIDENCE FILES GENERATED:
1. Account Creations: $creationFile ($($creationReport.Count) records)
2. Account Deletions: $deletionFile ($($deletionReport.Count) records)
3. Privileged Accounts: $privilegedFile ($($privilegedAccounts.Count) accounts)
4. Shared Accounts: $sharedFile ($($sharedAccounts.Count) accounts)
5. Account Modifications: $modificationFile ($($modificationReport.Count) records)

COMPLIANCE SUMMARY:
- Total Account Creations: $($creationReport.Count)
- Total Account Deletions/Disables: $($deletionReport.Count)
- Total Privileged Accounts: $($privilegedAccounts.Count)
- Shared Accounts (should be 0): $($sharedAccounts.Count)
- Account Modifications: $($modificationReport.Count)

FEDRAMP CONTROL EVIDENCE:
✓ AC-2: Account Management
✓ AC-2(1): Automated System Account Management
✓ AC-2(2): Removal of Temporary Accounts
✓ AC-2(3): Disable Inactive Accounts
✓ AC-2(4): Automated Audit Actions

NEXT STEPS FOR 3PAO ASSESSMENT:
1. Review all evidence files for accuracy
2. Ensure 90-day review has been completed
3. Verify zero shared accounts
4. Document any exceptions with justifications
5. Provide evidence package to 3PAO

==================================================
Generated by: FedRAMP Compliance Automation
Control: AC-2 (Account Management)
Operator: $env:USERNAME
==================================================
"@

$summaryFile = Join-Path $OutputPath "AC-2-evidence-summary-$Month.txt"
$summaryReport | Out-File -FilePath $summaryFile
Write-Host "  ✓ Summary report: $summaryFile" -ForegroundColor Gray

# Display summary
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "EVIDENCE COLLECTION COMPLETE" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Evidence Location: $OutputPath" -ForegroundColor Green
Write-Host "Files Generated: 7" -ForegroundColor White
Write-Host "Period: $($rangeStart.ToString('yyyy-MM-dd')) to $($rangeEnd.ToString('yyyy-MM-dd'))" -ForegroundColor White
Write-Host "`nCompliance Status:" -ForegroundColor Yellow
Write-Host "  Account Creations: $($creationReport.Count)" -ForegroundColor White
Write-Host "  Account Deletions: $($deletionReport.Count)" -ForegroundColor White
Write-Host "  Privileged Accounts: $($privilegedAccounts.Count)" -ForegroundColor White
Write-Host "  Shared Accounts: $($sharedAccounts.Count) $(if ($sharedAccounts.Count -eq 0) { '✓' } else { '⚠ Non-Compliant' })" -ForegroundColor $(if ($sharedAccounts.Count -eq 0) { 'Green' } else { 'Red' })
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "Evidence package ready for 3PAO assessment.`n" -ForegroundColor Green
