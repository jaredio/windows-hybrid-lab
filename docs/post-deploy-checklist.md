# Post-Deployment Runbook (Houston + West Forests)

Use this checklist after deploying infrastructure from `infra/main.bicep`.

> **Automation note:** When `enableDCPromotion=true`, sections 1-5 and 8 are handled automatically by CustomScriptExtension during deployment. You can skip those sections and start at section 6 (cross-forest DNS). The scripts include retry logic and automatic reboots.

## 1. Promote `HOUSTONDC1` as first DC for `lab.local`

Run in elevated PowerShell:

```powershell
Install-WindowsFeature AD-Domain-Services, DNS -IncludeManagementTools
Import-Module ADDSDeployment
Install-ADDSForest `
  -DomainName "lab.local" `
  -DomainNetbiosName "LAB" `
  -InstallDNS `
  -SafeModeAdministratorPassword (Read-Host -AsSecureString "DSRM Password") `
  -Force
```

Expected result: `HOUSTONDC1` is primary DC + DNS for `lab.local`.

## 2. Configure Houston reverse DNS zone

On `HOUSTONDC1`:

```powershell
Get-DnsServerZone
Add-DnsServerPrimaryZone -NetworkId "10.20.1.0/24" -ReplicationScope Forest
```

Expected result: forward and reverse zones exist for Houston forest.

## 3. Promote `HOUSTONDC2` as replica DC for `lab.local`

1. Set DNS client on `HOUSTONDC2` to `10.20.1.10`.
2. Join `HOUSTONDC2` to `lab.local`.
3. Promote as additional domain controller.

Expected result: AD DS and DNS redundancy in Houston.

## 4. Promote `WESTDC1` as first DC for `west.lab.local`

On `WESTDC1`:

```powershell
Install-WindowsFeature AD-Domain-Services, DNS -IncludeManagementTools
Import-Module ADDSDeployment
Install-ADDSForest `
  -DomainName "west.lab.local" `
  -DomainNetbiosName "WEST" `
  -InstallDNS `
  -SafeModeAdministratorPassword (Read-Host -AsSecureString "DSRM Password") `
  -Force
```

Expected result: `WESTDC1` is primary DC + DNS for west forest.

## 5. Configure West reverse DNS zone

On `WESTDC1`:

```powershell
Get-DnsServerZone
Add-DnsServerPrimaryZone -NetworkId "10.30.1.0/24" -ReplicationScope Forest
```

Expected result: forward and reverse zones exist for west forest.

## 6. Configure cross-forest DNS resolution

**Automated** (recommended):

```powershell
# On HOUSTONDC1:
.\scripts\post-deploy\Configure-CrossForestDNS.ps1

# Then on WESTDC1:
.\scripts\post-deploy\Configure-CrossForestDNS.ps1
```

The script auto-detects which forest it's running on and creates the correct conditional forwarder for the other forest. It includes idempotency checks and validation.

**Manual alternative** -- add conditional forwarders:

- On Houston DNS (`HOUSTONDC1`/`HOUSTONDC2`): forward `west.lab.local` to `10.30.1.10`
- On West DNS (`WESTDC1`): forward `lab.local` to `10.20.1.10` (and optionally `10.20.1.11`)

```powershell
# On HOUSTONDC1:
Add-DnsServerConditionalForwarderZone -Name "west.lab.local" -MasterServers 10.30.1.10 -ReplicationScope Forest

# On WESTDC1:
Add-DnsServerConditionalForwarderZone -Name "lab.local" -MasterServers 10.20.1.10 -ReplicationScope Forest
```

Expected result: names resolve across forests over peered VNets.

## 7. Configure bidirectional forest trust

**Automated** (recommended):

```powershell
# On HOUSTONDC1 (after DNS forwarders are configured in both directions):
.\scripts\post-deploy\Configure-ForestTrust.ps1
```

The script validates DNS prerequisites, prompts for remote forest credentials, creates the trust via `netdom`, and verifies the secure channel.

**Manual alternative** -- create a two-way forest trust between:

- `lab.local`
- `west.lab.local`

Using Active Directory Domains and Trusts: right-click `lab.local` > Properties > Trusts > New Trust > target `west.lab.local`, Bidirectional, Forest trust.

Expected result: users/resources can be authenticated across forests (per trust and ACL scope).

## 8. Join member VMs

Join:

- `HOUSTONVM1` to `lab.local`
- `HOUSTONVM2` to `lab.local`

Expected result: member VMs authenticate via Houston DCs and resolve both forests.

## 9. Validate DNS and trust

From each host:

```powershell
nslookup HOUSTONDC1.lab.local
nslookup WESTDC1.west.lab.local
nslookup 10.20.1.10
nslookup 10.30.1.10
```

Validate trust:

```powershell
nltest /domain_trusts
```

Expected result: forward + reverse resolution works and trust is visible.

## 10. (Optional) Promote `HOUSTONDC2` as RODC

If you want to practice Read-Only Domain Controller deployment instead of a writable replica, use this path. If you already promoted `HOUSTONDC2` as a writable replica in section 3, you must demote it first (demotion commands are included in the script).

Set `houstonDc2Role = 'RODC'` in your `.bicepparam` file and redeploy to update the Azure tags, then run:

```powershell
# On HOUSTONDC2:
.\scripts\post-deploy\Configure-RODC.ps1
```

Expected result: `HOUSTONDC2` is an RODC for `lab.local` with password replication policy configured.

Verify:

```powershell
Get-ADDomainController -Filter * | Format-Table Name, IsReadOnly, Site
Get-ADDomainControllerPasswordReplicationPolicy -Identity HOUSTONDC2 -Allowed
Get-ADDomainControllerPasswordReplicationPolicy -Identity HOUSTONDC2 -Denied
```

## 11. Configure AD Sites and Subnets

Create AD sites matching the Azure VNet topology so replication follows the correct network paths and DCs are associated with the right locations.

```powershell
# On HOUSTONDC1:
.\scripts\post-deploy\Configure-ADSitesAndSubnets.ps1
```

The script also includes a commented block for configuring the West forest sites on `WESTDC1`.

Expected result: Houston and West sites exist with subnets `10.20.1.0/24` and `10.30.1.0/24` mapped correctly, and a Houston-West site link with 15-minute replication.

## 12. Inspect and Transfer FSMO Roles

Display all five FSMO role holders. Optionally transfer roles to practice DC migration scenarios.

```powershell
# Inspect only:
.\scripts\post-deploy\Inspect-FSMORoles.ps1

# Inspect both forests:
.\scripts\post-deploy\Inspect-FSMORoles.ps1 -IncludeWest

# Transfer all roles to HOUSTONDC2:
.\scripts\post-deploy\Inspect-FSMORoles.ps1 -TransferTo HOUSTONDC2

# Transfer specific roles:
.\scripts\post-deploy\Inspect-FSMORoles.ps1 -TransferTo HOUSTONDC2 -Roles PDCEmulator, RIDMaster
```

Expected result: FSMO role holders are displayed and optionally moved to the target DC.

## 13. Configure Group Managed Service Accounts

Set up gMSA infrastructure (KDS root key, host group) and create a sample gMSA for member servers.

```powershell
# On HOUSTONDC1:
.\scripts\post-deploy\Configure-gMSA.ps1
```

After the script creates the host group, reboot `HOUSTONVM1` and `HOUSTONVM2` so they pick up the new group membership before the gMSA install step.

Expected result: `svc-WebApp` gMSA exists, installed and verified on member servers.

Verify:

```powershell
Get-ADServiceAccount -Identity svc-WebApp -Properties PrincipalsAllowedToRetrieveManagedPassword
# On member server:
Test-ADServiceAccount -Identity svc-WebApp
```

## 14. Create Security Baseline GPOs

Create and link baseline GPOs for password policy, audit policy, firewall, and SMBv1 hardening.

```powershell
# On HOUSTONDC1:
.\scripts\post-deploy\Configure-BaselineGPOs.ps1
```

Expected result: Four GPOs linked to the domain root, domain password policy hardened.

Verify:

```powershell
Get-GPO -All | Format-Table DisplayName, GpoStatus
# On a member server after gpupdate /force:
gpresult /r
```

## 15. Configure File Server (HOUSTONFS1)

Install file server roles, create SMB shares with NTFS permissions, and set up a DFS Namespace.

```powershell
# On HOUSTONFS1:
.\scripts\post-deploy\Configure-FileServer.ps1
```

Expected result: Department, Public, and IT shares exist. DFS Namespace `\\lab.local\Shares` is accessible.

Verify:

```powershell
Get-SmbShare | Where-Object { $_.Name -notin @('ADMIN$', 'C$', 'IPC$') }
Test-Path "\\lab.local\Shares"
```

## 16. Configure File Server (WESTFS1)

Install file server roles on WESTFS1 and create matching share structure for DFS Replication.

```powershell
# On WESTFS1:
.\scripts\post-deploy\Configure-FileServer.ps1 -SkipDfsNamespace
```

Expected result: Department, Public, and IT shares exist on WESTFS1.

## 17. Configure DFS Replication

Create a replication group between HOUSTONFS1 and WESTFS1 to replicate the Department folder across forests.

```powershell
# On HOUSTONDC1 (manages replication group):
.\scripts\post-deploy\Configure-DFSReplication.ps1
```

Expected result: DFS Replication group `Houston-West-Replication` exists with HOUSTONFS1 as primary member.

Verify:

```powershell
Get-DfsReplicationGroup -GroupName 'Houston-West-Replication'
Get-DfsrBacklog -GroupName 'Houston-West-Replication' -SourceComputerName HOUSTONFS1 -DestinationComputerName WESTFS1 -FolderName Department
```

## 18. Configure DHCP Server

Install DHCP, authorize in AD, and create a scope for the Houston subnet.

```powershell
# On HOUSTONDHCP1:
.\scripts\post-deploy\Configure-DHCP.ps1
```

Expected result: DHCP authorized, Houston-Clients scope active (10.20.1.100-200) with DNS and gateway options.

Verify:

```powershell
Get-DhcpServerInDC
Get-DhcpServerv4Scope
Get-DhcpServerv4OptionValue -ScopeId 10.20.1.0
```

## 19. Configure WSUS

Install WSUS on HOUSTONDHCP1, configure products/classifications, and create a client GPO.

```powershell
# On HOUSTONDHCP1:
.\scripts\post-deploy\Configure-WSUS.ps1
```

Expected result: WSUS running on port 8530, computer target groups created, client GPO linked.

Verify:

```powershell
Get-Service WsusService
Get-GPO -Name 'WSUS - Client Configuration'
# On a client after gpupdate /force:
reg query "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" /v WUServer
```

## 20. Configure AD CS (Enterprise Root CA)

Install an Enterprise Root CA on HOUSTONDC1, publish certificate templates, and enable LDAPS.

```powershell
# On HOUSTONDC1:
.\scripts\post-deploy\Configure-ADCS.ps1
```

Expected result: CA service running, LDAPS listening on port 636, Web Enrollment accessible.

Verify:

```powershell
certutil -ca
certutil -ping
Test-NetConnection -ComputerName HOUSTONDC1 -Port 636
```

## 21. Configure Entra Connect

Install and configure Microsoft Entra Connect for hybrid identity sync from lab.local to your Entra ID tenant.

```powershell
# On HOUSTAAC1:
.\scripts\post-deploy\Configure-EntraConnect.ps1 -TenantDomain "yourtenant.onmicrosoft.com"
```

The script installs prerequisites, downloads Entra Connect, creates test users, and guides you through the wizard configuration.

Expected result: ADSync service running, test users synced to Entra ID.

Verify:

```powershell
Get-Service ADSync
Start-ADSyncSyncCycle -PolicyType Delta
# Check Entra portal for synced users
```

