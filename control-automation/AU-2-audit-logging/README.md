# AU-2 Audit Evidence — Read-only Workspace Inventory

**Status: METADATA INVENTORY ONLY. NOT A FEDRAMP ATTESTATION.**

The available [collect-evidence.ps1](collect-evidence.ps1) script retrieves limited Log Analytics workspace configuration metadata and writes an explicit `NOT_ASSESSED` report. It does **not** verify that required audit events are actually ingested, that logs are immutable, or that workspace-level retention meets the system's specific regulatory controls.

## Run in a scoped test subscription

```powershell
Connect-AzAccount
./control-automation/AU-2-audit-logging/collect-evidence.ps1 \
  -ResourceGroupName "rg-lab" \
  -WorkspaceName "law-lab"
```

Requires `Az.Accounts`, `Az.OperationalInsights`, and workspace read permissions.

The output lists the selected workspace, its reported retention setting, and explicit false/unverified status for ingestion coverage, per-table retention, immutability, and control acceptance.

## Additional evidence needed for real assessments

- Define required event types, sources, and organizational NIST/FedRAMP control interpretation.
- Validate connector configuration, ingestion and audit gaps with actual queries.
- Confirm retention by plan/table/archive and any external retention requirements.
- Validate evidence protection, access controls, export provenance, and source timestamps.
- Have compliance stakeholders review the evidence and record pass/fail results independently.

**Do not use a metadata file as proof of AU-2 implementation or ATO.**

[Parent scope statement](../../README.md)
