#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Installs an Enterprise Root Certificate Authority on HOUSTONDC1.

.DESCRIPTION
    Installs Active Directory Certificate Services (AD CS) as an Enterprise
    Root CA, configures the CA with SHA256/2048-bit key, sets up certificate
    templates for Web Server and Workstation Authentication, and enables
    LDAPS on domain controllers by requesting a DC certificate.

    Running the CA on a domain controller is standard practice for small
    environments and labs. Production environments typically use a two-tier
    CA hierarchy with an offline root.

.PARAMETER CAName
    Common name for the CA (default: lab-HOUSTONDC1-CA).

.PARAMETER ValidityYears
    CA certificate validity period in years (default: 5).

.EXAMPLE
    .\Configure-ADCS.ps1

    # Custom CA name:
    .\Configure-ADCS.ps1 -CAName "LabEnterprise-CA"

.NOTES
    Target VM  : HOUSTONDC1
    Prereqs    : lab.local domain operational, HOUSTONDC1 is a DC
    AZ-800     : Implement and manage Active Directory Certificate Services
#>

param(
    [string]$CAName         = 'lab-HOUSTONDC1-CA',
    [int]$ValidityYears     = 5,
    [int]$KeyLength         = 2048,
    [string]$HashAlgorithm  = 'SHA256'
)

$ErrorActionPreference = "Stop"

# ── Step 1: Install AD CS role ────────────────────────────────────────
Write-Host "`n[1/5] Installing AD CS role..." -ForegroundColor Cyan

$adcs = Get-WindowsFeature -Name AD-Certificate
if (-not $adcs.Installed) {
    Install-WindowsFeature AD-Certificate -IncludeManagementTools -IncludeAllSubFeature | Out-Null
    Write-Host "  Installed AD Certificate Services."
} else {
    Write-Host "  AD CS role already installed."
}

# Also install web enrollment for certificate requests
$webEnroll = Get-WindowsFeature -Name ADCS-Web-Enrollment
if (-not $webEnroll.Installed) {
    Install-WindowsFeature ADCS-Web-Enrollment -IncludeManagementTools | Out-Null
    Write-Host "  Installed Web Enrollment."
}

# ── Step 2: Configure Enterprise Root CA ──────────────────────────────
Write-Host "`n[2/5] Configuring Enterprise Root CA..." -ForegroundColor Cyan

# Check if CA is already configured
$existingCA = Get-Service CertSvc -ErrorAction SilentlyContinue
if ($existingCA -and $existingCA.Status -eq 'Running') {
    Write-Host "  Certificate Services already running -- skipping CA configuration."
} else {
    try {
        Install-AdcsCertificationAuthority `
            -CAType EnterpriseRootCa `
            -CACommonName $CAName `
            -KeyLength $KeyLength `
            -HashAlgorithmName $HashAlgorithm `
            -ValidityPeriod Years `
            -ValidityPeriodUnits $ValidityYears `
            -CryptoProviderName "RSA#Microsoft Software Key Storage Provider" `
            -Force | Out-Null
        Write-Host "  Configured Enterprise Root CA: $CAName"
        Write-Host "    Key length: $KeyLength"
        Write-Host "    Hash: $HashAlgorithm"
        Write-Host "    Validity: $ValidityYears years"
    } catch {
        if ($_.Exception.Message -match "already installed") {
            Write-Host "  CA is already configured."
        } else {
            throw
        }
    }
}

# Configure web enrollment
try {
    Install-AdcsWebEnrollment -Force | Out-Null
    Write-Host "  Web Enrollment configured."
} catch {
    if ($_.Exception.Message -match "already installed") {
        Write-Host "  Web Enrollment already configured."
    } else {
        Write-Warning "Web Enrollment configuration failed: $($_.Exception.Message)"
    }
}

# ── Step 3: Configure certificate templates ───────────────────────────
Write-Host "`n[3/5] Publishing certificate templates..." -ForegroundColor Cyan

# Ensure the CA service is running
Start-Service CertSvc -ErrorAction SilentlyContinue
Start-Sleep -Seconds 5

# The default Enterprise Root CA publishes common templates automatically.
# Verify key templates are available.
$templates = certutil -CATemplates 2>&1
$templateList = $templates -join "`n"

$requiredTemplates = @('WebServer', 'DomainController', 'DomainControllerAuthentication')
foreach ($tmpl in $requiredTemplates) {
    if ($templateList -match $tmpl) {
        Write-Host "  Template available: $tmpl"
    } else {
        Write-Host "  Template not found: $tmpl (may need manual publishing)" -ForegroundColor Yellow
        # Try to add the template
        try {
            certutil -SetCATemplates "+$tmpl" 2>&1 | Out-Null
            Write-Host "    Published: $tmpl"
        } catch {
            Write-Host "    Could not publish: $tmpl" -ForegroundColor Yellow
        }
    }
}

# ── Step 4: Request DC certificate for LDAPS ─────────────────────────
Write-Host "`n[4/5] Requesting domain controller certificate for LDAPS..." -ForegroundColor Cyan

# Auto-enroll the DC certificate
$enrollResult = certreq -enroll -machine DomainController 2>&1
$enrollOutput = $enrollResult -join "`n"
if ($enrollOutput -match "Installed Certificate" -or $enrollOutput -match "already exists") {
    Write-Host "  DC certificate enrolled -- LDAPS should be active on port 636."
} else {
    Write-Host "  Certificate enrollment output:" -ForegroundColor Yellow
    Write-Host "  $enrollOutput"
    Write-Host "  LDAPS may need a manual certificate request or DC reboot." -ForegroundColor Yellow
}

# ── Step 5: Validation ────────────────────────────────────────────────
Write-Host "`n[5/5] Validation..." -ForegroundColor Cyan

Write-Host "`n--- CA Service Status ---"
Get-Service CertSvc | Format-Table Name, Status, DisplayName

Write-Host "--- CA Configuration ---"
certutil -ca 2>&1 | Select-Object -First 15

Write-Host "`n--- CA Ping ---"
certutil -ping 2>&1

Write-Host "`n--- LDAPS Test ---"
$ldapsTest = Test-NetConnection -ComputerName $env:COMPUTERNAME -Port 636 -WarningAction SilentlyContinue
if ($ldapsTest.TcpTestSucceeded) {
    Write-Host "  LDAPS (port 636): LISTENING" -ForegroundColor Green
} else {
    Write-Host "  LDAPS (port 636): NOT YET AVAILABLE" -ForegroundColor Yellow
    Write-Host "  A reboot may be required for the DC to load the new certificate." -ForegroundColor Yellow
}

Write-Host "`nAD CS configuration complete." -ForegroundColor Green
Write-Host "Access Web Enrollment: https://$env:COMPUTERNAME/certsrv" -ForegroundColor Yellow
Write-Host "View CA: certsrv.msc or certutil -ca" -ForegroundColor Yellow
