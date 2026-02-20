# Windows Hybrid Lab - Daily Build Log

This repo is my hands-on lab journal while building a Windows hybrid environment in Azure to practice enterprise AD, DNS, network peering, and cross-forest trust.

## Target Environment

- `HOUSTONDC1` - Primary DC and DNS server for Houston (`lab.local`) on `HoustonNET1`
- `HOUSTONDC2` - Replica DC for Houston (`lab.local`) on `HoustonNET1`
- `WESTDC1` - Primary DC and DNS server for West (`west.lab.local`) on `WestNET1`
- `HOUSTONVM1` - Domain-joined workload/test VM
- `HOUSTONVM2` - Domain-joined workload/test VM
- `HoustonNET1` and `WestNET1` are peered in Azure
- `lab.local` and `west.lab.local` use a bidirectional forest trust
- Forward and reverse DNS are configured so hosts are resolvable across environments

## Daily Activity Log

### Day 1 - Foundation and repo setup

- Created repo and IaC folder structure.
- Added Bicep templates for reusable VM deployment.
- Added parameter files for `dev` and `prod` profiles.
- Added PowerShell scripts for validate, what-if, and deploy flows.
- Added a manual GitHub Actions workflow for what-if/deploy.

### Day 2 - Domain design and naming

- Standardized hostnames around the final design:
  - `HOUSTONDC1`
  - `HOUSTONDC2`
  - `WESTDC1`
  - `HOUSTONVM1`
  - `HOUSTONVM2`
- Defined Houston forest/domain as `lab.local`.
- Defined West forest/domain as `west.lab.local`.

### Day 3 - Network and connectivity planning

- Planned separate Azure VNets:
  - `HoustonNET1`
  - `WestNET1`
- Built VNet peering between Houston and West in Bicep.
- Mapped connectivity requirements for AD DS, DNS, Kerberos, LDAP, and RPC traffic.

### Day 4 - AD DS, DNS, and trust objectives

- Built IaC deployment for:
  - `HOUSTONDC1`
  - `HOUSTONDC2`
  - `WESTDC1`
  - `HOUSTONVM1`
  - `HOUSTONVM2`
- Defined final AD/DNS goal state:
  - `HOUSTONDC1` primary DC + DNS for `lab.local`
  - `HOUSTONDC2` replica DC for `lab.local`
  - `WESTDC1` primary DC + DNS for `west.lab.local`
  - Bidirectional forest trust between `lab.local` and `west.lab.local`
  - Forward and reverse DNS working both directions

### Day 5 - Validation checklist (active)

- Confirm A and PTR records for all systems.
- Confirm name resolution both directions across peered VNets.
- Confirm Houston replication health between `HOUSTONDC1` and `HOUSTONDC2`.
- Confirm cross-forest authentication behavior through bidirectional trust.

## What This Lab Demonstrates

- Infrastructure-as-Code using Bicep
- Multi-domain controller design (primary + replica)
- Multi-forest Active Directory architecture
- Azure VNet peering for hybrid-style connectivity
- DNS forward/reverse zone implementation and troubleshooting
- Forest trust design and validation

## Repository Structure

- `infra/main.bicep`
- `infra/modules/windows-vm.bicep`
- `infra/parameters/dev.bicepparam`
- `infra/parameters/prod.bicepparam`
- `scripts/validate.ps1`
- `scripts/whatif.ps1`
- `scripts/deploy.ps1`
- `docs/post-deploy-checklist.md`

## Next Additions

- Post-deploy scripts for AD DS promotion and DNS setup automation.
- Forest trust setup and validation script/checklist artifacts.
