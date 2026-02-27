# Lab Validation Tests

Pester test suite that validates the full Windows Hybrid Lab post-deployment state.

## Prerequisites

- Run on **HOUSTONDC1** (or any `lab.local` domain controller)
- Pester v5+ installed: `Install-Module Pester -Force -SkipPublisherCheck`
- All post-deploy checklist steps completed

## Usage

```powershell
# Run all tests (requires both forests + trust configured):
Invoke-Pester .\tests\Lab.Tests.ps1 -Output Detailed

# Skip cross-forest tests (useful before trust is established):
$SkipCrossForest = $true
Invoke-Pester .\tests\Lab.Tests.ps1 -Output Detailed
```

## What's Tested

| Describe Block | Tests |
|----------------|-------|
| AD Forest Health | Forest existence, domain/forest functional levels |
| Domain Controller Health | DC reachability, writable/RODC status, SYSVOL/NETLOGON shares |
| DNS Resolution | Forward lookups, reverse lookups, conditional forwarders |
| Replication Health | repadmin error check, recent replication timestamps |
| Forest Trust | Bidirectional trust existence, forest-transitive type, secure channel |
| Security Baseline | Password policy, GPO existence/linkage, gMSA, AD Sites & Subnets |
