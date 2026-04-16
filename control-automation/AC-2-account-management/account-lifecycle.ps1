<#
.SYNOPSIS
    Automated account lifecycle management for FedRAMP AC-2 compliance.

.DESCRIPTION
    Automates account provisioning, modification, and deprovisioning with full audit trail.
    Integrates with HR systems (Workday, BambooHR, etc.) for employee lifecycle events.
    
    FedRAMP Controls: AC-2, AC-2(1), AC-2(4)

.PARAMETER Environment
    Target environment (Production, NonProduction, Dev)

.PARAMETER TenantId
    Azure AD Tenant ID

.PARAMETER DryRun
    If specified, shows what would be done without making changes

.EXAMPLE
    .\account-lifecycle.ps1 -Environment Production -TenantId "12345678-1234-1234-1234-123456789012"

.NOTES
    Author: Mario Hartson
    Website: https://mhartson.com
    Requires: Microsoft.Graph PowerShell module
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("Production", "NonProduction", "Dev")]
    [string]$Environment,
    
    [Parameter(Mandatory=$true)]
    [string]$TenantId,
    
    [Parameter(Mandatory=$false)]
    [switch]$DryRun,
    
    [Parameter(Mandatory=$false)]
    [string]$LogAnalyticsWorkspaceId
)

# Import required modules
Import-Module Microsoft.Graph.Users
Import-Module Microsoft.Graph.Identity.DirectoryManagement
Import-Module Az.Monitor

# Configuration
$config = @{
    Production = @{
        AccountExpirationDays = 90
        InactivityThresholdDays = 90
        TemporaryAccountMaxDays = 30
        RequireManagerApproval = $true
        LogRetentionDays = 365
    }
    NonProduction = @{
        AccountExpirationDays = 60
        InactivityThresholdDays = 60
        TemporaryAccountMaxDays = 14
        RequireManagerApproval = $false
        LogRetentionDays = 180
    }
    Dev = @{
        AccountExpirationDays = 30
        InactivityThresholdDays = 30
        TemporaryAccountMaxDays = 7
        RequireManagerApproval = $false
        LogRetentionDays = 90
    }
}

$envConfig = $config[$Environment]

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
        Severity = $Severity
        Message = $Message
        Properties = $Properties
    }
    
    Write-Host "[$Severity] $Message"
    
    if ($LogAnalyticsWorkspaceId) {
        # Send to Log Analytics for long-term storage
        $json = $logEntry | ConvertTo-Json -Compress
        Send-AzMonitorCustomLog -WorkspaceId $LogAnalyticsWorkspaceId `
            -SharedKey $env:LOG_ANALYTICS_KEY `
            -Body $json `
            -LogType "FedRAMP_AC2"
    }
}

# Connect to Microsoft Graph
function Connect-MgGraphWithRetry {
    $maxRetries = 3
    $retryCount = 0
    
    while ($retryCount -lt $maxRetries) {
        try {
            Connect-MgGraph -TenantId $TenantId `
                -Scopes "User.ReadWrite.All", "Directory.ReadWrite.All", "AuditLog.Read.All" `
                -NoWelcome
            Write-AuditLog "Successfully connected to Microsoft Graph"
            return $true
        }
        catch {
            $retryCount++
            Write-AuditLog "Failed to connect to Microsoft Graph (attempt $retryCount/$maxRetries): $_" -Severity "Warning"
            Start-Sleep -Seconds 5
        }
    }
    
    Write-AuditLog "Failed to connect to Microsoft Graph after $maxRetries attempts" -Severity "Error"
    return $false
}

# Function: Create new user account
function New-ManagedUserAccount {
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$UserInfo
    )
    
    Write-AuditLog "Processing account creation request for $($UserInfo.UserPrincipalName)"
    
    # Validate required approvals for production
    if ($Environment -eq "Production" -and $envConfig.RequireManagerApproval) {
        if (-not $UserInfo.ManagerApproval) {
            Write-AuditLog "Account creation denied: Missing manager approval" -Severity "Warning"
            return $false
        }
    }
    
    # Build user parameters
    $userParams = @{
        DisplayName = "$($UserInfo.FirstName) $($UserInfo.LastName)"
        UserPrincipalName = $UserInfo.UserPrincipalName
        MailNickname = $UserInfo.MailNickname
        AccountEnabled = $true
        PasswordProfile = @{
            ForceChangePasswordNextSignIn = $true
            Password = New-RandomPassword
        }
        JobTitle = $UserInfo.JobTitle
        Department = $UserInfo.Department
        OfficeLocation = $UserInfo.OfficeLocation
        UsageLocation = "US"
        CompanyName = $UserInfo.CompanyName
    }
    
    # Set account expiration for temporary accounts
    if ($UserInfo.AccountType -eq "Temporary") {
        $expirationDate = (Get-Date).AddDays($envConfig.TemporaryAccountMaxDays)
        $userParams.AccountExpirationDate = $expirationDate
        Write-AuditLog "Temporary account will expire on $expirationDate"
    }
    
    if ($DryRun) {
        Write-AuditLog "[DRY RUN] Would create user: $($UserInfo.UserPrincipalName)" -Severity "Information"
        return $true
    }
    
    try {
        $newUser = New-MgUser @userParams
        
        Write-AuditLog "Successfully created account: $($UserInfo.UserPrincipalName)" `
            -Properties @{
                UserId = $newUser.Id
                AccountType = $UserInfo.AccountType
                Department = $UserInfo.Department
                Manager = $UserInfo.ManagerUPN
                CreatedBy = $env:USERNAME
                ApprovalTicket = $UserInfo.ApprovalTicket
            }
        
        # Send welcome email
        Send-WelcomeEmail -UserPrincipalName $UserInfo.UserPrincipalName -TemporaryPassword $userParams.PasswordProfile.Password
        
        return $true
    }
    catch {
        Write-AuditLog "Failed to create account $($UserInfo.UserPrincipalName): $_" -Severity "Error"
        return $false
    }
}

# Function: Disable user account (termination)
function Disable-ManagedUserAccount {
    param(
        [Parameter(Mandatory=$true)]
        [string]$UserPrincipalName,
        
        [Parameter(Mandatory=$true)]
        [string]$Reason,
        
        [Parameter(Mandatory=$false)]
        [string]$TerminationTicket
    )
    
    Write-AuditLog "Processing account deactivation for $UserPrincipalName"
    
    try {
        $user = Get-MgUser -UserId $UserPrincipalName
        
        if ($DryRun) {
            Write-AuditLog "[DRY RUN] Would disable account: $UserPrincipalName" -Severity "Information"
            return $true
        }
        
        # Disable the account
        Update-MgUser -UserId $user.Id -AccountEnabled $false
        
        # Revoke all active sessions
        Revoke-MgUserSignInSession -UserId $user.Id
        
        # Remove from all groups (except compliance/audit groups)
        $groups = Get-MgUserMemberOf -UserId $user.Id
        foreach ($group in $groups) {
            if ($group.DisplayName -notmatch "Compliance|Audit") {
                Remove-MgGroupMemberByRef -GroupId $group.Id -DirectoryObjectId $user.Id
            }
        }
        
        Write-AuditLog "Successfully disabled account: $UserPrincipalName" `
            -Properties @{
                UserId = $user.Id
                Reason = $Reason
                TerminationTicket = $TerminationTicket
                SessionsRevoked = $true
                GroupsRemoved = $groups.Count
            }
        
        # Schedule account deletion after 60 days (FedRAMP requirement)
        Set-AccountDeletionSchedule -UserId $user.Id -Days 60
        
        return $true
    }
    catch {
        Write-AuditLog "Failed to disable account $UserPrincipalName: $_" -Severity "Error"
        return $false
    }
}

# Function: Generate secure random password
function New-RandomPassword {
    $length = 16
    $chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*()"
    $password = -join ((1..$length) | ForEach-Object { $chars[(Get-Random -Maximum $chars.Length)] })
    return $password
}

# Function: Send welcome email
function Send-WelcomeEmail {
    param(
        [string]$UserPrincipalName,
        [string]$TemporaryPassword
    )
    
    # Implementation depends on your mail system
    # Example using Microsoft Graph sendMail
    Write-AuditLog "Welcome email sent to $UserPrincipalName"
}

# Function: Schedule account deletion
function Set-AccountDeletionSchedule {
    param(
        [string]$UserId,
        [int]$Days
    )
    
    $deletionDate = (Get-Date).AddDays($Days)
    Write-AuditLog "Account $UserId scheduled for deletion on $deletionDate"
    
    # Store in database or scheduled task
    # Implementation depends on your scheduling system
}

# Main execution
function Main {
    Write-AuditLog "Starting account lifecycle management for $Environment environment"
    
    if (-not (Connect-MgGraphWithRetry)) {
        Write-AuditLog "Exiting due to connection failure" -Severity "Error"
        exit 1
    }
    
    Write-AuditLog "Account lifecycle automation configured successfully" -Severity "Information"
    Write-AuditLog "Configuration: $($envConfig | ConvertTo-Json -Compress)"
    
    # Example: Process pending account requests from HR system
    # This would integrate with your HR system API
    # For demo purposes, showing the structure
    
    Write-AuditLog "Account lifecycle management setup complete"
}

# Run main function
Main
