#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Configures AD Sites, Subnets, and Site Links to match the Azure VNet topology.

.DESCRIPTION
    Creates a Houston site and a West site in Active Directory Sites and Services,
    maps the VNet subnets to those sites, creates an inter-site link, and moves
    domain controllers into the correct sites.

    Run the Houston forest section on HOUSTONDC1 first. The West forest section
    is a separate block you can run on WESTDC1 (or remotely via Invoke-Command).

.NOTES
    Target VM  : HOUSTONDC1  (Houston forest section)
                 WESTDC1     (West forest section)
    Prereqs    : HOUSTONDC1, HOUSTONDC2, and WESTDC1 are all promoted as DCs
    AZ-800     : Configure and manage AD DS sites and subnets / AD DS replication
#>

$ErrorActionPreference = "Stop"
Import-Module ActiveDirectory

# ═════════════════════════════════════════════════════════════════════
# HOUSTON FOREST (lab.local) — Run on HOUSTONDC1
# ═════════════════════════════════════════════════════════════════════

Write-Host "`n=== Configuring AD Sites for lab.local ===" -ForegroundColor Green

# ── Step 1: Rename Default-First-Site-Name to Houston ────────────────
Write-Host "`n[1/6] Renaming Default-First-Site-Name to Houston..." -ForegroundColor Cyan
try {
    Get-ADReplicationSite -Identity "Default-First-Site-Name" | Rename-ADObject -NewName "Houston"
    Write-Host "  Renamed to Houston."
} catch {
    if ($_.Exception.Message -match "cannot be found") {
        Write-Host "  Houston site already exists -- skipping rename."
    } else { throw }
}

# ── Step 2: Create West site ────────────────────────────────────────
Write-Host "`n[2/6] Creating West site..." -ForegroundColor Cyan
try {
    New-ADReplicationSite -Name "West"
    Write-Host "  Created West site."
} catch {
    if ($_.Exception.Message -match "already exists") {
        Write-Host "  West site already exists -- skipping."
    } else { throw }
}

# ── Step 3: Create subnet-to-site mappings ───────────────────────────
Write-Host "`n[3/6] Creating subnet-to-site mappings..." -ForegroundColor Cyan
$subnets = @(
    @{ Name = "10.20.1.0/24"; Site = "Houston" }
    @{ Name = "10.30.1.0/24"; Site = "West" }
)
foreach ($s in $subnets) {
    try {
        New-ADReplicationSubnet -Name $s.Name -Site $s.Site
        Write-Host "  Mapped $($s.Name) -> $($s.Site)"
    } catch {
        if ($_.Exception.Message -match "already exists") {
            Write-Host "  Subnet $($s.Name) already mapped -- skipping."
        } else { throw }
    }
}

# ── Step 4: Create inter-site link ──────────────────────────────────
Write-Host "`n[4/6] Creating Houston-West site link..." -ForegroundColor Cyan
try {
    New-ADReplicationSiteLink -Name "Houston-West" `
        -SitesIncluded Houston, West `
        -Cost 100 `
        -ReplicationFrequencyInMinutes 15 `
        -InterSiteTransportProtocol IP
    Write-Host "  Created Houston-West site link (cost 100, repl every 15 min)."
} catch {
    if ($_.Exception.Message -match "already exists") {
        Write-Host "  Houston-West site link already exists -- skipping."
    } else { throw }
}

# Optionally remove the default site link if both sites are now covered
# Remove-ADReplicationSiteLink -Identity "DEFAULTIPSITELINK" -Confirm:$false

# ── Step 5: Move DCs to correct sites ───────────────────────────────
Write-Host "`n[5/6] Moving domain controllers to correct sites..." -ForegroundColor Cyan
try {
    Move-ADDirectoryServer -Identity "HOUSTONDC1" -Site "Houston"
    Write-Host "  Moved HOUSTONDC1 -> Houston"
} catch {
    Write-Host "  HOUSTONDC1 is already in Houston -- skipping."
}

try {
    Move-ADDirectoryServer -Identity "HOUSTONDC2" -Site "Houston"
    Write-Host "  Moved HOUSTONDC2 -> Houston"
} catch {
    Write-Host "  HOUSTONDC2 is already in Houston -- skipping."
}

# ── Step 6: Validate ────────────────────────────────────────────────
Write-Host "`n[6/6] Validation..." -ForegroundColor Cyan
Write-Host "`n--- Sites ---"
Get-ADReplicationSite -Filter * | Format-Table Name, DistinguishedName

Write-Host "--- Subnets ---"
Get-ADReplicationSubnet -Filter * | Format-Table Name, Site

Write-Host "--- Site Links ---"
Get-ADReplicationSiteLink -Filter * | Format-Table Name, SitesIncluded, Cost, ReplicationFrequencyInMinutes

Write-Host "--- Replication Status ---"
repadmin /showrepl

Write-Host "`nHouston forest site configuration complete." -ForegroundColor Green

# ═════════════════════════════════════════════════════════════════════
# WEST FOREST (west.lab.local) — Run on WESTDC1
# ═════════════════════════════════════════════════════════════════════
<#
  The West forest has its own AD Sites and Services. Run these commands
  on WESTDC1 in an elevated PowerShell session:

  Import-Module ActiveDirectory

  # Rename default site to West
  Get-ADReplicationSite -Identity "Default-First-Site-Name" | Rename-ADObject -NewName "West"

  # Create Houston site (for awareness of the peered subnet)
  New-ADReplicationSite -Name "Houston"

  # Map subnets
  New-ADReplicationSubnet -Name "10.30.1.0/24" -Site "West"
  New-ADReplicationSubnet -Name "10.20.1.0/24" -Site "Houston"

  # Create site link
  New-ADReplicationSiteLink -Name "West-Houston" `
      -SitesIncluded West, Houston `
      -Cost 100 `
      -ReplicationFrequencyInMinutes 15 `
      -InterSiteTransportProtocol IP

  # Move WESTDC1 to the West site
  Move-ADDirectoryServer -Identity "WESTDC1" -Site "West"

  # Validate
  Get-ADReplicationSite -Filter * | Format-Table Name
  Get-ADReplicationSubnet -Filter * | Format-Table Name, Site
#>
