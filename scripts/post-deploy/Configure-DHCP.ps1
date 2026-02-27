#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Installs and configures DHCP Server with a Houston subnet scope.

.DESCRIPTION
    Installs the DHCP Server role, authorizes it in Active Directory, creates
    an IPv4 scope for the Houston subnet with DNS and gateway options, and
    adds reservations for existing lab VMs.

    Note: Lab VMs use static IPs configured in Bicep. This DHCP scope
    demonstrates the skill and provides addresses for any additional VMs
    or test clients added to the subnet.

.PARAMETER ScopeName
    Display name for the DHCP scope (default: Houston-Clients).

.PARAMETER StartRange
    First IP in the DHCP range (default: 10.20.1.100).

.PARAMETER EndRange
    Last IP in the DHCP range (default: 10.20.1.200).

.EXAMPLE
    .\Configure-DHCP.ps1

.NOTES
    Target VM  : HOUSTONDHCP1
    Prereqs    : Domain-joined to lab.local, DNS operational
    AZ-800     : Deploy and configure DHCP
#>

param(
    [string]$ScopeName   = 'Houston-Clients',
    [string]$StartRange  = '10.20.1.100',
    [string]$EndRange    = '10.20.1.200',
    [string]$SubnetMask  = '255.255.255.0',
    [string]$Gateway     = '10.20.1.1',
    [string[]]$DnsServers = @('10.20.1.10', '10.20.1.11'),
    [string]$DomainName  = 'lab.local'
)

$ErrorActionPreference = "Stop"

# ── Step 1: Install DHCP Server role ──────────────────────────────────
Write-Host "`n[1/5] Installing DHCP Server role..." -ForegroundColor Cyan

$dhcp = Get-WindowsFeature -Name DHCP
if (-not $dhcp.Installed) {
    Install-WindowsFeature DHCP -IncludeManagementTools | Out-Null
    Write-Host "  Installed DHCP Server role."
} else {
    Write-Host "  DHCP Server role already installed."
}

# Complete post-install configuration (creates security groups)
$postInstall = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\ServerManager\Roles\12" -Name ConfigurationState -ErrorAction SilentlyContinue
if ($postInstall -and $postInstall.ConfigurationState -ne 2) {
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\ServerManager\Roles\12" -Name ConfigurationState -Value 2
    Write-Host "  Completed DHCP post-install configuration."
}

# Add DHCP security groups if they don't exist
try {
    netsh dhcp add securitygroups 2>&1 | Out-Null
} catch { }
Restart-Service dhcpserver -ErrorAction SilentlyContinue

# ── Step 2: Authorize DHCP in Active Directory ────────────────────────
Write-Host "`n[2/5] Authorizing DHCP server in Active Directory..." -ForegroundColor Cyan

$serverIP = (Get-NetIPAddress -InterfaceAlias Ethernet -AddressFamily IPv4).IPAddress
$authorized = Get-DhcpServerInDC | Where-Object { $_.IPAddress -eq $serverIP }
if (-not $authorized) {
    Add-DhcpServerInDC -DnsName "$env:COMPUTERNAME.$DomainName" -IPAddress $serverIP
    Write-Host "  Authorized: $env:COMPUTERNAME ($serverIP)"
} else {
    Write-Host "  Already authorized in AD."
}

# ── Step 3: Create IPv4 scope ─────────────────────────────────────────
Write-Host "`n[3/5] Creating DHCP scope..." -ForegroundColor Cyan

$existingScope = Get-DhcpServerv4Scope -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $ScopeName }
if (-not $existingScope) {
    Add-DhcpServerv4Scope -Name $ScopeName `
        -StartRange $StartRange `
        -EndRange $EndRange `
        -SubnetMask $SubnetMask `
        -LeaseDuration (New-TimeSpan -Days 8) `
        -State Active `
        -Description "Houston subnet DHCP range"
    Write-Host "  Created scope: $ScopeName ($StartRange - $EndRange)"
} else {
    Write-Host "  Scope '$ScopeName' already exists."
}

# ── Step 4: Set scope options ─────────────────────────────────────────
Write-Host "`n[4/5] Configuring scope options..." -ForegroundColor Cyan

$scopeId = (Get-DhcpServerv4Scope | Where-Object { $_.Name -eq $ScopeName }).ScopeId

# DNS servers
Set-DhcpServerv4OptionValue -ScopeId $scopeId -OptionId 6 -Value $DnsServers
Write-Host "  Option 006 (DNS Servers): $($DnsServers -join ', ')"

# Domain name
Set-DhcpServerv4OptionValue -ScopeId $scopeId -OptionId 15 -Value $DomainName
Write-Host "  Option 015 (Domain Name): $DomainName"

# Default gateway
Set-DhcpServerv4OptionValue -ScopeId $scopeId -OptionId 3 -Value $Gateway
Write-Host "  Option 003 (Router/Gateway): $Gateway"

# ── Step 5: Validation ────────────────────────────────────────────────
Write-Host "`n[5/5] Validation..." -ForegroundColor Cyan

Write-Host "`n--- Authorized DHCP Servers ---"
Get-DhcpServerInDC | Format-Table DnsName, IPAddress

Write-Host "--- DHCP Scopes ---"
Get-DhcpServerv4Scope | Format-Table ScopeId, Name, StartRange, EndRange, State

Write-Host "--- Scope Options ---"
Get-DhcpServerv4OptionValue -ScopeId $scopeId |
    Format-Table OptionId, Name, Value

Write-Host "--- DHCP Server Statistics ---"
Get-DhcpServerv4Statistics

Write-Host "`nDHCP configuration complete." -ForegroundColor Green
Write-Host "Test with: Get-DhcpServerv4Lease -ScopeId $scopeId" -ForegroundColor Yellow
