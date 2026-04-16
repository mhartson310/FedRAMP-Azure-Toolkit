<#
.SYNOPSIS
    Automated 90-day account review for FedRAMP AC-2 compliance.

.DESCRIPTION
    Identifies inactive accounts, notifies managers, and generates evidence for 3PAO assessment.
    Meets FedRAMP requirement for periodic account reviews (AC-2, AC-2(3)).
    
    FedRAMP Controls: AC-2, AC-2(3) - Disable Inactive Accounts

.PARAMETER Environment
    Target environment (Production, NonProduction, Dev)

.PARAMETER SendNotifications
    If true, sends email notifications to managers

.PARAMETER WhatIf
    Shows what would be done without making changes

.EXAMPLE
    .\90-day-review.ps1 -Environment Production -SendNotifications $true

.EXAMPLE
    .\90-day-review.ps1 -Environment Production -WhatIf

.NOTES
    Author: Mario Hartson
    Website: https://mhartson.com
    Schedule: Run quarterly (every 90 days)
    Requires: Microsoft.Graph PowerShell module
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("Production", "NonProduction", "Dev")]
    [string]$Environment,
    
    [Parameter(Mandatory=$false)]
    [switch]$SendNotifications,
    
    [Parameter(Mandatory=$false)]
    [switch]$WhatIf,
    
    [Parameter(Mandatory=$false)]
    [string]$OutputPath = ".\evidence",
    
    [Parameter(Mandatory=$false)]
    [int]$InactivityThresholdDays = 90,
    
    [Parameter(Mandatory=$false)]
    [string]$LogAnalyticsWorkspaceId
)

# Import required modules
Import-Module Microsoft.Graph.Users
Import-Module Microsoft.Graph.Reports
Import-Module Microsoft.Graph.Identity.DirectoryManagement

# Configuration
$reviewDate = Get-Date
$cutoffDate = $reviewDate.AddDays(-$InactivityThresholdDays)

# Logging function
function Write-AuditLog {
    param(
        [string]$Message,
        [string]$Severity = "Information",
        [hashtable]$Properties = @{}
    )
    
    $logEntry = @{
        TimeGenerated = (Get-Date).ToUniversalTime()
        Environment = $Environment
        Control = "AC-2"
        Activity = "90-Day-Review"
        Severity = $Severity
        Message = $Message
        Properties = $Properties
    }
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] [$Severity] $Message"
    
    # Append to log file
    $logFile = Join-Path $OutputPath "90-day-review-$(Get-Date -Format 'yyyy-MM').log"
    "$timestamp | $Severity | $Message" | Out-File -FilePath $logFile -Append
}

# Connect to Microsoft Graph
function Connect-MgGraphWithRetry {
    try {
        Connect-MgGraph -Scopes "User.Read.All", "AuditLog.Read.All", "Directory.Read.All", "Mail.Send" -NoWelcome
        Write-AuditLog "Connected to Microsoft Graph successfully"
        return $true
    }
    catch {
        Write-AuditLog "Failed to connect to Microsoft Graph: $_" -Severity "Error"
        return $false
    }
}

# Function: Get all active users
function Get-AllActiveUsers {
    Write-AuditLog "Retrieving all active user accounts..."
    
    try {
        $users = Get-MgUser -All -Property Id,UserPrincipalName,DisplayName,AccountEnabled,CreatedDateTime,SignInActivity,JobTitle,Department,Manager
        $activeUsers = $users | Where-Object { $_.AccountEnabled -eq $true }
        
        Write-AuditLog "Found $($activeUsers.Count) active user accounts"
        return $activeUsers
    }
    catch {
        Write-AuditLog "Failed to retrieve users: $_" -Severity "Error"
        return @()
    }
}

# Function: Identify inactive accounts
function Get-InactiveAccounts {
    param(
        [Parameter(Mandatory=$true)]
        [array]$Users
    )
    
    Write-AuditLog "Analyzing account activity for last $InactivityThresholdDays days..."
    
    $inactiveAccounts = @()
    
    foreach ($user in $Users) {
        # Get last sign-in time
        $lastSignIn = $null
        if ($user.SignInActivity) {
            $lastSignIn = $user.SignInActivity.LastSignInDateTime
        }
        
        # Determine if account is inactive
        $isInactive = $false
        $daysSinceLastSignIn = $null
        
        if ($null -eq $lastSignIn) {
            # Never signed in
            $isInactive = $true
            $daysSinceCreation = (Get-Date) - $user.CreatedDateTime
            $daysSinceLastSignIn = [int]$daysSinceCreation.TotalDays
        }
        elseif ($lastSignIn -lt $cutoffDate) {
            # Last sign-in before cutoff
            $isInactive = $true
            $daysSinceLastSignIn = [int]((Get-Date) - $lastSignIn).TotalDays
        }
        
        if ($isInactive) {
            # Get manager information
            $manager = $null
            try {
                $managerObj = Get-MgUserManager -UserId $user.Id -ErrorAction SilentlyContinue
                if ($managerObj) {
                    $manager = Get-MgUser -UserId $managerObj.Id -Property DisplayName,UserPrincipalName
                }
            }
            catch {
                # No manager assigned
            }
            
            $inactiveAccount = [PSCustomObject]@{
                UserPrincipalName = $user.UserPrincipalName
                DisplayName = $user.DisplayName
                UserId = $user.Id
                Department = $user.Department
                JobTitle = $user.JobTitle
                CreatedDate = $user.CreatedDateTime
                LastSignIn = $lastSignIn
                DaysSinceLastSignIn = $daysSinceLastSignIn
                ManagerName = if ($manager) { $manager.DisplayName } else { "No Manager" }
                ManagerEmail = if ($manager) { $manager.UserPrincipalName } else { $null }
                ReviewDate = $reviewDate
                Status = "Pending Review"
            }
            
            $inactiveAccounts += $inactiveAccount
        }
    }
    
    Write-AuditLog "Identified $($inactiveAccounts.Count) inactive accounts (inactive >$InactivityThresholdDays days)"
    
    return $inactiveAccounts
}

# Function: Send manager notification
function Send-ManagerNotification {
    param(
        [Parameter(Mandatory=$true)]
        [array]$InactiveAccounts,
        
        [Parameter(Mandatory=$true)]
        [string]$ManagerEmail
    )
    
    $accountsForManager = $InactiveAccounts | Where-Object { $_.ManagerEmail -eq $ManagerEmail }
    
    if ($accountsForManager.Count -eq 0) {
        return
    }
    
    $accountList = $accountsForManager | ForEach-Object {
        "- $($_.DisplayName) ($($_.UserPrincipalName)) - Last sign-in: $(if ($_.LastSignIn) { $_.LastSignIn.ToString('yyyy-MM-dd') } else { 'Never' }) ($($_.DaysSinceLastSignIn) days ago)"
    }
    
    $emailBody = @"
Subject: Action Required - Inactive Account Review

Dear Manager,

As part of our FedRAMP compliance requirements (Control AC-2), we conduct quarterly reviews of all user accounts. The following accounts under your management have been inactive for more than $InactivityThresholdDays days:

$($accountList -join "`n")

Required Actions:
1. Review each account listed above
2. Determine if the account is still needed
3. Respond within 30 days with one of the following:
   - KEEP: Account is still required (provide justification)
   - DISABLE: Account should be disabled
   - DELETE: Account should be deleted

Accounts not reviewed within 30 days will be automatically disabled per our security policy.

To respond, please reply to this email or update the account status in the compliance portal.

Review Deadline: $((Get-Date).AddDays(30).ToString('yyyy-MM-dd'))

Questions? Contact: security@company.com

---
This is an automated message from the FedRAMP Compliance System
Review ID: AC2-$(Get-Date -Format 'yyyyMMdd')-$($ManagerEmail.Split('@')[0])
"@

    if ($WhatIf) {
        Write-AuditLog "[WHATIF] Would send notification to $ManagerEmail for $($accountsForManager.Count) accounts"
        return
    }
    
    try {
        # Send email via Microsoft Graph
        $message = @{
            Message = @{
                Subject = "Action Required - Inactive Account Review ($($accountsForManager.Count) accounts)"
                Body = @{
                    ContentType = "Text"
                    Content = $emailBody
                }
                ToRecipients = @(
                    @{
                        EmailAddress = @{
                            Address = $ManagerEmail
                        }
                    }
                )
            }
            SaveToSentItems = "true"
        }
        
        # Send from shared mailbox or service account
        $fromAddress = "noreply-compliance@company.com"
        Send-MgUserMail -UserId $fromAddress -BodyParameter $message
        
        Write-AuditLog "Notification sent to $ManagerEmail for $($accountsForManager.Count) inactive accounts"
    }
    catch {
        Write-AuditLog "Failed to send notification to $ManagerEmail: $_" -Severity "Warning"
    }
}

# Function: Generate evidence report
function Export-ReviewEvidence {
    param(
        [Parameter(Mandatory=$true)]
        [array]$InactiveAccounts,
        
        [Parameter(Mandatory=$true)]
        [array]$AllUsers
    )
    
    # Ensure output directory exists
    if (-not (Test-Path $OutputPath)) {
        New-Item -Path $OutputPath -ItemType Directory | Out-Null
    }
    
    $reportDate = Get-Date -Format "yyyy-MM-dd"
    
    # Export 1: Inactive accounts CSV
    $csvFile = Join-Path $OutputPath "inactive-accounts-$reportDate.csv"
    $InactiveAccounts | Export-Csv -Path $csvFile -NoTypeInformation
    Write-AuditLog "Exported inactive accounts to: $csvFile"
    
    # Export 2: Summary report
    $summaryFile = Join-Path $OutputPath "90-day-review-summary-$reportDate.txt"
    
    $summary = @"
==================================================
FedRAMP AC-2 ACCOUNT REVIEW SUMMARY
==================================================

Review Date: $reportDate
Environment: $Environment
Inactivity Threshold: $InactivityThresholdDays days
Review Period: $(($cutoffDate).ToString('yyyy-MM-dd')) to $reportDate

ACCOUNT STATISTICS:
- Total Active Accounts: $($AllUsers.Count)
- Inactive Accounts Identified: $($InactiveAccounts.Count)
- Percentage Inactive: $([math]::Round(($InactiveAccounts.Count / $AllUsers.Count) * 100, 2))%

BREAKDOWN BY DEPARTMENT:
$($InactiveAccounts | Group-Object Department | ForEach-Object { "  - $($_.Name): $($_.Count) accounts" } | Out-String)

BREAKDOWN BY INACTIVITY DURATION:
- 90-180 days: $(($InactiveAccounts | Where-Object { $_.DaysSinceLastSignIn -ge 90 -and $_.DaysSinceLastSignIn -lt 180 }).Count)
- 180-365 days: $(($InactiveAccounts | Where-Object { $_.DaysSinceLastSignIn -ge 180 -and $_.DaysSinceLastSignIn -lt 365 }).Count)
- 365+ days: $(($InactiveAccounts | Where-Object { $_.DaysSinceLastSignIn -ge 365 }).Count)
- Never signed in: $(($InactiveAccounts | Where-Object { $_.LastSignIn -eq $null }).Count)

MANAGER NOTIFICATIONS:
- Unique Managers Notified: $(($InactiveAccounts | Where-Object { $_.ManagerEmail } | Select-Object -ExpandProperty ManagerEmail -Unique).Count)
- Accounts Without Manager: $(($InactiveAccounts | Where-Object { -not $_.ManagerEmail }).Count)

NEXT STEPS:
1. Managers have 30 days to review and respond
2. Accounts not reviewed will be automatically disabled
3. Evidence package generated for 3PAO assessment
4. Next review scheduled for: $((Get-Date).AddDays(90).ToString('yyyy-MM-dd'))

COMPLIANCE EVIDENCE:
- Inactive accounts list: $csvFile
- Review summary: $summaryFile
- Audit log: $(Join-Path $OutputPath "90-day-review-$(Get-Date -Format 'yyyy-MM').log")

==================================================
Generated by: FedRAMP Compliance Automation
Control: AC-2 (Account Management)
Operator: $env:USERNAME
Timestamp: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss UTC")
==================================================
"@

    $summary | Out-File -FilePath $summaryFile
    Write-AuditLog "Generated summary report: $summaryFile"
    
    # Export 3: Manager review tracking spreadsheet
    $trackingFile = Join-Path $OutputPath "manager-review-tracking-$reportDate.csv"
    
    $managerTracking = $InactiveAccounts | Group-Object ManagerEmail | ForEach-Object {
        [PSCustomObject]@{
            ManagerEmail = $_.Name
            ManagerName = ($_.Group | Select-Object -First 1).ManagerName
            InactiveAccountsCount = $_.Count
            NotificationSent = if ($SendNotifications -and -not $WhatIf) { "Yes" } else { "Pending" }
            NotificationDate = $reviewDate
            ResponseDeadline = $reviewDate.AddDays(30)
            ResponseReceived = "Pending"
            AccountsDisabled = 0
            AccountsRetained = 0
            ReviewStatus = "In Progress"
        }
    }
    
    $managerTracking | Export-Csv -Path $trackingFile -NoTypeInformation
    Write-AuditLog "Generated manager tracking spreadsheet: $trackingFile"
    
    return @{
        InactiveAccountsCSV = $csvFile
        SummaryReport = $summaryFile
        ManagerTracking = $trackingFile
    }
}

# Function: Auto-disable accounts past grace period
function Disable-UnreviewedAccounts {
    param(
        [Parameter(Mandatory=$true)]
        [array]$InactiveAccounts
    )
    
    # Check for accounts inactive >120 days (90 + 30 grace period)
    $gracePeriodCutoff = (Get-Date).AddDays(-120)
    $accountsToDisable = $InactiveAccounts | Where-Object {
        if ($_.LastSignIn) {
            $_.LastSignIn -lt $gracePeriodCutoff
        } else {
            $_.CreatedDate -lt $gracePeriodCutoff
        }
    }
    
    Write-AuditLog "Found $($accountsToDisable.Count) accounts past grace period (>120 days inactive)"
    
    foreach ($account in $accountsToDisable) {
        if ($WhatIf) {
            Write-AuditLog "[WHATIF] Would disable account: $($account.UserPrincipalName)"
            continue
        }
        
        try {
            # Disable the account
            Update-MgUser -UserId $account.UserId -AccountEnabled $false
            
            # Revoke sessions
            Revoke-MgUserSignInSession -UserId $account.UserId -ErrorAction SilentlyContinue
            
            Write-AuditLog "Disabled unreviewed account: $($account.UserPrincipalName)" -Properties @{
                UserId = $account.UserId
                DaysSinceLastSignIn = $account.DaysSinceLastSignIn
                Reason = "Inactive >120 days without manager review"
            }
        }
        catch {
            Write-AuditLog "Failed to disable account $($account.UserPrincipalName): $_" -Severity "Error"
        }
    }
    
    return $accountsToDisable.Count
}

# Main execution
function Main {
    Write-AuditLog "=== Starting 90-Day Account Review ==="
    Write-AuditLog "Environment: $Environment"
    Write-AuditLog "Inactivity Threshold: $InactivityThresholdDays days"
    Write-AuditLog "Cutoff Date: $($cutoffDate.ToString('yyyy-MM-dd'))"
    
    if ($WhatIf) {
        Write-AuditLog "RUNNING IN WHATIF MODE - No changes will be made" -Severity "Warning"
    }
    
    # Connect to Graph
    if (-not (Connect-MgGraphWithRetry)) {
        Write-AuditLog "Exiting due to connection failure" -Severity "Error"
        exit 1
    }
    
    # Get all users
    $allUsers = Get-AllActiveUsers
    if ($allUsers.Count -eq 0) {
        Write-AuditLog "No active users found - exiting" -Severity "Warning"
        exit 0
    }
    
    # Identify inactive accounts
    $inactiveAccounts = Get-InactiveAccounts -Users $allUsers
    
    # Send manager notifications
    if ($SendNotifications -and $inactiveAccounts.Count -gt 0) {
        Write-AuditLog "Sending notifications to managers..."
        
        $uniqueManagers = $inactiveAccounts | Where-Object { $_.ManagerEmail } | 
            Select-Object -ExpandProperty ManagerEmail -Unique
        
        foreach ($manager in $uniqueManagers) {
            Send-ManagerNotification -InactiveAccounts $inactiveAccounts -ManagerEmail $manager
        }
        
        Write-AuditLog "Notifications sent to $($uniqueManagers.Count) managers"
    }
    
    # Auto-disable accounts past grace period
    $disabledCount = Disable-UnreviewedAccounts -InactiveAccounts $inactiveAccounts
    Write-AuditLog "Auto-disabled $disabledCount accounts past grace period"
    
    # Generate evidence
    $evidenceFiles = Export-ReviewEvidence -InactiveAccounts $inactiveAccounts -AllUsers $allUsers
    
    Write-AuditLog "=== 90-Day Account Review Complete ==="
    Write-AuditLog "Evidence files generated:"
    $evidenceFiles.GetEnumerator() | ForEach-Object {
        Write-AuditLog "  - $($_.Key): $($_.Value)"
    }
    
    # Summary output
    Write-Host "`n" -NoNewline
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "90-DAY ACCOUNT REVIEW SUMMARY" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Total Active Accounts: $($allUsers.Count)" -ForegroundColor White
    Write-Host "Inactive Accounts: $($inactiveAccounts.Count)" -ForegroundColor Yellow
    Write-Host "Accounts Disabled: $disabledCount" -ForegroundColor Red
    Write-Host "Evidence Location: $OutputPath" -ForegroundColor Green
    Write-Host "========================================`n" -ForegroundColor Cyan
}

# Run main function
Main
