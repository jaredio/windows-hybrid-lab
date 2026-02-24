#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Creates and links security baseline GPOs for lab.local.

.DESCRIPTION
    Creates four Group Policy Objects that establish a basic security baseline:
      1. Password and account lockout policy
      2. Audit policy for security event logging
      3. Windows Firewall baseline (all profiles enabled)
      4. Disable SMBv1 (legacy protocol hardening)

    Each GPO is created, configured, and linked to the domain root.

.NOTES
    Target VM  : HOUSTONDC1
    Prereqs    : lab.local domain operational, GPMC available
    AZ-800     : Implement Group Policy Objects in AD DS / Group Policy Preferences
#>

$ErrorActionPreference = "Stop"

# ── Step 0: Ensure GPMC is installed ─────────────────────────────────
Write-Host "`n[0/5] Checking for Group Policy Management feature..." -ForegroundColor Cyan
$gpmc = Get-WindowsFeature -Name GPMC
if (-not $gpmc.Installed) {
    Install-WindowsFeature GPMC -IncludeManagementTools
    Write-Host "  Installed GPMC."
} else {
    Write-Host "  GPMC already installed."
}

Import-Module GroupPolicy

$domainDN = "DC=lab,DC=local"

# ═════════════════════════════════════════════════════════════════════
# GPO 1: Password and Account Lockout Policy
# ═════════════════════════════════════════════════════════════════════
Write-Host "`n[1/5] Configuring domain password and lockout policy..." -ForegroundColor Cyan

# Domain password policy is set via Default Domain Policy or Set-ADDefaultDomainPasswordPolicy.
# This is the correct way -- GPO registry hacks don't apply to domain password policy.
Set-ADDefaultDomainPasswordPolicy -Identity "lab.local" `
    -MinPasswordLength 12 `
    -PasswordHistoryCount 24 `
    -MaxPasswordAge (New-TimeSpan -Days 90) `
    -MinPasswordAge (New-TimeSpan -Days 1) `
    -ComplexityEnabled $true `
    -LockoutThreshold 5 `
    -LockoutDuration (New-TimeSpan -Minutes 30) `
    -LockoutObservationWindow (New-TimeSpan -Minutes 30)

Write-Host "  Domain password policy configured:"
Write-Host "    Min length:       12"
Write-Host "    History:          24"
Write-Host "    Max age:          90 days"
Write-Host "    Complexity:       Enabled"
Write-Host "    Lockout:          5 attempts / 30 min window / 30 min duration"

# ═════════════════════════════════════════════════════════════════════
# GPO 2: Audit Policy
# ═════════════════════════════════════════════════════════════════════
Write-Host "`n[2/5] Creating audit policy GPO..." -ForegroundColor Cyan

$auditGpo = Get-GPO -Name "SEC - Audit Policy" -ErrorAction SilentlyContinue
if (-not $auditGpo) {
    $auditGpo = New-GPO -Name "SEC - Audit Policy" -Comment "Enable security auditing for key event categories"
    $auditGpo | New-GPLink -Target $domainDN | Out-Null
    Write-Host "  Created and linked: SEC - Audit Policy"
} else {
    Write-Host "  GPO 'SEC - Audit Policy' already exists -- updating settings."
}

# Configure advanced audit policy via registry (Computer Configuration > Policies >
# Windows Settings > Security Settings > Advanced Audit Policy Configuration)
$auditCategories = @(
    @{ Key = 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Audit'; ValueName = 'ProcessCreationIncludeCmdLine_Enabled'; Type = 'DWord'; Value = 1 }
)
foreach ($entry in $auditCategories) {
    Set-GPRegistryValue -Name $auditGpo.DisplayName `
        -Key $entry.Key `
        -ValueName $entry.ValueName `
        -Type $entry.Type `
        -Value $entry.Value | Out-Null
}

# Enable classic audit categories via auditpol (more reliable for advanced audit)
# These are applied as a startup script or can be pushed via the GPO above
Write-Host "  Configuring audit categories via auditpol..."
auditpol /set /category:"Account Logon" /success:enable /failure:enable
auditpol /set /category:"Logon/Logoff" /success:enable /failure:enable
auditpol /set /category:"Object Access" /success:enable /failure:enable
auditpol /set /category:"Policy Change" /success:enable /failure:enable
auditpol /set /category:"Account Management" /success:enable /failure:enable
Write-Host "  Audit categories enabled: Account Logon, Logon/Logoff, Object Access, Policy Change, Account Management"

# ═════════════════════════════════════════════════════════════════════
# GPO 3: Windows Firewall Baseline
# ═════════════════════════════════════════════════════════════════════
Write-Host "`n[3/5] Creating firewall baseline GPO..." -ForegroundColor Cyan

$fwGpo = Get-GPO -Name "SEC - Firewall Baseline" -ErrorAction SilentlyContinue
if (-not $fwGpo) {
    $fwGpo = New-GPO -Name "SEC - Firewall Baseline" -Comment "Enable Windows Firewall on all profiles"
    $fwGpo | New-GPLink -Target $domainDN | Out-Null
    Write-Host "  Created and linked: SEC - Firewall Baseline"
} else {
    Write-Host "  GPO 'SEC - Firewall Baseline' already exists -- updating settings."
}

# Enable firewall for Domain, Private, and Public profiles
$firewallKeys = @(
    @{ Profile = 'DomainProfile'; Key = 'HKLM\SOFTWARE\Policies\Microsoft\WindowsFirewall\DomainProfile'; ValueName = 'EnableFirewall'; Value = 1 }
    @{ Profile = 'StandardProfile'; Key = 'HKLM\SOFTWARE\Policies\Microsoft\WindowsFirewall\StandardProfile'; ValueName = 'EnableFirewall'; Value = 1 }
    @{ Profile = 'PublicProfile'; Key = 'HKLM\SOFTWARE\Policies\Microsoft\WindowsFirewall\PublicProfile'; ValueName = 'EnableFirewall'; Value = 1 }
)
foreach ($fw in $firewallKeys) {
    Set-GPRegistryValue -Name $fwGpo.DisplayName `
        -Key $fw.Key `
        -ValueName $fw.ValueName `
        -Type DWord `
        -Value $fw.Value | Out-Null
    Write-Host "  Enabled firewall: $($fw.Profile)"
}

# ═════════════════════════════════════════════════════════════════════
# GPO 4: Disable SMBv1
# ═════════════════════════════════════════════════════════════════════
Write-Host "`n[4/5] Creating SMBv1 disable GPO..." -ForegroundColor Cyan

$smbGpo = Get-GPO -Name "SEC - Disable SMBv1" -ErrorAction SilentlyContinue
if (-not $smbGpo) {
    $smbGpo = New-GPO -Name "SEC - Disable SMBv1" -Comment "Disable SMBv1 server and client (legacy protocol hardening)"
    $smbGpo | New-GPLink -Target $domainDN | Out-Null
    Write-Host "  Created and linked: SEC - Disable SMBv1"
} else {
    Write-Host "  GPO 'SEC - Disable SMBv1' already exists -- updating settings."
}

# Disable SMBv1 server
Set-GPRegistryValue -Name $smbGpo.DisplayName `
    -Key "HKLM\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" `
    -ValueName "SMB1" `
    -Type DWord `
    -Value 0 | Out-Null
Write-Host "  Disabled SMBv1 server component."

# Disable SMBv1 client
Set-GPRegistryValue -Name $smbGpo.DisplayName `
    -Key "HKLM\SYSTEM\CurrentControlSet\Services\mrxsmb10" `
    -ValueName "Start" `
    -Type DWord `
    -Value 4 | Out-Null
Write-Host "  Disabled SMBv1 client component (mrxsmb10 set to disabled)."

# ═════════════════════════════════════════════════════════════════════
# Validation
# ═════════════════════════════════════════════════════════════════════
Write-Host "`n[5/5] Validation..." -ForegroundColor Cyan

Write-Host "`n--- All GPOs ---"
Get-GPO -All | Format-Table DisplayName, GpoStatus, CreationTime

Write-Host "--- GPO Inheritance at Domain Root ---"
Get-GPInheritance -Target $domainDN | Select-Object -ExpandProperty GpoLinks |
    Format-Table DisplayName, Enabled, Enforced, Order

Write-Host "--- Domain Password Policy ---"
Get-ADDefaultDomainPasswordPolicy -Identity "lab.local" |
    Select-Object MinPasswordLength, PasswordHistoryCount, MaxPasswordAge,
        ComplexityEnabled, LockoutThreshold, LockoutDuration |
    Format-List

Write-Host "GPO configuration complete." -ForegroundColor Green
Write-Host "Run 'gpresult /r' on a member server to verify applied policies." -ForegroundColor Yellow
