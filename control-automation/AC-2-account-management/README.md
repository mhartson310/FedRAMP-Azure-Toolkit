# AC-2 Account Management — Reference Scripts

**Status: REFERENCE / NOT PRODUCTION-READY.**

This directory demonstrates selected account-lifecycle and periodic-review logic using Microsoft Graph PowerShell. It is **not** a configured HR integration, validated manager-approval workflow, automated offboarding system, or FedRAMP authorization evidence package.

## Contents

- [account-lifecycle.ps1](account-lifecycle.ps1) — example functions for provisioning and deprovisioning. **Live create/disable operations are deliberately blocked** until trusted approvals, credential delivery, group policy, and deletion scheduling are actually implemented and reviewed. The script's entry point intentionally makes no Graph connection or changes; its functions are design references, not a usable provisioning service.
- [90-day-review.ps1](90-day-review.ps1) — review workflow prototype. **Read-only candidate review only.** Notifications are explicitly rejected; no accounts are disabled. Missing sign-in data stays `INSUFFICIENT_DATA` and is never treated as proven inactivity.
- [collect-evidence.ps1](collect-evidence.ps1) — evidence collection example. Any output must be independently reviewed.

## Before any real tenant execution

1. Use a dedicated test tenant, disposable users, and least-privileged read scopes.
2. Review every Graph API permission requested; avoid broad tenant write permissions for assessment.
3. Validate sign-in data availability and licensing; absence of activity is not always proof of inactivity.
4. Verify real manager authority and HR signals; don't treat a caller-provided boolean as approval.
5. Confirm that notifications, approvals, and scheduling actually complete before claiming any lifecycle coverage.
6. Redact identifiers and personnel records before publishing evidence.

**No universal FedRAMP periodic-review interval or compliance percentage is asserted here.** Required timing and control implementation must follow the system's authorized control baseline, agency requirements and actual documented policies.

## Verification

CI parses the scripts **and runs synthetic classification tests** for recent, old, missing, future, and disabled-user activity. These are offline logic tests and do not establish Graph compatibility, production automation, or FedRAMP compliance. See [offline tests](../../tests/offline-policy.tests.ps1).

[Parent scope statement](../../README.md)
