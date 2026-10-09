# FedRAMP Azure Toolkit — Selected Compliance-as-Code Patterns

Practical Azure control-automation examples focused on **account lifecycle** and **audit evidence collection**, with guidance on how these relate to regulated-cloud governance.

> **Scope:** A partial technical reference, **not** a FedRAMP authorization package, compliance certification, complete High baseline, or substitute for a 3PAO assessment.

## What this demonstrates

- Translating identity and audit-control objectives into repeatable engineering workflows
- PowerShell-based account lifecycle and access-review patterns
- Evidence collection for control review
- Separating control implementation from assessment and authorization

## Problem

Regulated-cloud projects need repeatable technical implementations and reviewable evidence, not compliance labels alone.

## Architecture and trust boundaries

Account lifecycle operations cross identity-administration and organizational approval boundaries. Audit evidence collection crosses administrative, telemetry, and assessor boundaries. Validate permissions, data retention, and provenance before use.

## Implemented examples

| Control family | Available artifact | What to review |
|---|---|---|
| AC-2 Account Management | [Lifecycle and 90-day review scripts](control-automation/AC-2-account-management/README.md) | Provisioning, deprovisioning, approvals, least privilege |
| AU-2 Audit Events | [Audit logging and evidence guidance](control-automation/AU-2-audit-logging/README.md) | Log source scope, completeness, retention, evidence quality |

The repository does not currently include deployable automation for every control family or the other modules described in earlier versions of this README.

## Threats and controls

Review identity misuse, inappropriate standing access, missing or tampered logs, incomplete evidence, and failures of separation of duties.

## Deployment and validation

Read scripts before executing them; use a non-production tenant or scoped test identities. Verify required permissions, inspect outputs, and retain a dated evidence record. No live FedRAMP assessment outcome is claimed.

## Monitoring and governance

Pair evidence collection with [Sentinel detection patterns](https://github.com/mhartson310/Sentinel-KQL-Library) and the [Zero Trust validation model](https://github.com/mhartson310/Azure-Zero-Trust-Reference-Architectures).

## Limitations

Implementation of selected technical controls does not establish NIST 800-53 coverage, FedRAMP High readiness, authorization to operate, or any fixed percentage of compliance automation. Those conclusions require a defined system boundary, control inheritance analysis, evidence, and assessment.

## Related architecture work

[Azure landing zones](https://github.com/mhartson310/Azure-Landing-Zones) · [Secure enterprise RAG](https://github.com/mhartson310/Azure-Secure-Enterprise-RAG)

**Use these examples as engineering starting points, not as compliance guarantees.**
