# Windows Hybrid Lab

A dual-forest Active Directory lab built entirely in Azure using Bicep. Two forests (`lab.local` and `west.lab.local`) live in separate VNets connected by peering, with domain controllers, replica DCs, and member servers you can spin up in minutes to practice enterprise AD, DNS, replication, and cross-forest trusts.

I built this because I wanted a repeatable environment for learning Windows identity infrastructure the way it actually works in production -- multiple forests, multiple sites, trust relationships, DNS delegation -- without burning hours clicking through the portal every time.

Note: this repository intentionally preserves my canonical lab defaults (hostnames, IPs, domains) so the documented topology and validation evidence stay consistent.

## Architecture

```
            HoustonNET1 (10.20.0.0/16)                   WestNET1 (10.30.0.0/16)
           ┌──────────────────────────┐                  ┌──────────────────────┐
           │  HoustonServers Subnet   │   VNet Peering   │  WestServers Subnet  │
           │     10.20.1.0/24         │◄────────────────►│    10.30.1.0/24      │
           │                          │                  │                      │
           │  HOUSTONDC1  10.20.1.10  │                  │  WESTDC1  10.30.1.10 │
           │  (DC + DNS + CA,         │                  │  (DC + DNS,          │
           │   lab.local)             │                  │   west.lab.local)    │
           │                          │                  │                      │
           │  HOUSTONDC2  10.20.1.11  │                  │  WESTFS1  10.30.1.20 │
           │  (Replica DC, lab.local) │                  │  (File server + DFS) │
           │                          │                  └──────────────────────┘
           │  HOUSTONVM1  10.20.1.20  │
           │  HOUSTONVM2  10.20.1.21  │        lab.local  ◄──  forest trust  ──►  west.lab.local
           │  (Member servers)        │              (bidirectional)
           │                          │
           │  HOUSTONFS1  10.20.1.30  │        ┌─────────────────────────────────┐
           │  (File server + DFS)     │        │  Log Analytics Workspace        │
           │                          │        │  Azure Monitor Agent on all VMs │
           │  HOUSTONDHCP1 10.20.1.40 │        │  Windows Events + Perf Counters │
           │  (DHCP + WSUS)           │        │  Alert Rules (CPU, Disk, etc.)  │
           │                          │        └─────────────────────────────────┘
           │  HOUSTAAC1   10.20.1.50  │
           │  (Entra Connect sync)    │        ┌─────────────────────────────────┐
           │                          │        │  Microsoft Entra ID             │
           │  AzureBastionSubnet      │        │  ◄── Password Hash Sync ──      │
           │     10.20.0.0/26         │        │  Hybrid identity from lab.local │
           │  (Azure Bastion host)    │        └─────────────────────────────────┘
           └──────────────────────────┘
```

## What This Demonstrates

- **Infrastructure as Code** -- Modular Bicep templates (networking, bastion, monitoring, VM modules) composed by a thin orchestrator
- **Multi-forest Active Directory** -- Two independent forests with a bidirectional trust
- **DC replication** -- Primary + replica domain controller in the Houston forest
- **Read-Only Domain Controller** -- Optional RODC deployment for branch-office simulation
- **Automated DC promotion** -- Optional CustomScriptExtension-based AD DS forest/domain creation at deploy time
- **Cross-forest DNS & trust automation** -- Scripted conditional forwarders and bidirectional forest trust setup
- **Azure Bastion** -- Secure RDP access without public IPs on VMs (Standard SKU with native client + tunneling)
- **Azure Monitor + Alerts** -- Centralized logging via AMA with alert rules for heartbeat loss, high CPU, low disk, and account lockouts
- **KQL query library** -- Ready-to-use Log Analytics queries for AD replication errors, lockout investigation, failed logons, and performance trends
- **AD Sites & Subnets** -- Site topology matching Azure VNet layout with inter-site replication
- **FSMO role management** -- Inspection and transfer of all five operations master roles
- **Group Managed Service Accounts** -- KDS root key, gMSA creation, and host-based password retrieval
- **Security baseline GPOs** -- Password policy, audit policy, firewall, and SMBv1 hardening via Group Policy
- **File services & DFS** -- SMB shares with NTFS permissions, DFS Namespaces, cross-forest DFS Replication
- **DHCP Server** -- Scope creation, AD authorization, option configuration (DNS, gateway, domain)
- **WSUS** -- Windows Server Update Services with product/classification targeting, computer groups, and client GPO
- **Active Directory Certificate Services** -- Enterprise Root CA, certificate templates, LDAPS enablement
- **Microsoft Entra Connect** -- Guided hybrid identity setup from on-premises AD to Entra ID with Password Hash Sync
- **Azure networking** -- VNet peering, subnet-level NSGs, static private IPs
- **DNS design** -- Forward/reverse zones, conditional forwarders across forests
- **Deployment automation** -- PowerShell scripts and GitHub Actions for validate/what-if/deploy
- **Automated validation** -- Pester test suite verifying AD health, DNS, replication, trust, and security baselines

## Prerequisites

- An Azure subscription (Pay-As-You-Go works fine)
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) with the Bicep extension
- A resource group created in your target region
- PowerShell (for the helper scripts) or just use `az deployment` directly

If you do not have an active subscription, you can still run local template validation (`.\scripts\validate.ps1`) and review post-deploy automation scripts.

## How to Deploy

### 1. Clone and configure

```bash
git clone https://github.com/jaredio/windows-hybrid-lab.git
cd windows-hybrid-lab
```

Edit `infra/parameters/dev.bicepparam` (or `prod.bicepparam`) to set your preferred regions, VM sizes, and -- importantly -- `allowedSourceAddressPrefix` to your public IP so RDP is locked down.

### 2. Validate the template

```powershell
.\scripts\validate.ps1
```

Or manually:

```bash
az deployment group validate \
  --resource-group <your-rg> \
  --template-file infra/main.bicep \
  --parameters infra/parameters/dev.bicepparam \
  --parameters adminPassword="<YourStrongPassword>"
```

### 3. Preview changes

```powershell
.\scripts\whatif.ps1 -ResourceGroupName <your-rg> -Environment dev -AdminPassword "<YourStrongPassword>"
```

### 4. Deploy

```powershell
.\scripts\deploy.ps1 -ResourceGroupName <your-rg> -Environment dev -AdminPassword "<YourStrongPassword>"
```

Or manually:

```bash
az deployment group create \
  --resource-group <your-rg> \
  --template-file infra/main.bicep \
  --parameters infra/parameters/dev.bicepparam \
  --parameters adminPassword="<YourStrongPassword>"
```

The password must be at least 12 characters. Azure will reject it otherwise.

## Repository Structure

| File | Purpose |
|------|---------|
| **Infrastructure** | |
| `infra/main.bicep` | Orchestrator -- composes networking, bastion, monitoring, and VM modules with DC promotion scripts |
| `infra/modules/networking.bicep` | NSGs, VNets, subnets, and bidirectional VNet peering |
| `infra/modules/bastion.bicep` | Azure Bastion Standard SKU with native client tunneling |
| `infra/modules/monitoring.bicep` | Log Analytics, Data Collection Rule, alert rules (heartbeat, CPU, disk, lockout), action group |
| `infra/modules/windows-vm.bicep` | Reusable VM module (NIC, optional public IP, OS disk, managed identity, CSE, AMA, DCR association) |
| `infra/parameters/dev.bicepparam` | Dev environment parameters (B-series VMs, eastus/westus2) |
| `infra/parameters/prod.bicepparam` | Prod environment parameters (D-series VMs, eastus2/westus2) |
| **Deployment Scripts** | |
| `scripts/validate.ps1` | Validates Bicep template and parameter files |
| `scripts/whatif.ps1` | Previews deployment changes with `az deployment group what-if` |
| `scripts/deploy.ps1` | Executes deployment with `az deployment group create` |
| **Post-Deploy Scripts** | |
| `scripts/post-deploy/Configure-CrossForestDNS.ps1` | Auto-detect forest and create conditional DNS forwarders |
| `scripts/post-deploy/Configure-ForestTrust.ps1` | Create bidirectional forest trust with validation |
| `scripts/post-deploy/Configure-RODC.ps1` | Promote HOUSTONDC2 as a Read-Only Domain Controller |
| `scripts/post-deploy/Configure-ADSitesAndSubnets.ps1` | Create AD sites and subnets matching VNet topology |
| `scripts/post-deploy/Inspect-FSMORoles.ps1` | Display and optionally transfer FSMO roles |
| `scripts/post-deploy/Configure-gMSA.ps1` | Set up KDS root key and group Managed Service Accounts |
| `scripts/post-deploy/Configure-BaselineGPOs.ps1` | Create and link security baseline GPOs |
| `scripts/post-deploy/Configure-FileServer.ps1` | Install file server role, SMB shares, DFS Namespace |
| `scripts/post-deploy/Configure-DFSReplication.ps1` | Cross-forest DFS Replication between HOUSTONFS1 and WESTFS1 |
| `scripts/post-deploy/Configure-DHCP.ps1` | DHCP server install, AD authorization, scope and options |
| `scripts/post-deploy/Configure-WSUS.ps1` | WSUS install, product/classification config, client GPO |
| `scripts/post-deploy/Configure-ADCS.ps1` | Enterprise Root CA, certificate templates, LDAPS |
| `scripts/post-deploy/Configure-EntraConnect.ps1` | Entra Connect installer + wizard-guided Password Hash Sync setup |
| **Testing** | |
| `tests/Lab.Tests.ps1` | Pester test suite -- AD health, DNS, replication, trust, security baseline |
| **Documentation** | |
| `docs/post-deploy-checklist.md` | Post-deployment steps: AD promotion, DNS, trust, sites, GPOs |
| `docs/kql-queries.md` | KQL queries for Log Analytics: replication errors, lockouts, performance trends |
| **CI/CD** | |
| `.github/workflows/azure-lab.yml` | Manual GitHub Actions workflow for what-if and deploy |

## Post-Deployment

After the VMs are up, the real work starts. If `enableDCPromotion=true`, steps 1-5 and 8 are automated -- skip to step 6.

1. **Promote HOUSTONDC1** to domain controller for `lab.local` and configure DNS
2. **Promote HOUSTONDC2** as a replica DC or RODC in `lab.local` (see `Configure-RODC.ps1`)
3. **Promote WESTDC1** to domain controller for `west.lab.local` and configure DNS
4. **Set up DNS** -- run `Configure-CrossForestDNS.ps1` on each DC for cross-forest resolution
5. **Join member servers** -- domain-join HOUSTONVM1 and HOUSTONVM2 to `lab.local`
6. **Create the forest trust** -- run `Configure-ForestTrust.ps1` on HOUSTONDC1
7. **Configure AD Sites & Subnets** -- match the Azure VNet topology (`Configure-ADSitesAndSubnets.ps1`)
8. **Set up gMSAs** -- KDS root key and managed service accounts (`Configure-gMSA.ps1`)
9. **Apply security GPOs** -- password, audit, firewall, SMBv1 baselines (`Configure-BaselineGPOs.ps1`)
10. **Configure file servers** -- `Configure-FileServer.ps1` on HOUSTONFS1 and WESTFS1
11. **Set up DFS Replication** -- `Configure-DFSReplication.ps1` on HOUSTONDC1
12. **Configure DHCP** -- `Configure-DHCP.ps1` on HOUSTONDHCP1
13. **Configure WSUS** -- `Configure-WSUS.ps1` on HOUSTONDHCP1
14. **Install Enterprise CA** -- `Configure-ADCS.ps1` on HOUSTONDC1
15. **Set up Entra Connect** -- run `Configure-EntraConnect.ps1 -TenantDomain "<yourtenant>.onmicrosoft.com" -InstallerPath "<path-to-AzureADConnect.msi>"` on HOUSTAAC1, then complete the wizard
16. **Validate** -- run `Invoke-Pester .\tests\Lab.Tests.ps1 -Output Detailed`

See `docs/post-deploy-checklist.md` for the detailed walkthrough.

## Monitoring & Alerts

When `deployMonitoring=true` (default), the template deploys:

- **Log Analytics workspace** with configurable retention (default 30 days)
- **Data Collection Rule** capturing Windows Event Logs (Application, System, Security) and performance counters (CPU, memory, disk, network)
- **Azure Monitor Agent** on all VMs with system-managed identity

Set `alertEmailAddress` in your parameter file to also deploy alert rules:

| Alert | Severity | Trigger |
|-------|----------|---------|
| VM Heartbeat Loss | 1 (Error) | No heartbeat for 5+ minutes |
| High CPU Usage | 2 (Warning) | CPU > 90% sustained for 5 minutes |
| Low Disk Space | 2 (Warning) | Any logical disk < 10% free |
| Account Lockout | 3 (Info) | Security Event 4740 detected |

See `docs/kql-queries.md` for ready-to-use Log Analytics queries.

## Automated Testing

The Pester test suite in `tests/Lab.Tests.ps1` validates the full lab state from a domain controller:

```powershell
# Install Pester (if needed):
Install-Module Pester -Force -SkipPublisherCheck

# Run all tests (requires both forests + trust):
Invoke-Pester .\tests\Lab.Tests.ps1 -Output Detailed

# Skip cross-forest tests (before trust is set up):
$SkipCrossForest = $true
Invoke-Pester .\tests\Lab.Tests.ps1 -Output Detailed
```

Tests cover: forest health, DC roles, DNS forward/reverse/cross-forest, replication timing, trust validation, password policy, GPO linkage, gMSA existence, and AD Sites & Subnets.

---

## Daily Build Log

This section is my running journal of what I built each day.

### Day 1 -- Foundation and repo setup

- Created repo and IaC folder structure.
- Added Bicep templates for reusable VM deployment.
- Added parameter files for `dev` and `prod` profiles.
- Added PowerShell scripts for validate, what-if, and deploy flows.
- Added a manual GitHub Actions workflow for what-if/deploy.

### Day 2 -- Domain design and naming

- Standardized hostnames around the final design:
  - `HOUSTONDC1`
  - `HOUSTONDC2`
  - `WESTDC1`
  - `HOUSTONVM1`
  - `HOUSTONVM2`
- Defined Houston forest/domain as `lab.local`.
- Defined West forest/domain as `west.lab.local`.

### Day 3 -- Network and connectivity planning

- Planned separate Azure VNets:
  - `HoustonNET1`
  - `WestNET1`
- Built VNet peering between Houston and West in Bicep.
- Mapped connectivity requirements for AD DS, DNS, Kerberos, LDAP, and RPC traffic.

### Day 4 -- AD DS, DNS, and trust objectives

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

### Day 5 -- Validation checklist

- Confirm A and PTR records for all systems.
- Confirm name resolution both directions across peered VNets.
- Confirm Houston replication health between `HOUSTONDC1` and `HOUSTONDC2`.
- Confirm cross-forest authentication behavior through bidirectional trust.

### Day 6 -- AD DS depth (AZ-800 coverage)

- Added RODC support: `houstonDc2Role` Bicep parameter + `Configure-RODC.ps1` for Read-Only DC promotion with password replication policy.
- Added `Configure-ADSitesAndSubnets.ps1` to create Houston/West sites, subnet mappings, and inter-site replication links.
- Added `Inspect-FSMORoles.ps1` for displaying and transferring all five FSMO roles (with `ntdsutil` reference).
- Added `Configure-gMSA.ps1` for KDS root key creation, gMSA provisioning, and member server install.
- Added `Configure-BaselineGPOs.ps1` for password policy, audit policy, firewall, and SMBv1 hardening GPOs.
- Updated post-deploy checklist with sections 10-14.

### Day 7 -- Tier 1 infrastructure (Bastion, DC promotion, monitoring)

- Added Azure Bastion (Standard SKU) with native client tunneling -- replaces public IP RDP access.
- Added optional automated DC promotion via CustomScriptExtension (`enableDCPromotion` parameter).
- Added Log Analytics workspace + Data Collection Rule for centralized Windows Event and performance counter collection.
- Added Azure Monitor Agent (AMA) extension with system-managed identity to all VMs.
- Added deployment ordering (`dependsOn`) so HOUSTONDC2 and member VMs wait for HOUSTONDC1 when promotion is enabled.
- Set `houstonVm1PublicIp = false` in parameter files (Bastion replaces direct RDP).

### Day 8 -- Modular architecture, alerting, and automated testing

- Decomposed `main.bicep` into focused modules: `networking.bicep`, `bastion.bicep`, `monitoring.bicep`, with `main.bicep` as a thin orchestrator.
- Added Azure Monitor alert rules (heartbeat loss, high CPU, low disk space, account lockout) with email action group.
- Created `docs/kql-queries.md` with ready-to-use Log Analytics queries for AD replication, lockouts, failed logons, GPO failures, and performance trends.
- Automated cross-forest DNS forwarders (`Configure-CrossForestDNS.ps1`) with auto-detection and idempotency.
- Automated bidirectional forest trust creation (`Configure-ForestTrust.ps1`) with DNS prerequisite validation and secure channel verification.
- Added Pester test suite (`tests/Lab.Tests.ps1`) validating AD forest health, DC roles, DNS, replication, trust, password policy, GPOs, gMSA, and AD Sites.

### Day 9 -- Enterprise services expansion (File, DHCP, WSUS, CA, Entra Connect)

- Added 4 new VMs: HOUSTONFS1 (file server), HOUSTONDHCP1 (DHCP + WSUS), HOUSTAAC1 (Entra Connect), WESTFS1 (West file server).
- Added `westDomainJoinScript` for WESTFS1 to join `west.lab.local` instead of `lab.local`.
- Added `Configure-FileServer.ps1` for SMB shares, NTFS permissions, and DFS Namespaces.
- Added `Configure-DFSReplication.ps1` for cross-forest file replication between Houston and West.
- Added `Configure-DHCP.ps1` for DHCP scope creation, AD authorization, and scope options.
- Added `Configure-WSUS.ps1` for Windows Update services with computer target groups and client GPO.
- Added `Configure-ADCS.ps1` for Enterprise Root CA, certificate templates, and LDAPS enablement.
- Added `Configure-EntraConnect.ps1` for hybrid identity sync to Entra ID with Password Hash Sync.
- Expanded Pester tests with 6 new Describe blocks covering all new services.
- Updated post-deploy checklist with sections 15-21.

## Next Additions

- Azure Arc onboarding for hybrid VM management.
- Windows Admin Center for centralized server management.
