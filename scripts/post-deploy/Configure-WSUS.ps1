#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Installs and configures Windows Server Update Services (WSUS).

.DESCRIPTION
    Installs the WSUS role with Windows Internal Database, runs post-install
    configuration, sets update source and product categories, creates computer
    target groups, and optionally creates a GPO to point clients to this WSUS server.

.PARAMETER ContentPath
    Local path for WSUS update storage (default: C:\WSUS).

.PARAMETER WsusPort
    HTTP port for WSUS (default: 8530).

.EXAMPLE
    .\Configure-WSUS.ps1

.NOTES
    Target VM  : HOUSTONDHCP1 (co-located with DHCP)
    Prereqs    : Domain-joined to lab.local, internet access for initial sync
    AZ-800     : Deploy and configure WSUS / Configure Group Policy for updates
#>

param(
    [string]$ContentPath = 'C:\WSUS',
    [int]$WsusPort       = 8530
)

$ErrorActionPreference = "Stop"

# ── Step 1: Install WSUS role ─────────────────────────────────────────
Write-Host "`n[1/6] Installing WSUS role..." -ForegroundColor Cyan

$wsus = Get-WindowsFeature -Name UpdateServices
if (-not $wsus.Installed) {
    Install-WindowsFeature UpdateServices -IncludeManagementTools | Out-Null
    Write-Host "  Installed WSUS with management tools."
} else {
    Write-Host "  WSUS role already installed."
}

# Also install the SQL tools for WID
$wsusDb = Get-WindowsFeature -Name UpdateServices-WidDB
if (-not $wsusDb.Installed) {
    Install-WindowsFeature UpdateServices-WidDB | Out-Null
    Write-Host "  Installed Windows Internal Database for WSUS."
}

# ── Step 2: Run post-install configuration ────────────────────────────
Write-Host "`n[2/6] Running WSUS post-install configuration..." -ForegroundColor Cyan

if (-not (Test-Path $ContentPath)) {
    New-Item -Path $ContentPath -ItemType Directory -Force | Out-Null
    Write-Host "  Created content directory: $ContentPath"
}

$wsusUtil = "$env:ProgramFiles\Update Services\Tools\wsusutil.exe"
if (Test-Path $wsusUtil) {
    $result = & $wsusUtil postinstall CONTENT_DIR=$ContentPath 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  Post-install completed successfully."
    } else {
        Write-Host "  Post-install output: $result" -ForegroundColor Yellow
    }
} else {
    Write-Warning "wsusutil.exe not found at expected path. WSUS may need manual post-install."
}

# ── Step 3: Configure WSUS server settings ────────────────────────────
Write-Host "`n[3/6] Configuring WSUS server settings..." -ForegroundColor Cyan

# Load WSUS administration assembly
[reflection.assembly]::LoadWithPartialName("Microsoft.UpdateServices.Administration") | Out-Null
$wsusServer = [Microsoft.UpdateServices.Administration.AdminProxy]::GetUpdateServer($env:COMPUTERNAME, $false, $WsusPort)

# Set update source to Microsoft Update
$config = $wsusServer.GetConfiguration()
$config.SyncFromMicrosoftUpdate = $true
$config.Save()
Write-Host "  Update source: Microsoft Update"

# ── Step 4: Configure products and classifications ────────────────────
Write-Host "`n[4/6] Setting product categories and classifications..." -ForegroundColor Cyan

$subscription = $wsusServer.GetSubscription()

# Enable Windows Server 2022
$allProducts = $wsusServer.GetUpdateCategories()
$server2022 = $allProducts | Where-Object { $_.Title -match "Windows Server 2022" }
if ($server2022) {
    $productCollection = New-Object Microsoft.UpdateServices.Administration.UpdateCategoryCollection
    foreach ($product in $server2022) {
        $productCollection.Add($product) | Out-Null
    }
    $subscription.SetUpdateCategories($productCollection)
    Write-Host "  Enabled product: Windows Server 2022"
} else {
    Write-Warning "Could not find 'Windows Server 2022' in WSUS product categories."
}

# Enable Critical Updates and Security Updates classifications
$allClassifications = $wsusServer.GetUpdateClassifications()
$targetClassifications = $allClassifications | Where-Object {
    $_.Title -in @('Critical Updates', 'Security Updates', 'Definition Updates')
}
$classCollection = New-Object Microsoft.UpdateServices.Administration.UpdateClassificationCollection
foreach ($cls in $targetClassifications) {
    $classCollection.Add($cls) | Out-Null
    Write-Host "  Enabled classification: $($cls.Title)"
}
$subscription.SetUpdateClassifications($classCollection)
$subscription.Save()

# ── Step 5: Create computer target groups ─────────────────────────────
Write-Host "`n[5/6] Creating computer target groups..." -ForegroundColor Cyan

$groups = @('DomainControllers', 'MemberServers', 'FileServers')
foreach ($groupName in $groups) {
    $existing = $wsusServer.GetComputerTargetGroups() | Where-Object { $_.Name -eq $groupName }
    if (-not $existing) {
        $wsusServer.CreateComputerTargetGroup($groupName) | Out-Null
        Write-Host "  Created group: $groupName"
    } else {
        Write-Host "  Group exists: $groupName"
    }
}

# ── Step 6: Create WSUS client GPO ────────────────────────────────────
Write-Host "`n[6/6] Creating WSUS client GPO..." -ForegroundColor Cyan

Import-Module GroupPolicy -ErrorAction SilentlyContinue

$gpoName = "WSUS - Client Configuration"
$domainDN = "DC=lab,DC=local"
$wsusUrl = "http://$env:COMPUTERNAME`:$WsusPort"

$existingGpo = Get-GPO -Name $gpoName -ErrorAction SilentlyContinue
if (-not $existingGpo) {
    $gpo = New-GPO -Name $gpoName -Comment "Point Windows Update clients to internal WSUS server"
    $gpo | New-GPLink -Target $domainDN | Out-Null
    Write-Host "  Created and linked: $gpoName"
} else {
    Write-Host "  GPO '$gpoName' already exists."
}

# Configure Automatic Updates via GPO registry
$auKey = "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
$wuKey = "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"

# Point to WSUS server
Set-GPRegistryValue -Name $gpoName -Key $wuKey -ValueName "WUServer" -Type String -Value $wsusUrl | Out-Null
Set-GPRegistryValue -Name $gpoName -Key $wuKey -ValueName "WUStatusServer" -Type String -Value $wsusUrl | Out-Null
Write-Host "  WSUS URL: $wsusUrl"

# Enable automatic updates (4 = Auto download and schedule install)
Set-GPRegistryValue -Name $gpoName -Key $auKey -ValueName "NoAutoUpdate" -Type DWord -Value 0 | Out-Null
Set-GPRegistryValue -Name $gpoName -Key $auKey -ValueName "AUOptions" -Type DWord -Value 4 | Out-Null
Set-GPRegistryValue -Name $gpoName -Key $auKey -ValueName "UseWUServer" -Type DWord -Value 1 | Out-Null
Write-Host "  Auto-update policy: Download and schedule install"

# Enable client-side targeting
Set-GPRegistryValue -Name $gpoName -Key $wuKey -ValueName "TargetGroupEnabled" -Type DWord -Value 1 | Out-Null
Write-Host "  Client-side targeting: Enabled"

# ── Validation ─────────────────────────────────────────────────────────
Write-Host "`n--- WSUS Server Info ---"
Write-Host "  Server: $env:COMPUTERNAME`:$WsusPort"
Write-Host "  Content: $ContentPath"

Write-Host "`n--- Computer Target Groups ---"
$wsusServer.GetComputerTargetGroups() | Format-Table Name

Write-Host "`nWSUS configuration complete." -ForegroundColor Green
Write-Host "Trigger initial sync: `$subscription.StartSynchronization()" -ForegroundColor Yellow
Write-Host "On clients, run: gpupdate /force && wuauclt /detectnow" -ForegroundColor Yellow
