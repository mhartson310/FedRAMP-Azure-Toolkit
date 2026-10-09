# FedRAMP High Azure Toolkit

[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![FedRAMP](https://img.shields.io/badge/FedRAMP-High-red.svg)](https://www.fedramp.gov/)
[![Azure](https://img.shields.io/badge/Azure-Governance-0078D4?logo=microsoft-azure)](https://azure.microsoft.com/)
[![Maintained](https://img.shields.io/badge/Maintained-Yes-brightgreen.svg)](https://github.com/mhartson310/FedRAMP-Azure-Toolkit)

A practical Azure compliance-as-code toolkit for implementing and evidencing selected FedRAMP High control patterns with Terraform, PowerShell, Azure Policy, KQL, and Microsoft Sentinel.

📖 **[Read the complete FedRAMP guide →](https://mhartson.com/insights/fedramp-high-azure)**

---

## What this demonstrates

- translating regulatory requirements into technical Azure controls;
- compliance-as-code with Terraform, Azure Policy, PowerShell, and KQL;
- evidence collection and continuous-monitoring design;
- mapping identity, logging, boundary protection, monitoring, and data controls to implementation artifacts;
- separating technical control implementation from authorization and assessment;
- building repeatable governance patterns for regulated Azure environments.

## What this is

A reference toolkit for several high-friction FedRAMP High control areas. It is designed to make the implementation and evidence path concrete while keeping the boundary clear between **technical automation** and **formal authorization**.

---

## ⚠️ Critical Disclaimer

**This toolkit provides AUTOMATION, not authorization.**

- ✅ Automates control implementation
- ✅ Generates evidence artifacts
- ✅ Reduces repetitive manual implementation and evidence work
- ❌ Does NOT replace 3PAO assessment
- ❌ Does NOT guarantee ATO
- ❌ Does NOT replace compliance expertise

**You still need:**
- Experienced 3PAO (Third Party Assessment Organization)
- System Security Plan (SSP) documentation
- Continuous monitoring processes
- Trained security personnel

**FedRAMP authorization is complex.** Use this toolkit as a starting point, not a complete solution.

---

## 📦 What's Included

### Selected control areas

| Control | Name | Automation Type | Evidence Generated |
|---------|------|----------------|-------------------|
| **AC-2** | Account Management | PowerShell + Azure AD | Account lifecycle logs, 90-day reviews |
| **AU-2** | Audit Events | Azure Policy + Sentinel | Log inventory, retention proof |
| **CM-7** | Least Functionality | Azure Policy + Terraform | Approved baselines, scan reports |
| **SC-7** | Boundary Protection | Terraform + Firewall | Network diagrams, rule documentation |
| **IA-2** | Identification & Authentication | PowerShell + Conditional Access | MFA enforcement reports |
| **SI-4** | Information System Monitoring | KQL + Logic Apps | Alert logs, incident response |
| **SI-12** | Information Handling | Azure Policy + Labels | Data classification reports |

### Documentation Templates

- System Security Plan (SSP) outline
- Control implementation statements
- Evidence collection guides
- POA&M tracking spreadsheet
- Continuous monitoring plan

### Compliance as Code

- Azure Policy definitions (FedRAMP High baseline)
- Terraform modules (compliant infrastructure)
- PowerShell scripts (automated evidence collection)
- KQL queries (audit log analysis)

---

## 🚀 Quick Start

### Prerequisites

- **Azure Subscription** with Owner or Contributor role
- **Terraform** >= 1.6.0
- **Azure CLI** >= 2.50.0
- **PowerShell** 7.0+ (for automation scripts)
- **Existing understanding** of FedRAMP requirements

### 1. Clone the Repository

```bash
git clone https://github.com/mhartson310/FedRAMP-Azure-Toolkit.git
cd FedRAMP-Azure-Toolkit
```

### 2. Review Your Gap Analysis

Before deploying anything:

```bash
# Run the FedRAMP readiness assessment
pwsh ./scripts/fedramp-readiness-check.ps1
```

This generates a gap analysis report showing which controls you're missing.

### 3. Deploy Core Compliance Infrastructure

```bash
cd terraform/fedramp-baseline

# Initialize Terraform
terraform init

# Review what will be deployed
terraform plan -var-file="production.tfvars"

# Deploy (takes ~60 minutes)
terraform apply
```

**This deploys:**
- Compliant Azure Policy baseline
- Log Analytics workspace (1-year retention)
- Diagnostic settings for all resources
- Network security baseline
- Encryption enforcement

### 4. Configure Automated Controls

```bash
# Deploy account management automation (AC-2)
pwsh ./control-automation/AC-2-account-management.ps1 -Environment Production

# Deploy audit logging (AU-2)
terraform -chdir=./control-automation/AU-2-audit-logging apply

# Deploy monitoring & alerting (SI-4)
terraform -chdir=./control-automation/SI-4-monitoring apply
```

### 5. Generate Evidence Artifacts

```bash
# Collect evidence for all automated controls
pwsh ./scripts/collect-evidence.ps1 -OutputPath ./evidence -Month "2026-04"
```

This generates:
- Account review logs (AC-2)
- Audit event inventory (AU-2)
- Software baseline reports (CM-7)
- Firewall rule documentation (SC-7)
- MFA compliance reports (IA-2)
- Security alerts summary (SI-4)
- Data classification reports (SI-12)

---

---

## Selected FedRAMP control patterns

### Control 1: AC-2 (Account Management)

**Common implementation gaps:**
- No automated provisioning/deprovisioning
- No 90-day account reviews
- Orphaned accounts from former employees

**Our automation:**
```powershell
# Automated account lifecycle
./control-automation/AC-2-account-management/account-lifecycle.ps1

# Automated 90-day reviews
./control-automation/AC-2-account-management/90-day-review.ps1
```

**Evidence generated:**
- Account creation logs with approval workflows
- Deprovisioning logs tied to HR terminations
- Quarterly review reports with manager sign-offs

**[Implementation guide →](control-automation/AC-2-account-management/README.md)**

---

### Control 2: AU-2 (Audit Events)

**Common implementation gaps:**
- Not logging all required NIST 800-53 events
- Logs scattered across 40+ Azure services
- No proof of log integrity

**Our automation:**
```bash
# Deploy comprehensive audit logging
terraform -chdir=./control-automation/AU-2-audit-logging apply
```

**Evidence generated:**
- Complete audit event matrix (AU-2 mapped to Azure logs)
- Centralized log collection proof (Sentinel)
- 1-year retention verification
- Log integrity verification

**[Implementation guide →](control-automation/AU-2-audit-logging/README.md)**

---

### Control 3: CM-7 (Least Functionality)

**Common implementation gaps:**
- Default Azure VM images have 50+ unnecessary services
- No documented approved software baseline
- Developers install unapproved software

**Our automation:**
```bash
# Enforce approved VM images only
terraform -chdir=./control-automation/CM-7-least-functionality apply
```

**Evidence generated:**
- Approved software baseline documentation
- Monthly vulnerability scans showing compliance
- Azure Policy enforcement logs

**[Implementation guide →](control-automation/CM-7-least-functionality/README.md)**

---

### Control 4: SC-7 (Boundary Protection)

**Common implementation gaps:**
- Firewall in "audit mode" (doesn't block)
- No application-layer inspection
- No TLS decryption

**Our automation:**
```bash
# Deploy Azure Firewall Premium with IPS
terraform -chdir=./control-automation/SC-7-boundary-protection apply
```

**Evidence generated:**
- Network architecture diagrams
- Firewall rule documentation (every rule justified)
- IPS signature update logs
- Monthly traffic analysis reports

**[Implementation guide →](control-automation/SC-7-boundary-protection/README.md)**

---

### Control 5: IA-2 (Identification & Authentication)

**Common implementation gaps:**
- MFA only for admins (requirement: ALL users)
- SMS-based MFA (not phishing-resistant)
- No PIV/CAC support

**Our automation:**
```powershell
# Enforce MFA for all users
./control-automation/IA-2-authentication/enforce-mfa.ps1

# Configure PIV/CAC authentication
./control-automation/IA-2-authentication/configure-piv.ps1
```

**Evidence generated:**
- MFA coverage reports (must be 100%)
- Failed MFA attempt logs
- PIV certificate mapping documentation

**[Implementation guide →](control-automation/IA-2-authentication/README.md)**

---

### Control 6: SI-4 (Information System Monitoring)

**Common implementation gaps:**
- Alerts configured but no one responds
- No defined incident response time
- Can't prove monitoring is happening

**Our automation:**
```bash
# Deploy Sentinel with automated response
terraform -chdir=./control-automation/SI-4-monitoring apply
```

**Evidence generated:**
- Alert rule documentation (all 40+ rules)
- Incident response metrics (MTTD, MTTR)
- Monthly monitoring reports
- Automated response playbook logs

**[Implementation guide →](control-automation/SI-4-monitoring/README.md)**

---

### Control 7: SI-12 (Information Handling and Retention)

**Common implementation gaps:**
- No data classification labels
- PII/CUI mixed with non-sensitive data
- Can't prove proper disposal

**Our automation:**
```powershell
# Deploy data classification
./control-automation/SI-12-information-handling/deploy-labels.ps1

# Enforce encryption for CUI
terraform -chdir=./control-automation/SI-12-information-handling apply
```

**Evidence generated:**
- Data classification policy
- Encryption verification reports
- Retention schedule documentation
- Data disposal certificates

**[Implementation guide →](control-automation/SI-12-information-handling/README.md)**

---

## Scope and implementation reality

The amount of work this toolkit can automate depends on the system boundary, inherited controls, agency requirements, existing Azure platform maturity, evidence expectations, and assessment approach.

Use the repository to accelerate repeatable technical controls and evidence collection—not to estimate authorization cost, schedule, or outcome.

## ⚠️ What This Does NOT Do

**Does NOT replace:**
- 3PAO assessment ($150k-$400k)
- System Security Plan writing (200-600 pages)
- FedRAMP expertise and consulting
- Compliance training for your team
- Incident response procedures
- Physical security controls

**This toolkit:**
- ✅ Automates technical implementation
- ✅ Generates evidence artifacts
- ✅ Enforces compliance via policy
- ❌ Does not replace human expertise
- ❌ Does not guarantee authorization

---

## 🤝 Contributing

Contributions welcome! See [CONTRIBUTING.md](CONTRIBUTING.md).

**High priority:**
- Additional control automation
- Evidence collection improvements
- Documentation template enhancements
- Bug fixes and improvements

---

## 📝 License

MIT License - see [LICENSE](LICENSE) file.

**Important:** This is provided "as-is" without warranty. Consult with FedRAMP experts before using in production.

---

## 🙋 Need Help?

**Free Resources:**
- 📖 [Complete FedRAMP Implementation Guide](https://mhartson.com/insights/fedramp-high-azure)
- 📥 [FedRAMP Control Mapping Spreadsheet](https://mhartson.com/resources/fedramp-mapping)
- 💬 [Hartson Security Guild Community](https://hartson-security-guild.circle.so)

**Professional Services:**
- 🔍 FedRAMP readiness assessment
- 🏗️ Full implementation services
- 📋 3PAO selection guidance
- 🎓 Team training

**[Book a FedRAMP discovery call →](https://mhartson.com/consulting)**

---

## ⚡ Quick Links

- [Implementation Guide](docs/implementation-guide.md)
- [Control Mapping (421 controls)](docs/control-mapping.xlsx)
- [3PAO Selection Guide](docs/3pao-selection-guide.md)
- [Evidence Collection Guide](documentation-templates/evidence-guides/)
- [Blog Post: FedRAMP High on Azure](https://mhartson.com/insights/fedramp-high-azure)

---

## 🔗 Related Projects

- [Azure-Landing-Zones](https://github.com/mhartson310/Azure-Landing-Zones) - Production landing zone templates
- [Sentinel-KQL-Library](https://github.com/mhartson310/Sentinel-KQL-Library) - Detection rules for SI-4
- [Azure-Security-Baseline](https://github.com/mhartson310/Azure-Security-Baseline) - CIS/NIST hardening

---

**Built with 🔐 by [Mario Hartson](https://mhartson.com)** | Cloud Security Architect | FedRAMP Specialist

📧 mario@hartsonadvisory.com | 💼 [LinkedIn](https://linkedin.com/in/mariohartson) | 🌐 [mhartson.com](https://mhartson.com)

## 📂 Repository Structure

