<#
.SYNOPSIS
    Classifies Graph user activity as a signal for HUMAN account review.
.DESCRIPTION
    Read-only policy logic. No auto-disable conclusions, no compliance attestation.
    Incomplete sign-in data is NOT treated as proof of inactivity.
#>
function Get-AccountActivityReviewSignal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$User,
        [Parameter(Mandatory = $true)][DateTimeOffset]$ObservedUtc,
        [Parameter(Mandatory = $true)][ValidateRange(1,3650)][int]$ThresholdDays
    )

    $status = 'INSUFFICIENT_DATA'
    $days = $null
    $lastSignIn = $null
    $reason = 'No reliable last-sign-in timestamp; investigate other authentication sources.'

    if ($User.AccountEnabled -eq $false) {
        $status = 'ALREADY_DISABLED'
        $reason = 'Account is already disabled; excluded from active-account inactivity review.'
    } elseif ($null -ne $User.SignInActivity -and
              $null -ne $User.SignInActivity.LastSignInDateTime) {
        try { $lastSignIn = ([DateTimeOffset]$User.SignInActivity.LastSignInDateTime).ToUniversalTime() }
        catch { $lastSignIn = $null }

        if ($null -ne $lastSignIn -and $lastSignIn -le $ObservedUtc) {
            $days = [int][Math]::Floor(($ObservedUtc - $lastSignIn).TotalDays)
            if ($days -ge $ThresholdDays) {
                $status = 'REVIEW_CANDIDATE'
                $reason = 'Last reported sign-in predates the threshold; validate other activity and business need.'
            } else {
                $status = 'NO_CANDIDATE_SIGNAL'
                $reason = 'Available last-sign-in timestamp is newer than the review threshold.'
            }
        }
    }

    [pscustomobject]@{
        UserId             = [string]$User.Id
        UserPrincipalName  = [string]$User.UserPrincipalName
        ReviewStatus       = $status
        DaysSinceSignIn    = $days
        LastSignInUtc      = if ($null -ne $lastSignIn) { $lastSignIn.ToString('o') } else { $null }
        Reason             = $reason
        ApprovalVerified   = $false
        DisableAuthorized  = $false
        ControlAssessed    = $false
    }
}
