# Post-Deployment Runbook (Houston + West Forests)

Use this checklist after deploying infrastructure from `infra/main.bicep`.

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

Add conditional forwarders:

- On Houston DNS (`HOUSTONDC1`/`HOUSTONDC2`): forward `west.lab.local` to `10.30.1.10`
- On West DNS (`WESTDC1`): forward `lab.local` to `10.20.1.10` (and optionally `10.20.1.11`)

Expected result: names resolve across forests over peered VNets.

## 7. Configure bidirectional forest trust

Create a two-way forest trust between:

- `lab.local`
- `west.lab.local`

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

