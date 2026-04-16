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
   - DELETE: Account should be
