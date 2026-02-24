#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Promotes HOUSTONDC2 as a Read-Only Domain Controller (RODC) for lab.local.

.DESCRIPTION
    Run this script on HOUSTONDC2 after HOUSTONDC1 has been promoted as the
    first writable DC for lab.local (post-deploy-checklist section 1).

    If HOUSTONDC2 was already promoted as a writable replica (section 3),
    you must demote it first -- see the demotion section at the bottom of
    this script.

    The script installs the AD DS and DNS roles, creates a Password
    Replication Policy group on the domain, and promotes HOUSTONDC2 as an
    RODC with DNS installed.

.NOTES
    Target VM  : HOUSTONDC2
    Prereqs    : HOUSTONDC1 is a writable DC for lab.local
                 HOUSTONDC2 DNS client points to 10.20.1.10
                 HOUSTONDC2 is domain-joined to lab.local (but NOT a DC)
    AZ-800     : Deploy and manage domain controllers / RODC deployment
#>

param(
    [string]$DomainName = 'lab.local',
    [string]$SiteName   = 'Houston'
)

$ErrorActionPreference = "Stop"

# ── Step 1: Install AD DS and DNS features ───────────────────────────
Write-Host "`n[1/5] Installing AD-Domain-Services and DNS features..." -ForegroundColor Cyan
Install-WindowsFeature AD-Domain-Services, DNS -IncludeManagementTools

# ── Step 2: Collect credentials ──────────────────────────────────────
Write-Host "`n[2/5] Collecting credentials..." -ForegroundColor Cyan
$domainCred = Get-Credential -Message "Enter domain admin credentials (LAB\labadmin)"
$dsrmPassword = Read-Host -AsSecureString -Prompt "Enter DSRM (Directory Services Restore Mode) password"

# ── Step 3: Create RODC password replication group on the domain ─────
Write-Host "`n[3/5] Creating RODC password replication group on the domain..." -ForegroundColor Cyan
$session = New-PSSession -ComputerName HOUSTONDC1 -Credential $domainCred
Invoke-Command -Session $session -ScriptBlock {
    Import-Module ActiveDirectory
    if (-not (Get-ADGroup -Filter 'Name -eq "RODC-Allowed-Replication"' -ErrorAction SilentlyContinue)) {
        New-ADGroup -Name "RODC-Allowed-Replication" `
            -GroupScope Global `
            -GroupCategory Security `
            -Path "CN=Users,DC=lab,DC=local" `
            -Description "Accounts whose passwords can be cached on the RODC"
        Write-Host "  Created group: RODC-Allowed-Replication"
    } else {
        Write-Host "  Group RODC-Allowed-Replication already exists -- skipping."
    }
}
Remove-PSSession $session

# ── Step 4: Promote as RODC ──────────────────────────────────────────
Write-Host "`n[4/5] Promoting $env:COMPUTERNAME as RODC for $DomainName..." -ForegroundColor Cyan
Import-Module ADDSDeployment
Install-ADDSDomainController `
    -DomainName $DomainName `
    -ReadOnlyReplica `
    -SiteName $SiteName `
    -InstallDns `
    -Credential $domainCred `
    -SafeModeAdministratorPassword $dsrmPassword `
    -DenyPasswordReplicationAccountName @(
        "BUILTIN\Administrators",
        "BUILTIN\Server Operators",
        "BUILTIN\Backup Operators",
        "BUILTIN\Account Operators",
        "$DomainName\Denied RODC Password Replication Group"
    ) `
    -AllowPasswordReplicationAccountName @(
        "$DomainName\RODC-Allowed-Replication",
        "$DomainName\Allowed RODC Password Replication Group"
    ) `
    -NoGlobalCatalog:$false `
    -Force

# Server will reboot after promotion.

# ── Step 5: Post-reboot validation (run manually after reboot) ───────
<#
  After the reboot, open an elevated PowerShell prompt and run:

  # Verify RODC appears in the domain
  Get-ADDomainController -Filter * | Format-Table Name, IsReadOnly, Site

  # Check replication health
  repadmin /showrepl

  # Review Password Replication Policy
  Get-ADDomainControllerPasswordReplicationPolicy -Identity HOUSTONDC2 -Allowed
  Get-ADDomainControllerPasswordReplicationPolicy -Identity HOUSTONDC2 -Denied

  # Test password caching (after adding a user to RODC-Allowed-Replication)
  Get-ADDomainControllerPasswordReplicationPolicyUsage -Identity HOUSTONDC2 -RevealedAccounts
#>

# ── Demotion (if you need to switch back to writable) ────────────────
<#
  If HOUSTONDC2 is currently a writable replica and you want to demote it
  before re-promoting as RODC, run this on HOUSTONDC2:

  Uninstall-ADDSDomainController `
      -Credential (Get-Credential) `
      -DemoteOperationMasterRole `
      -RemoveApplicationPartitions `
      -Force

  Then clean up metadata on HOUSTONDC1 if needed:

  # On HOUSTONDC1:
  Get-ADDomainController -Identity HOUSTONDC2 | Remove-ADDomainControllerClonableAllowedList
  # Or use ntdsutil → metadata cleanup if the object persists

  After demotion completes and HOUSTONDC2 reboots, re-run this script.
#>
