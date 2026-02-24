#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Displays current FSMO role holders and optionally transfers roles to another DC.

.DESCRIPTION
    Shows all five FSMO (Flexible Single Master Operations) role holders for
    the lab.local forest/domain. Can also query west.lab.local if a trust
    exists and credentials are provided.

    Use -TransferTo to move all roles to a different DC, or -TransferTo with
    -Roles to move specific roles only.

.PARAMETER TransferTo
    Hostname of the target DC to receive FSMO roles. If omitted, the script
    only displays current holders (inspect mode).

.PARAMETER Roles
    Array of specific roles to transfer. Valid values:
    SchemaMaster, DomainNamingMaster, PDCEmulator, RIDMaster, InfrastructureMaster
    If omitted with -TransferTo, all five roles are transferred.

.PARAMETER IncludeWest
    Also query FSMO holders for the west.lab.local forest.

.EXAMPLE
    .\Inspect-FSMORoles.ps1
    # Display all FSMO holders for lab.local

.EXAMPLE
    .\Inspect-FSMORoles.ps1 -TransferTo HOUSTONDC2
    # Transfer all five FSMO roles to HOUSTONDC2

.EXAMPLE
    .\Inspect-FSMORoles.ps1 -TransferTo HOUSTONDC2 -Roles PDCEmulator, RIDMaster
    # Transfer only PDC Emulator and RID Master to HOUSTONDC2

.NOTES
    Target VM  : Any DC in lab.local (typically HOUSTONDC1)
    Prereqs    : AD DS role installed, domain operational
    AZ-800     : Manage and troubleshoot FSMO roles
#>

param(
    [string]$TransferTo,

    [ValidateSet('SchemaMaster', 'DomainNamingMaster', 'PDCEmulator', 'RIDMaster', 'InfrastructureMaster')]
    [string[]]$Roles,

    [switch]$IncludeWest
)

$ErrorActionPreference = "Stop"
Import-Module ActiveDirectory

# ── Display current FSMO holders ─────────────────────────────────────
Write-Host "`n=== FSMO Role Holders for lab.local ===" -ForegroundColor Green

$forest = Get-ADForest -Identity "lab.local"
$domain = Get-ADDomain -Identity "lab.local"

$holders = [PSCustomObject]@{
    'Schema Master'          = $forest.SchemaMaster
    'Domain Naming Master'   = $forest.DomainNamingMaster
    'PDC Emulator'           = $domain.PDCEmulator
    'RID Master'             = $domain.RIDMaster
    'Infrastructure Master'  = $domain.InfrastructureMaster
}
$holders | Format-List

# ── Optionally show West forest FSMO holders ─────────────────────────
if ($IncludeWest) {
    Write-Host "`n=== FSMO Role Holders for west.lab.local ===" -ForegroundColor Green
    try {
        $westForest = Get-ADForest -Identity "west.lab.local" -Server "WESTDC1.west.lab.local"
        $westDomain = Get-ADDomain -Identity "west.lab.local" -Server "WESTDC1.west.lab.local"
        [PSCustomObject]@{
            'Schema Master'          = $westForest.SchemaMaster
            'Domain Naming Master'   = $westForest.DomainNamingMaster
            'PDC Emulator'           = $westDomain.PDCEmulator
            'RID Master'             = $westDomain.RIDMaster
            'Infrastructure Master'  = $westDomain.InfrastructureMaster
        } | Format-List
    } catch {
        Write-Host "  Could not query west.lab.local: $_" -ForegroundColor Yellow
        Write-Host "  Ensure the forest trust is established and WESTDC1 is reachable."
    }
}

# ── Transfer roles if requested ──────────────────────────────────────
if ($TransferTo) {
    $rolesToTransfer = if ($Roles) { $Roles } else {
        @('SchemaMaster', 'DomainNamingMaster', 'PDCEmulator', 'RIDMaster', 'InfrastructureMaster')
    }

    Write-Host "`n=== Transferring FSMO Roles to $TransferTo ===" -ForegroundColor Yellow
    Write-Host "Roles: $($rolesToTransfer -join ', ')"
    $confirm = Read-Host "Continue? (Y/N)"
    if ($confirm -ne 'Y') {
        Write-Host "Transfer cancelled." -ForegroundColor Yellow
        return
    }

    Move-ADDirectoryServerOperationMasterRole -Identity $TransferTo -OperationMasterRole $rolesToTransfer -Force
    Write-Host "`nTransfer complete. Verifying..." -ForegroundColor Green

    # Re-query to confirm
    $forest = Get-ADForest -Identity "lab.local"
    $domain = Get-ADDomain -Identity "lab.local"
    [PSCustomObject]@{
        'Schema Master'          = $forest.SchemaMaster
        'Domain Naming Master'   = $forest.DomainNamingMaster
        'PDC Emulator'           = $domain.PDCEmulator
        'RID Master'             = $domain.RIDMaster
        'Infrastructure Master'  = $domain.InfrastructureMaster
    } | Format-List
}

# ── ntdsutil equivalent (for reference) ──────────────────────────────
<#
  The GUI/legacy way to inspect and transfer FSMO roles:

  # View all role holders
  netdom query fsmo

  # Transfer via ntdsutil (interactive)
  ntdsutil
    roles
    connections
    connect to server HOUSTONDC2.lab.local
    quit
    transfer schema master
    transfer naming master
    transfer pdc
    transfer rid master
    transfer infrastructure master
    quit
    quit

  # Seize roles (ONLY if the source DC is permanently offline)
  # Same as above but replace "transfer" with "seize"
  # WARNING: Seizing is destructive -- the original holder must NEVER come
  # back online after a seize operation.
#>
