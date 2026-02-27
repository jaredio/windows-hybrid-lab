#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Creates a bidirectional forest trust between lab.local and west.lab.local.

.DESCRIPTION
    Validates DNS prerequisites, then establishes a two-way forest trust
    between the Houston and West forests. Uses netdom for reliable trust
    creation in lab environments.

    Run this on HOUSTONDC1 after conditional DNS forwarders are configured
    in both directions (see Configure-CrossForestDNS.ps1).

.PARAMETER LocalDomain
    FQDN of the local forest (default: lab.local).

.PARAMETER RemoteDomain
    FQDN of the remote forest to trust (default: west.lab.local).

.EXAMPLE
    # Default: create bidirectional trust between lab.local and west.lab.local
    .\Configure-ForestTrust.ps1

    # Custom domains:
    .\Configure-ForestTrust.ps1 -LocalDomain "corp.local" -RemoteDomain "branch.local"

.NOTES
    Target VM  : HOUSTONDC1
    Prereqs    : Both forests promoted, conditional DNS forwarders configured
                 in both directions, VNet peering active
    AZ-800     : Configure and manage Active Directory trust relationships
#>

param(
    [string]$LocalDomain    = 'lab.local',
    [string]$RemoteDomain   = 'west.lab.local'
)

$ErrorActionPreference = "Stop"

# ── Step 1: Check for existing trust ──────────────────────────────────
Write-Host "`n[1/4] Checking for existing trust..." -ForegroundColor Cyan

$existingTrust = Get-ADTrust -Filter { Target -eq $RemoteDomain } -ErrorAction SilentlyContinue
if ($existingTrust) {
    Write-Host "  Trust to '$RemoteDomain' already exists." -ForegroundColor Yellow
    Write-Host "    Direction : $($existingTrust.Direction)"
    Write-Host "    Trust Type: $(if ($existingTrust.ForestTransitive) { 'Forest' } else { 'External' })"
    Write-Host "  Skipping trust creation. Delete the existing trust first if you want to recreate it."
    Write-Host "`n--- Validation ---"
    nltest /domain_trusts
    return
}

# ── Step 2: Validate DNS prerequisites ────────────────────────────────
Write-Host "`n[2/4] Validating DNS resolution to $RemoteDomain..." -ForegroundColor Cyan

try {
    $soa = Resolve-DnsName -Name $RemoteDomain -Type SOA -ErrorAction Stop
    Write-Host "  SOA record found: $($soa.PrimaryServer)" -ForegroundColor Green
} catch {
    Write-Error "Cannot resolve '$RemoteDomain'. Ensure conditional DNS forwarders are configured. Run Configure-CrossForestDNS.ps1 first."
}

try {
    $dc = Resolve-DnsName -Name "_ldap._tcp.dc._msdcs.$RemoteDomain" -Type SRV -ErrorAction Stop
    Write-Host "  SRV record found: $($dc.NameTarget)" -ForegroundColor Green
} catch {
    Write-Warning "SRV record lookup for $RemoteDomain DCs failed. Trust creation may still succeed if the DC is reachable."
}

# ── Step 3: Create bidirectional forest trust ─────────────────────────
Write-Host "`n[3/4] Creating bidirectional forest trust..." -ForegroundColor Cyan
Write-Host "  Local forest : $LocalDomain"
Write-Host "  Remote forest: $RemoteDomain"

$remoteCred = Get-Credential -Message "Enter credentials for a Domain Admin in $RemoteDomain (e.g., WEST\labadmin)"

# netdom is the most reliable method for lab trust creation
# It handles the trust object creation on both sides in a single command
Write-Host "  Running netdom trust..."
$netdomArgs = @(
    'trust', $LocalDomain,
    '/domain:' + $RemoteDomain,
    '/twoway',
    '/transitive:yes',
    '/add',
    '/UserD:' + $remoteCred.UserName,
    '/PasswordD:' + $remoteCred.GetNetworkCredential().Password
)
$netdomResult = & netdom @netdomArgs 2>&1
$netdomOutput = $netdomResult -join "`n"

if ($LASTEXITCODE -eq 0) {
    Write-Host "  Forest trust created successfully." -ForegroundColor Green
} else {
    Write-Host "  netdom output:" -ForegroundColor Red
    Write-Host $netdomOutput
    Write-Error "Trust creation failed. Check credentials and network connectivity."
}

# ── Step 4: Validate ──────────────────────────────────────────────────
Write-Host "`n[4/4] Validation..." -ForegroundColor Cyan

Write-Host "`n--- AD Trust Object ---"
Get-ADTrust -Filter { Target -eq $RemoteDomain } -ErrorAction SilentlyContinue |
    Format-List Name, Target, Direction, ForestTransitive, TrustType

Write-Host "--- Domain Trusts (nltest) ---"
nltest /domain_trusts

Write-Host "--- Secure Channel Verification ---"
$scResult = nltest /sc_verify:$RemoteDomain 2>&1
$scOutput = $scResult -join "`n"
if ($scOutput -match 'NERR_Success') {
    Write-Host "  Secure channel to $RemoteDomain`: HEALTHY" -ForegroundColor Green
} else {
    Write-Host "  Secure channel to $RemoteDomain`: $scOutput" -ForegroundColor Yellow
    Write-Host "  The trust was created but the secure channel may need time to establish." -ForegroundColor Yellow
}

Write-Host "`nForest trust configuration complete." -ForegroundColor Green
Write-Host "Test cross-forest auth: runas /netonly /user:WEST\labadmin cmd" -ForegroundColor Yellow
