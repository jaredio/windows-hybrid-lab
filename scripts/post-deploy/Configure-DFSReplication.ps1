#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Configures DFS Replication between Houston and West file servers.

.DESCRIPTION
    Creates a DFS Replication group to replicate shared folders between
    HOUSTONFS1 and WESTFS1 across the VNet peering link. HOUSTONFS1 is
    set as the primary member for initial sync direction.

    Run this on HOUSTONDC1 (or any DC with DFS management tools) after
    Configure-FileServer.ps1 has been run on both file servers.

.PARAMETER ReplicationGroupName
    Name of the DFS Replication group (default: Houston-West-Replication).

.PARAMETER HoustonServer
    Houston file server hostname (default: HOUSTONFS1).

.PARAMETER WestServer
    West file server hostname (default: WESTFS1).

.PARAMETER ReplicatedFolder
    Folder name to replicate (default: Department).

.PARAMETER HoustonPath
    Local path on Houston server (default: C:\Shares\Department).

.PARAMETER WestPath
    Local path on West server (default: C:\Shares\Department).

.EXAMPLE
    .\Configure-DFSReplication.ps1

.NOTES
    Target VM  : HOUSTONDC1 (manages replication group)
    Prereqs    : DFS Replication feature installed on HOUSTONFS1 and WESTFS1,
                 Configure-FileServer.ps1 run on both servers, cross-forest
                 DNS working
    AZ-800     : Configure DFS Replication
#>

param(
    [string]$ReplicationGroupName = 'Houston-West-Replication',
    [string]$HoustonServer        = 'HOUSTONFS1',
    [string]$WestServer           = 'WESTFS1',
    [string]$ReplicatedFolder     = 'Department',
    [string]$HoustonPath          = 'C:\Shares\Department',
    [string]$WestPath             = 'C:\Shares\Department'
)

$ErrorActionPreference = "Stop"

# ── Step 1: Verify prerequisites ──────────────────────────────────────
Write-Host "`n[1/4] Verifying prerequisites..." -ForegroundColor Cyan

Import-Module DFSR -ErrorAction Stop
Write-Host "  DFSR module loaded."

# Check both servers are reachable
foreach ($server in @($HoustonServer, $WestServer)) {
    if (Test-Connection -ComputerName $server -Count 1 -Quiet) {
        Write-Host "  $server is reachable."
    } else {
        Write-Error "$server is not reachable. Ensure both file servers are online and DNS is working."
    }
}

# ── Step 2: Create replication group ──────────────────────────────────
Write-Host "`n[2/4] Creating DFS Replication group..." -ForegroundColor Cyan

$existing = Get-DfsReplicationGroup -GroupName $ReplicationGroupName -ErrorAction SilentlyContinue
if ($existing) {
    Write-Host "  Replication group '$ReplicationGroupName' already exists -- skipping creation."
} else {
    New-DfsReplicationGroup -GroupName $ReplicationGroupName | Out-Null
    Write-Host "  Created replication group: $ReplicationGroupName"

    # Add members
    Add-DfsrMember -GroupName $ReplicationGroupName -ComputerName $HoustonServer | Out-Null
    Write-Host "  Added member: $HoustonServer"
    Add-DfsrMember -GroupName $ReplicationGroupName -ComputerName $WestServer | Out-Null
    Write-Host "  Added member: $WestServer"
}

# ── Step 3: Add replicated folder and connections ─────────────────────
Write-Host "`n[3/4] Configuring replicated folder and connections..." -ForegroundColor Cyan

$existingFolder = Get-DfsReplicatedFolder -GroupName $ReplicationGroupName -FolderName $ReplicatedFolder -ErrorAction SilentlyContinue
if (-not $existingFolder) {
    New-DfsReplicatedFolder -GroupName $ReplicationGroupName `
        -FolderName $ReplicatedFolder | Out-Null
    Write-Host "  Added replicated folder: $ReplicatedFolder"
} else {
    Write-Host "  Replicated folder '$ReplicatedFolder' already exists."
}

# Set content paths
Set-DfsrMembership -GroupName $ReplicationGroupName `
    -FolderName $ReplicatedFolder `
    -ComputerName $HoustonServer `
    -ContentPath $HoustonPath `
    -PrimaryMember $true `
    -Force | Out-Null
Write-Host "  Set $HoustonServer as PRIMARY member (path: $HoustonPath)"

Set-DfsrMembership -GroupName $ReplicationGroupName `
    -FolderName $ReplicatedFolder `
    -ComputerName $WestServer `
    -ContentPath $WestPath `
    -Force | Out-Null
Write-Host "  Set $WestServer as secondary member (path: $WestPath)"

# Create bidirectional connections
$existingConn = Get-DfsrConnection -GroupName $ReplicationGroupName -ErrorAction SilentlyContinue
if (-not $existingConn) {
    Add-DfsrConnection -GroupName $ReplicationGroupName `
        -SourceComputerName $HoustonServer `
        -DestinationComputerName $WestServer | Out-Null
    Write-Host "  Created bidirectional connection: $HoustonServer <-> $WestServer"
} else {
    Write-Host "  Connection already exists between members."
}

# ── Step 4: Validation ────────────────────────────────────────────────
Write-Host "`n[4/4] Validation..." -ForegroundColor Cyan

# Force AD replication so DFSR config propagates
Write-Host "  Forcing AD replication for DFSR config propagation..."
repadmin /syncall /AdeP 2>&1 | Out-Null

Write-Host "`n--- Replication Group ---"
Get-DfsReplicationGroup -GroupName $ReplicationGroupName | Format-Table GroupName, State

Write-Host "--- Members ---"
Get-DfsrMember -GroupName $ReplicationGroupName | Format-Table ComputerName, DomainName

Write-Host "--- Replicated Folders ---"
Get-DfsReplicatedFolder -GroupName $ReplicationGroupName | Format-Table FolderName, State

Write-Host "--- Backlog (may be empty initially) ---"
try {
    Get-DfsrBacklog -GroupName $ReplicationGroupName `
        -SourceComputerName $HoustonServer `
        -DestinationComputerName $WestServer `
        -FolderName $ReplicatedFolder -Verbose 2>&1
} catch {
    Write-Host "  Backlog check not yet available (replication may need a few minutes to initialize)." -ForegroundColor Yellow
}

Write-Host "`nDFS Replication configuration complete." -ForegroundColor Green
Write-Host "Initial sync may take several minutes. Monitor with:" -ForegroundColor Yellow
Write-Host "  Get-DfsrBacklog -GroupName '$ReplicationGroupName' -SourceComputerName $HoustonServer -DestinationComputerName $WestServer -FolderName $ReplicatedFolder" -ForegroundColor Yellow
