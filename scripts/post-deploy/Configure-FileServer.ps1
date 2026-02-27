#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Configures a Windows file server with SMB shares and DFS Namespace.

.DESCRIPTION
    Installs the File Server role, DFS Namespace, and DFS Replication features.
    Creates a departmental share structure with proper NTFS and share permissions,
    then publishes shares into a domain-based DFS Namespace for transparent access.

    Run on HOUSTONFS1 first, then adapt and run the West section on WESTFS1.

.PARAMETER ShareRoot
    Root path for shared folders (default: C:\Shares).

.PARAMETER DfsNamespace
    DFS Namespace name published under the domain (default: Shares).

.EXAMPLE
    # On HOUSTONFS1:
    .\Configure-FileServer.ps1

    # On WESTFS1 (West forest):
    .\Configure-FileServer.ps1 -SkipDfsNamespace

.NOTES
    Target VM  : HOUSTONFS1 (primary), WESTFS1 (secondary)
    Prereqs    : Domain-joined, lab.local or west.lab.local operational
    AZ-800     : Configure and manage file servers / DFS Namespaces
#>

param(
    [string]$ShareRoot     = 'C:\Shares',
    [string]$DfsNamespace  = 'Shares',
    [string]$DomainNetbios = 'LAB',
    [switch]$SkipDfsNamespace
)

$ErrorActionPreference = "Stop"
$domainAdmins = "$DomainNetbios\Domain Admins"
$domainUsers = "$DomainNetbios\Domain Users"

# ── Step 1: Install roles and features ─────────────────────────────────
Write-Host "`n[1/5] Installing File Server roles and features..." -ForegroundColor Cyan

$features = @(
    'FS-FileServer',
    'FS-DFS-Namespace',
    'FS-DFS-Replication',
    'RSAT-DFS-Mgmt-Con'
)
foreach ($feature in $features) {
    $f = Get-WindowsFeature -Name $feature
    if (-not $f.Installed) {
        Install-WindowsFeature $feature -IncludeManagementTools | Out-Null
        Write-Host "  Installed: $feature"
    } else {
        Write-Host "  Already installed: $feature"
    }
}

# ── Step 2: Create share folder structure ──────────────────────────────
Write-Host "`n[2/5] Creating share folder structure at $ShareRoot..." -ForegroundColor Cyan

$folders = @(
    "$ShareRoot\Department",
    "$ShareRoot\Public",
    "$ShareRoot\IT"
)
foreach ($folder in $folders) {
    if (-not (Test-Path $folder)) {
        New-Item -Path $folder -ItemType Directory -Force | Out-Null
        Write-Host "  Created: $folder"
    } else {
        Write-Host "  Exists: $folder"
    }
}

# ── Step 3: Create SMB shares with permissions ─────────────────────────
Write-Host "`n[3/5] Creating SMB shares..." -ForegroundColor Cyan

$shares = @(
    @{ Name = 'Department'; Path = "$ShareRoot\Department"; FullAccess = $domainAdmins; ChangeAccess = $domainUsers }
    @{ Name = 'Public';     Path = "$ShareRoot\Public";     FullAccess = $domainAdmins; ChangeAccess = 'Everyone' }
    @{ Name = 'IT';         Path = "$ShareRoot\IT";         FullAccess = $domainAdmins; ChangeAccess = $domainAdmins }
)

foreach ($share in $shares) {
    $existing = Get-SmbShare -Name $share.Name -ErrorAction SilentlyContinue
    if (-not $existing) {
        New-SmbShare -Name $share.Name `
            -Path $share.Path `
            -FullAccess $share.FullAccess `
            -ChangeAccess $share.ChangeAccess `
            -Description "$($share.Name) share" | Out-Null
        Write-Host "  Created share: \\$env:COMPUTERNAME\$($share.Name)"
    } else {
        Write-Host "  Share exists: \\$env:COMPUTERNAME\$($share.Name)"
    }
}

# ── Step 4: Set NTFS permissions ───────────────────────────────────────
Write-Host "`n[4/5] Setting NTFS permissions..." -ForegroundColor Cyan

# Department: Domain Users Read+Execute, Domain Admins Full Control
$acl = Get-Acl "$ShareRoot\Department"
$acl.SetAccessRuleProtection($true, $false)
$acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($domainAdmins, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")))
$acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($domainUsers, "ReadAndExecute", "ContainerInherit,ObjectInherit", "None", "Allow")))
$acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule("SYSTEM", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")))
Set-Acl "$ShareRoot\Department" $acl
Write-Host "  Department: Domain Users (R+X), Domain Admins (Full)"

# IT: Domain Admins Full Control only
$acl = Get-Acl "$ShareRoot\IT"
$acl.SetAccessRuleProtection($true, $false)
$acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($domainAdmins, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")))
$acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule("SYSTEM", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")))
Set-Acl "$ShareRoot\IT" $acl
Write-Host "  IT: Domain Admins (Full)"

Write-Host "  Public: default permissions (Everyone Change via share)"

# ── Step 5: Create DFS Namespace ───────────────────────────────────────
if (-not $SkipDfsNamespace) {
    Write-Host "`n[5/5] Configuring DFS Namespace..." -ForegroundColor Cyan

    $domain = (Get-ADDomain).DNSRoot
    $dfsRoot = "\\$domain\$DfsNamespace"

    $existingDfs = Get-DfsnRoot -Path $dfsRoot -ErrorAction SilentlyContinue
    if (-not $existingDfs) {
        New-DfsnRoot -Path $dfsRoot `
            -TargetPath "\\$env:COMPUTERNAME\Department" `
            -Type DomainV2 `
            -Description "Lab shared folders" | Out-Null
        Write-Host "  Created DFS root: $dfsRoot"
    } else {
        Write-Host "  DFS root exists: $dfsRoot"
    }

    # Add folder targets
    $dfsFolders = @(
        @{ Path = "$dfsRoot\Department"; Target = "\\$env:COMPUTERNAME\Department" }
        @{ Path = "$dfsRoot\Public";     Target = "\\$env:COMPUTERNAME\Public" }
        @{ Path = "$dfsRoot\IT";         Target = "\\$env:COMPUTERNAME\IT" }
    )
    foreach ($dfs in $dfsFolders) {
        $existingFolder = Get-DfsnFolder -Path $dfs.Path -ErrorAction SilentlyContinue
        if (-not $existingFolder) {
            New-DfsnFolder -Path $dfs.Path -TargetPath $dfs.Target | Out-Null
            Write-Host "  Added DFS folder: $($dfs.Path)"
        } else {
            Write-Host "  DFS folder exists: $($dfs.Path)"
        }
    }
} else {
    Write-Host "`n[5/5] Skipping DFS Namespace (use -SkipDfsNamespace was set)." -ForegroundColor Yellow
}

# ── Validation ─────────────────────────────────────────────────────────
Write-Host "`n--- SMB Shares ---"
Get-SmbShare | Where-Object { $_.Name -notin @('ADMIN$', 'C$', 'IPC$') } |
    Format-Table Name, Path, Description

if (-not $SkipDfsNamespace) {
    Write-Host "--- DFS Namespace ---"
    $domain = (Get-ADDomain).DNSRoot
    Get-DfsnFolder -Path "\\$domain\$DfsNamespace\*" -ErrorAction SilentlyContinue |
        Format-Table Path, State
}

Write-Host "File server configuration complete." -ForegroundColor Green
