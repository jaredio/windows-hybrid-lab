#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Guides installation and configuration of Microsoft Entra Connect for hybrid identity sync.

.DESCRIPTION
    Prepares the server with prerequisites (TLS 1.2, .NET Framework), installs
    Entra Connect binaries when an installer is provided, and guides interactive
    wizard-based configuration for Password Hash Sync from lab.local to Entra ID.

    Creates test users in AD to verify synchronization is working.

.PARAMETER TenantDomain
    Your Entra ID tenant domain (e.g., yourname.onmicrosoft.com). Required.

.PARAMETER SyncMethod
    Sign-on method: PasswordHashSync (default) or PassThroughAuth.

.PARAMETER OUsToSync
    Distinguished names of OUs to sync. Default syncs the entire domain.

.PARAMETER InstallerPath
    Optional local path to AzureADConnect.msi. If ADSync is not installed and
    this path is not provided, the script stops with instructions.

.EXAMPLE
    # Interactive (will prompt for Entra Global Admin and AD Enterprise Admin creds):
    .\Configure-EntraConnect.ps1 -TenantDomain "contoso.onmicrosoft.com"

    # With specific OUs:
    .\Configure-EntraConnect.ps1 -TenantDomain "contoso.onmicrosoft.com" `
        -OUsToSync @("OU=Users,DC=lab,DC=local", "OU=Groups,DC=lab,DC=local")

.NOTES
    Target VM  : HOUSTAAC1
    Prereqs    : Domain-joined to lab.local, internet access, Entra ID tenant
                 with Global Administrator credentials
    AZ-800     : Implement and manage hybrid identity / Configure Azure AD Connect
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$TenantDomain,

    [ValidateSet('PasswordHashSync', 'PassThroughAuth')]
    [string]$SyncMethod = 'PasswordHashSync',

    [string[]]$OUsToSync = @(),

    [string]$InstallerPath = ''
)

$ErrorActionPreference = "Stop"

# â”€â”€ Step 1: Prerequisites â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
Write-Host "`n[1/6] Checking prerequisites..." -ForegroundColor Cyan

# Enforce TLS 1.2 (required for Entra Connect)
$tls12Path = "HKLM:\SOFTWARE\Microsoft\.NETFramework\v4.0.30319"
$currentValue = Get-ItemProperty -Path $tls12Path -Name SchUseStrongCrypto -ErrorAction SilentlyContinue
if (-not $currentValue -or $currentValue.SchUseStrongCrypto -ne 1) {
    Set-ItemProperty -Path $tls12Path -Name SchUseStrongCrypto -Value 1 -Type DWord
    Write-Host "  Enabled TLS 1.2 for .NET Framework (SchUseStrongCrypto)."
}

# Also set for 64-bit
$tls12Path64 = "HKLM:\SOFTWARE\Wow6432Node\Microsoft\.NETFramework\v4.0.30319"
if (Test-Path $tls12Path64) {
    Set-ItemProperty -Path $tls12Path64 -Name SchUseStrongCrypto -Value 1 -Type DWord
}

# Ensure current session uses TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Write-Host "  TLS 1.2: Enabled"

# Check .NET Framework version
$netVersion = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full").Release
if ($netVersion -ge 461808) {
    Write-Host "  .NET Framework 4.7.2+: OK (release $netVersion)"
} else {
    Write-Warning ".NET Framework 4.7.2 or higher is required. Current release: $netVersion"
    Write-Host "  Install from: https://dotnet.microsoft.com/download/dotnet-framework" -ForegroundColor Yellow
}

# â”€â”€ Step 2: Locate installer (if needed) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
Write-Host "`n[2/6] Checking installer availability..." -ForegroundColor Cyan

$adSync = Get-Service ADSync -ErrorAction SilentlyContinue
if ($adSync) {
    Write-Host "  Entra Connect is already installed (ADSync service exists)."
} else {
    if ([string]::IsNullOrWhiteSpace($InstallerPath)) {
        throw "ADSync is not installed and -InstallerPath was not provided. Download AzureADConnect.msi from Entra admin center and rerun this script with -InstallerPath."
    }

    if (-not (Test-Path $InstallerPath)) {
        throw "Installer not found at path: $InstallerPath"
    }

    Write-Host "  Using installer: $InstallerPath"
}

# â”€â”€ Step 3: Install Entra Connect â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
Write-Host "`n[3/6] Installing Entra Connect binaries..." -ForegroundColor Cyan

if ($adSync) {
    Write-Host "  Skipping install because ADSync already exists."
} else {
    Write-Host "  Running MSI install..."
    $msiArgs = "/i `"$InstallerPath`" /passive /norestart"
    Start-Process msiexec.exe -ArgumentList $msiArgs -Wait
    Write-Host "  Installation complete."

    # Wait for ADSync service to appear
    $retries = 0
    while ($retries -lt 12) {
        $adSync = Get-Service ADSync -ErrorAction SilentlyContinue
        if ($adSync) { break }
        Start-Sleep -Seconds 5
        $retries++
    }

    if ($adSync) {
        Write-Host "  ADSync service detected."
    } else {
        Write-Warning "ADSync service not found after install. You may need to run the Entra Connect wizard manually."
    }
}

# â”€â”€ Step 4: Configure sync (wizard-guided) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
Write-Host "`n[4/6] Checking sync configuration state..." -ForegroundColor Cyan

# Import the ADSync module
Import-Module ADSync -ErrorAction SilentlyContinue

if (Get-Command Get-ADSyncConnector -ErrorAction SilentlyContinue) {
    # Check if already configured
    $connectors = Get-ADSyncConnector -ErrorAction SilentlyContinue
    if ($connectors) {
        Write-Host "  Entra Connect is already configured with connectors."
        Write-Host "  Connectors:" -ForegroundColor Yellow
        $connectors | Format-Table Name, Type
    } else {
        Write-Host "  ADSync module loaded but no connectors configured."
        Write-Host "  The Entra Connect wizard must be run to complete initial configuration." -ForegroundColor Yellow
    }
} else {
    Write-Host "  ADSync module not available yet." -ForegroundColor Yellow
}

# Provide wizard configuration guidance
Write-Host "`nEntra Connect wizard guidance:" -ForegroundColor Cyan
Write-Host "  If the wizard didn't run automatically, launch:" -ForegroundColor Cyan
Write-Host "  C:\Program Files\Microsoft Azure AD Sync\AzureADConnect.exe" -ForegroundColor Cyan
Write-Host "  1. Express Settings (recommended for lab)" -ForegroundColor Cyan
Write-Host "  2. Entra ID credentials: $TenantDomain" -ForegroundColor Cyan
Write-Host "  3. On-prem AD: lab.local (Enterprise Admin)" -ForegroundColor Cyan
Write-Host "  4. Sign-on method: $SyncMethod" -ForegroundColor Cyan
Write-Host "  5. Sync all domains and OUs (or filter)" -ForegroundColor Cyan
Write-Host "  6. Enable Password Hash Sync" -ForegroundColor Cyan
Write-Host "  7. Start sync when configuration completes" -ForegroundColor Cyan
Write-Host "  OU filter (optional): $($OUsToSync -join '; ')" -ForegroundColor Cyan
Write-Host "  Microsoft does not support unattended wizard configuration." -ForegroundColor Yellow
Read-Host "`nPress Enter after completing the Entra Connect wizard"

# Step 5: Create test users for sync verification
Write-Host "`n[5/6] Creating test users for sync verification..." -ForegroundColor Cyan

Import-Module ActiveDirectory -ErrorAction SilentlyContinue

$testUsers = @(
    @{ Name = 'Sync Test User 1'; SamAccountName = 'synctest1'; UPN = "synctest1@lab.local" }
    @{ Name = 'Sync Test User 2'; SamAccountName = 'synctest2'; UPN = "synctest2@lab.local" }
)

$defaultPassword = ConvertTo-SecureString 'SyncTest!2024' -AsPlainText -Force

foreach ($user in $testUsers) {
    $existing = Get-ADUser -Filter "SamAccountName -eq '$($user.SamAccountName)'" -ErrorAction SilentlyContinue
    if (-not $existing) {
        New-ADUser -Name $user.Name `
            -SamAccountName $user.SamAccountName `
            -UserPrincipalName $user.UPN `
            -AccountPassword $defaultPassword `
            -Enabled $true `
            -ChangePasswordAtLogon $false `
            -Description "Test account for Entra Connect sync verification"
        Write-Host "  Created: $($user.SamAccountName)"
    } else {
        Write-Host "  Exists: $($user.SamAccountName)"
    }
}

# Trigger sync if ADSync is configured
if (Get-Command Start-ADSyncSyncCycle -ErrorAction SilentlyContinue) {
    try {
        Start-ADSyncSyncCycle -PolicyType Delta
        Write-Host "`n  Delta sync triggered." -ForegroundColor Green
    } catch {
        Write-Host "  Could not trigger sync: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

# â”€â”€ Step 6: Validation â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
Write-Host "`n[6/6] Validation..." -ForegroundColor Cyan
Write-Host "`n--- ADSync Service ---"
Get-Service ADSync -ErrorAction SilentlyContinue | Format-Table Name, Status, DisplayName

if (Get-Command Get-ADSyncScheduler -ErrorAction SilentlyContinue) {
    Write-Host "--- Sync Schedule ---"
    Get-ADSyncScheduler | Format-List SyncCycleEnabled, NextSyncCycleStartTimeInUTC,
        CurrentlyEffectiveSyncCycleInterval
}

Write-Host "`n--- Test Users in AD ---"
Get-ADUser -Filter * -Properties Description |
    Where-Object { $_.Description -like '*Entra Connect sync*' } |
    Format-Table Name, SamAccountName, UserPrincipalName, Enabled

Write-Host "`nEntra Connect setup complete." -ForegroundColor Green
Write-Host "Verify sync in Entra portal: https://entra.microsoft.com > Users" -ForegroundColor Yellow
Write-Host "Force full sync: Start-ADSyncSyncCycle -PolicyType Initial" -ForegroundColor Yellow

