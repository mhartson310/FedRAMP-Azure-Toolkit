# AC-2: Account Management

**NIST 800-53 Control:** The organization manages information system accounts, including establishing, activating, modifying, reviewing, disabling, and removing accounts.

**FedRAMP High Enhancement:** AC-2(1) through AC-2(13) - Automated account management, usage conditions, inactivity logout, etc.

---

## Why This Control Fails

**Common failures in first assessments:**

1. ❌ No automated account provisioning/deprovisioning
2. ❌ Orphaned accounts from former employees still active
3. ❌ No 90-day account review process (or it's manual/incomplete)
4. ❌ Shared accounts in use (not allowed for FedRAMP High)
5. ❌ No documentation of account approval workflow
6. ❌ Privileged accounts not justified with documented need

**Cost of failure:** 6-12 weeks remediation, $50k-$150k in labor

---

## What This Automation Does

**Automated Account Lifecycle:**
- ✅ Account creation with approval workflow
- ✅ Automatic deprovisioning on HR termination
- ✅ 90-day inactive account reviews
- ✅ Privileged account attestation
- ✅ Automated evidence collection

**Evidence Generated:**
- Account creation logs with approvals
- Deprovisioning logs tied to HR events
- Quarterly review reports with manager sign-offs
- Privileged account justification forms
- Audit trail for all account changes

---

## Quick Start

### Prerequisites

- Azure AD Premium P2 (required for Conditional Access)
- Global Administrator or Privileged Role Administrator
- PowerShell 7.0+
- Azure AD PowerShell module

### Install Dependencies

```powershell
# Install required modules
Install-Module -Name Microsoft.Graph -Scope CurrentUser -Force
Install-Module -Name Az.Accounts -Scope CurrentUser -Force
Install-Module -Name Az.Monitor -Scope CurrentUser -Force
```

### 1. Configure Automated Account Lifecycle

```powershell
# Connect to Azure AD
Connect-MgGraph -Scopes "User.ReadWrite.All", "Directory.ReadWrite.All"

# Deploy automated account management
.\account-lifecycle.ps1 -Environment Production -TenantId "YOUR_TENANT_ID"
```

**This configures:**
- Automated onboarding workflow (triggered by HR system)
- Automated offboarding workflow (triggered by HR termination)
- Account expiration for temporary accounts
- Guest account lifecycle management

### 2. Enable 90-Day Account Reviews

```powershell
# Deploy automated 90-day review process
.\90-day-review.ps1 -Environment Production -SendNotifications $true
```

**This creates:**
- Quarterly review schedule
- Manager notifications for inactive accounts
- Automatic account disabling for unreviewed accounts
- Evidence collection and archival

### 3. Configure Privileged Account Management

```powershell
# Deploy privileged account attestation
.\privileged-account-management.ps1 -Environment Production
```

**This enforces:**
- Documented justification for all privileged roles
- Annual re-attestation of privileged access
- Automatic PIM (Privileged Identity Management) configuration
- Just-in-time access for high-privilege operations

---

## Files in This Module

| File | Purpose | Run Frequency |
|------|---------|---------------|
| `account-lifecycle.ps1` | Automated provisioning/deprovisioning | Continuous (event-driven) |
| `90-day-review.ps1` | Inactive account reviews | Quarterly |
| `privileged-account-management.ps1` | Privileged access control | One-time setup + annual |
| `collect-evidence.ps1` | Generate evidence artifacts | Monthly |
| `azure-policy.json` | Policy enforcement for account standards | One-time deployment |

---

## Evidence Collection

### Monthly Evidence Package

```powershell
# Collect all AC-2 evidence for the month
.\collect-evidence.ps1 -Month "2026-04" -OutputPath "C:\Evidence\AC-2"
```

**Generates:**
- `account-creations-2026-04.csv` - All accounts created with approvals
- `account-deletions-2026-04.csv` - All accounts removed with reasons
- `account-reviews-2026-04.pdf` - 90-day review results
- `privileged-accounts-2026-04.xlsx` - Current privileged account inventory
- `shared-accounts-report-2026-04.csv` - Verification of zero shared accounts

### For 3PAO Assessment

When your 3PAO requests AC-2 evidence:

```powershell
# Generate comprehensive AC-2 evidence package
.\collect-evidence.ps1 -AssessmentMode $true -StartDate "2025-10-01" -EndDate "2026-04-30"
```

This creates a complete evidence package covering the entire assessment period.

---

## Control Implementation

### AC-2: Account Management

**Control Statement:**
"The organization manages information system accounts by:
a. Identifying account types
b. Assigning account managers
c. Establishing conditions for group and role membership
d. Specifying authorized users, group/role membership, and access authorizations
e. Requiring approvals by designated officials for requests to create accounts
f. Creating, enabling, modifying, disabling, and removing accounts
g. Monitoring the use of accounts
h. Notifying account managers when accounts are no longer required
i. Deactivating temporary and emergency accounts within a specified time period
j. Reviewing accounts annually or when there is a change in assignment"

**How We Implement:**
- ✅ Automated via Azure AD lifecycle workflows
- ✅ Manager approval required (enforced via Azure AD)
- ✅ HR integration (terminates account on employee departure)
- ✅ 90-day reviews automated
- ✅ Guest accounts expire automatically (30-60 days)

### AC-2(1): Automated System Account Management

**Control Statement:**
"The organization employs automated mechanisms to support the management of information system accounts."

**How We Implement:**
- ✅ PowerShell automation for all account operations
- ✅ Azure AD Lifecycle Workflows
- ✅ Microsoft Graph API integration
- ✅ Event-driven automation (HR system triggers)

### AC-2(2): Removal of Temporary Accounts

**Control Statement:**
"The information system automatically removes or disables temporary accounts after 30 days."

**How We Implement:**
- ✅ Account expiration set on creation
- ✅ Automated cleanup script runs daily
- ✅ Manager notification 7 days before expiration
- ✅ Evidence logged automatically

### AC-2(3): Disable Inactive Accounts

**Control Statement:**
"The information system automatically disables inactive accounts after 90 days of inactivity."

**How We Implement:**
- ✅ Daily scan for accounts inactive >90 days
- ✅ Manager notification before disabling
- ✅ Automatic disable after 30-day grace period
- ✅ Full audit trail maintained

### AC-2(4): Automated Audit Actions

**Control Statement:**
"The information system automatically audits account creation, modification, enabling, disabling, and removal actions."

**How We Implement:**
- ✅ All actions logged to Azure AD Audit Logs
- ✅ Forwarded to Log Analytics (1-year retention)
- ✅ Sentinel analytics rules detect anomalies
- ✅ Monthly reports auto-generated

---

## Cost Estimate

**One-time setup:** 40-60 hours ($8k-$12k labor)

**Monthly operating cost:**
- Azure AD Premium P2: $9/user/month (required)
- Log Analytics ingestion: $100-300/month
- PowerShell automation: $0 (serverless)
- **Total: $9/user/month + $100-300**

**Savings vs manual:**
- Manual account reviews: 80 hours/quarter
- Manual evidence collection: 20 hours/month
- **Labor savings: ~$50k/year**

**ROI:** Pays for itself in 2-3 months

---

## Troubleshooting

### Issue: Accounts not automatically disabled after 90 days

**Solution:**
```powershell
# Verify the scheduled task is running
Get-ScheduledTask -TaskName "AC2-InactiveAccountReview" | Get-ScheduledTaskInfo

# Run manually to test
.\90-day-review.ps1 -WhatIf
```

### Issue: Evidence collection script fails

**Solution:**
```powershell
# Check permissions
Get-MgContext | Select-Object -ExpandProperty Scopes

# Should include: User.Read.All, AuditLog.Read.All, Directory.Read.All
```

### Issue: Manager notifications not sending

**Solution:**
```powershell
# Verify mail-enabled in Exchange Online
Get-Mailbox -Identity "manager@domain.com"

# Test email configuration
Send-MailMessage -To "test@domain.com" -From "noreply@domain.com" -Subject "Test"
```

---

## Integration with Other Controls

**Works with:**
- **AU-2 (Audit Events)** - Account changes logged centrally
- **IA-2 (Authentication)** - MFA enforced on all accounts
- **IA-4 (Identifier Management)** - Unique user identifiers
- **IA-5 (Authenticator Management)** - Password/MFA policies
- **AC-6 (Least Privilege)** - Role-based access control

---

## Next Steps

After implementing AC-2:

1. **Deploy AU-2** (Audit Logging) - Centralize account audit logs
2. **Deploy IA-2** (MFA) - Enforce multi-factor authentication
3. **Test workflows** - Simulate onboarding/offboarding
4. **Collect evidence** - Run for 3 months before assessment
5. **Review with 3PAO** - Have assessor verify implementation

---

## References

- [NIST 800-53 AC-2](https://nvd.nist.gov/800-53/Rev4/control/AC-2)
- [FedRAMP AC-2 Guidance](https://www.fedramp.gov/)
- [Azure AD Lifecycle Workflows](https://learn.microsoft.com/azure/active-directory/governance/what-are-lifecycle-workflows)
- [Microsoft Graph API](https://learn.microsoft.com/graph/overview)

---

**Questions?** [Book a consultation →](https://mhartson.com/consulting)
