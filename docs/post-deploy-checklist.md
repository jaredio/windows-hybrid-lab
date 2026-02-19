# Post-Deployment Runbook (AD DS, DNS, DHCP, Domain Join)

Use this checklist after infrastructure deployment to complete the Windows services layer of the lab.

## 1. Promote Domain Controller 1 (`*-dc1`)

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

Expected result: server reboots and becomes the first domain controller.

## 2. Validate and Configure DNS

On `dc1`:

```powershell
Get-DnsServerZone
Add-DnsServerPrimaryZone -NetworkId "10.20.1.0/24" -ReplicationScope Forest
```

Expected result: forward zone for `lab.local` and reverse zone for the subnet.

## 3. Join and Promote Domain Controller 2 (`*-dc2`)

1. Set DNS client on `dc2` to `dc1` private IP.
2. Join `dc2` to `lab.local`.
3. Promote `dc2` as an additional domain controller.

Expected result: redundant AD DS and DNS capability.

## 4. Configure DHCP

On `dc1` (or a dedicated DHCP server):

```powershell
Install-WindowsFeature DHCP -IncludeManagementTools
Add-DhcpServerInDC -DnsName "<dc1-fqdn>" -IPAddress 10.20.1.10
Add-DhcpServerv4Scope -Name "LabScope" -StartRange 10.20.1.100 -EndRange 10.20.1.200 -SubnetMask 255.255.255.0
Set-DhcpServerv4OptionValue -DnsServer 10.20.1.10 -Router 10.20.1.1 -DnsDomain "lab.local"
```

Expected result: dynamic addressing is available for domain clients.

## 5. Join Client (`*-cl1`) to the Domain

Set DNS to `dc1` private IP, then run:

```powershell
Add-Computer -DomainName "lab.local" -Credential "LAB\Administrator" -Restart
```

Expected result: client authenticates against AD and appears in AD Computers.

## 6. Test Group Policy Processing

Create/link a test GPO and validate on `cl1`:

```powershell
gpupdate /force
gpresult /r
```

Expected result: policy applies successfully.

## 7. Capture Evidence for Portfolio

- Screenshot AD Users and Computers showing domain objects
- Screenshot DHCP scope and active leases
- Screenshot DNS forward and reverse zones
- Screenshot `gpresult /r` on client
- Export deployment outputs from Azure CLI for reproducibility
