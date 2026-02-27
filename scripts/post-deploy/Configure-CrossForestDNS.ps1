#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Configures conditional DNS forwarders for cross-forest name resolution.

.DESCRIPTION
    Detects which forest the current DC belongs to and creates a conditional
    forwarder zone pointing to the other forest's DNS server. This enables
    name resolution across peered VNets without modifying root hints.

    Run this script on HOUSTONDC1 first, then on WESTDC1.

.PARAMETER HoustonDcIp
    IP address of the Houston primary DC (DNS server for lab.local).

.PARAMETER WestDcIp
    IP address of the West primary DC (DNS server for west.lab.local).

.PARAMETER HoustonDomain
    FQDN of the Houston forest root domain.

.PARAMETER WestDomain
    FQDN of the West forest root domain.

.EXAMPLE
    # On HOUSTONDC1 -- creates forwarder for west.lab.local → 10.30.1.10
    .\Configure-CrossForestDNS.ps1

    # On WESTDC1 -- creates forwarder for lab.local → 10.20.1.10
    .\Configure-CrossForestDNS.ps1

    # Custom IPs:
    .\Configure-CrossForestDNS.ps1 -HoustonDcIp 10.20.1.10 -WestDcIp 10.30.1.10

.NOTES
    Target VM  : HOUSTONDC1, then WESTDC1
    Prereqs    : Both forests promoted, DNS role installed, VNet peering active
    AZ-800     : Configure DNS for Active Directory / Conditional forwarders
#>

param(
    [string]$HoustonDcIp    = '10.20.1.10',
    [string]$WestDcIp       = '10.30.1.10',
    [string]$HoustonDomain  = 'lab.local',
    [string]$WestDomain     = 'west.lab.local'
)

$ErrorActionPreference = "Stop"

# ── Detect current forest ──────────────────────────────────────────────
Write-Host "`n[1/3] Detecting current forest..." -ForegroundColor Cyan

$currentDomain = (Get-ADDomain).DNSRoot

if ($currentDomain -eq $HoustonDomain) {
    $targetDomain   = $WestDomain
    $targetServers  = @($WestDcIp)
    Write-Host "  Current forest: $HoustonDomain (Houston)"
    Write-Host "  Will create forwarder for: $targetDomain → $($targetServers -join ', ')"
}
elseif ($currentDomain -eq $WestDomain) {
    $targetDomain   = $HoustonDomain
    $targetServers  = @($HoustonDcIp)
    Write-Host "  Current forest: $WestDomain (West)"
    Write-Host "  Will create forwarder for: $targetDomain → $($targetServers -join ', ')"
}
else {
    Write-Error "Current domain '$currentDomain' does not match Houston ($HoustonDomain) or West ($WestDomain). Exiting."
}

# ── Create conditional forwarder ───────────────────────────────────────
Write-Host "`n[2/3] Creating conditional forwarder zone..." -ForegroundColor Cyan

$existingZone = Get-DnsServerZone -Name $targetDomain -ErrorAction SilentlyContinue
if ($existingZone) {
    Write-Host "  Conditional forwarder zone '$targetDomain' already exists -- skipping creation."
    Write-Host "  Master servers: $($existingZone.MasterServers -join ', ')"
} else {
    Add-DnsServerConditionalForwarderZone `
        -Name $targetDomain `
        -MasterServers $targetServers `
        -ReplicationScope Forest `
        -PassThru | Out-Null
    Write-Host "  Created conditional forwarder: $targetDomain → $($targetServers -join ', ')"
    Write-Host "  Replication scope: Forest (all DCs in this forest)"
}

# ── Validate ───────────────────────────────────────────────────────────
Write-Host "`n[3/3] Validation..." -ForegroundColor Cyan

Write-Host "`n--- Conditional Forwarder Zones ---"
Get-DnsServerZone | Where-Object { $_.ZoneType -eq 'Forwarder' } |
    Format-Table ZoneName, MasterServers, ZoneType

Write-Host "--- Cross-Forest Resolution Test ---"
try {
    $result = Resolve-DnsName -Name $targetDomain -Type SOA -ErrorAction Stop
    Write-Host "  SOA lookup for $targetDomain`: SUCCESS" -ForegroundColor Green
    $result | Format-Table Name, Type, PrimaryServer -AutoSize
} catch {
    Write-Host "  SOA lookup for $targetDomain`: FAILED" -ForegroundColor Red
    Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host "  Ensure VNet peering is active and the remote DC is reachable on port 53." -ForegroundColor Yellow
}

Write-Host "`nDNS forwarder configuration complete." -ForegroundColor Green
Write-Host "Next step: Run this script on the other forest's DC, then configure the forest trust." -ForegroundColor Yellow
