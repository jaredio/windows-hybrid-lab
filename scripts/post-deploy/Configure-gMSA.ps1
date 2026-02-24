#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Creates a KDS root key and a group Managed Service Account (gMSA) for lab.local.

.DESCRIPTION
    Sets up the infrastructure for gMSAs in lab.local:
      1. Creates the KDS root key (required before any gMSA can exist)
      2. Creates a security group for hosts allowed to retrieve the gMSA password
      3. Creates the gMSA itself
      4. Installs the gMSA on member servers (HOUSTONVM1, HOUSTONVM2)

    The gMSA password is managed automatically by AD -- no human ever sees or
    rotates it. This is the recommended approach for service accounts in
    production (replaces standalone service accounts with static passwords).

.NOTES
    Target VM  : HOUSTONDC1
    Prereqs    : lab.local domain functional level 2012 or higher
                 HOUSTONVM1 and HOUSTONVM2 are domain-joined
    AZ-800     : Choose and implement service account types (MSA, gMSA)
#>

param(
    [string]$ServiceAccountName = 'svc-WebApp',
    [string]$GroupName = 'gMSA-Hosts',
    [string[]]$MemberServers = @('HOUSTONVM1', 'HOUSTONVM2')
)

$ErrorActionPreference = "Stop"
Import-Module ActiveDirectory

# ── Step 1: Create KDS Root Key ──────────────────────────────────────
Write-Host "`n[1/5] Creating KDS root key..." -ForegroundColor Cyan

$existingKeys = Get-KdsRootKey
if ($existingKeys) {
    Write-Host "  KDS root key already exists (KeyId: $($existingKeys[0].KeyId)) -- skipping."
} else {
    # In a lab, backdate the effective time by 10 hours so the key is
    # immediately usable. In production, use Add-KdsRootKey -EffectiveImmediately
    # and wait 10 hours for replication to all DCs before creating gMSAs.
    Add-KdsRootKey -EffectiveTime ((Get-Date).AddHours(-10))
    Write-Host "  KDS root key created (backdated for lab use)."
    Write-Host "  NOTE: In production, allow 10 hours for replication before creating gMSAs." -ForegroundColor Yellow
}

# ── Step 2: Create host group ────────────────────────────────────────
Write-Host "`n[2/5] Creating security group '$GroupName'..." -ForegroundColor Cyan
try {
    New-ADGroup -Name $GroupName `
        -GroupScope Global `
        -GroupCategory Security `
        -Path "CN=Users,DC=lab,DC=local" `
        -Description "Hosts allowed to retrieve gMSA passwords"
    Write-Host "  Created group: $GroupName"
} catch {
    if ($_.Exception.Message -match "already exists") {
        Write-Host "  Group $GroupName already exists -- skipping."
    } else { throw }
}

# ── Step 3: Add member servers to the group ──────────────────────────
Write-Host "`n[3/5] Adding member servers to $GroupName..." -ForegroundColor Cyan
foreach ($server in $MemberServers) {
    try {
        $computer = Get-ADComputer -Identity $server
        Add-ADGroupMember -Identity $GroupName -Members $computer
        Write-Host "  Added $server"
    } catch {
        if ($_.Exception.Message -match "already a member") {
            Write-Host "  $server is already a member -- skipping."
        } else { throw }
    }
}

# IMPORTANT: Member servers must reboot (or wait for Kerberos ticket refresh)
# after being added to the group, so they receive the new group membership
# in their Kerberos token before they can retrieve the gMSA password.
Write-Host "`n  IMPORTANT: Reboot $($MemberServers -join ', ') before step 5" -ForegroundColor Yellow
Write-Host "  so they pick up the new group membership in their Kerberos token."

# ── Step 4: Create the gMSA ─────────────────────────────────────────
Write-Host "`n[4/5] Creating gMSA '$ServiceAccountName'..." -ForegroundColor Cyan
$dnsHostName = "$ServiceAccountName.lab.local"

try {
    New-ADServiceAccount -Name $ServiceAccountName `
        -DNSHostName $dnsHostName `
        -PrincipalsAllowedToRetrieveManagedPassword $GroupName `
        -KerberosEncryptionType AES128, AES256 `
        -Enabled $true
    Write-Host "  Created gMSA: $ServiceAccountName ($dnsHostName)"
} catch {
    if ($_.Exception.Message -match "already exists") {
        Write-Host "  gMSA $ServiceAccountName already exists -- skipping."
    } else { throw }
}

# ── Step 5: Install and test on member servers ───────────────────────
Write-Host "`n[5/5] Installing gMSA on member servers..." -ForegroundColor Cyan
Write-Host "  (Run these commands on each member server after rebooting)`n"

foreach ($server in $MemberServers) {
    Write-Host "  --- $server ---" -ForegroundColor Cyan
    try {
        Invoke-Command -ComputerName $server -ScriptBlock {
            param($Name)
            Install-ADServiceAccount -Identity $Name
            $result = Test-ADServiceAccount -Identity $Name
            if ($result) {
                Write-Host "    gMSA '$Name' installed and verified successfully." -ForegroundColor Green
            } else {
                Write-Host "    gMSA '$Name' installed but test FAILED." -ForegroundColor Red
                Write-Host "    Did you reboot after adding this server to the gMSA group?"
            }
        } -ArgumentList $ServiceAccountName
    } catch {
        Write-Host "    Could not connect to $server -- install manually:" -ForegroundColor Yellow
        Write-Host "    Install-ADServiceAccount -Identity $ServiceAccountName"
        Write-Host "    Test-ADServiceAccount -Identity $ServiceAccountName"
    }
}

# ── Validation ───────────────────────────────────────────────────────
Write-Host "`n=== gMSA Summary ===" -ForegroundColor Green
Get-ADServiceAccount -Identity $ServiceAccountName -Properties * |
    Select-Object Name, DNSHostName, Enabled, KerberosEncryptionType,
        PrincipalsAllowedToRetrieveManagedPassword, Created |
    Format-List

# ── Using the gMSA with a Windows service ────────────────────────────
<#
  To configure a Windows service to run as this gMSA:

  # On the member server (HOUSTONVM1 or HOUSTONVM2):
  $cred = New-Object System.Management.Automation.PSCredential("LAB\svc-WebApp$", (New-Object SecureString))
  Set-Service -Name "SomeService" -Credential $cred

  # Or via sc.exe:
  sc.exe config "SomeService" obj= "LAB\svc-WebApp$" password= ""

  The trailing $ in the account name is required -- it tells Windows this
  is a managed service account, not a regular user.
#>
