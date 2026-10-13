<#
.SYNOPSIS
    Formats read-only workspace metadata without making compliance assertions.
#>
function New-AuditWorkspaceInventory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Workspace,
        [Parameter(Mandatory=$true)][string]$ResourceGroupName,
        [Parameter(Mandatory=$true)][string]$Month,
        [Parameter(Mandatory=$true)][DateTimeOffset]$CollectedUtc
    )
    if ($Month -notmatch '^\d{4}-(0[1-9]|1[0-2])$') {
        throw 'Month must use yyyy-MM with a valid calendar month.'
    }
    [pscustomobject]@{
        CollectedUtc             = $CollectedUtc.ToUniversalTime().ToString('o')
        Month                    = $Month
        WorkspaceName            = [string]$Workspace.Name
        WorkspaceResourceGroup   = $ResourceGroupName
        WorkspaceResourceId      = [string]$Workspace.ResourceId
        WorkspaceRetentionDays   = $Workspace.RetentionInDays
        AssessmentResult         = 'NOT_ASSESSED'
        DataIngestionVerified    = $false
        ControlCoverageVerified  = $false
        PerTableRetentionChecked = $false
        ImmutabilityVerified     = $false
        Note                     = 'Workspace configuration inventory only. No control compliance claims.'
    }
}
