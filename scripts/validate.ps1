param(
    [string]$TemplateFile = "infra/main.bicep",
    [string]$DevParametersFile = "infra/parameters/dev.bicepparam",
    [string]$ProdParametersFile = "infra/parameters/prod.bicepparam"
)

$ErrorActionPreference = "Stop"

# Keep Azure CLI session/cache local to the repo to avoid profile permission issues.
$env:AZURE_CONFIG_DIR = Join-Path $PSScriptRoot ".azure"
New-Item -ItemType Directory -Path $env:AZURE_CONFIG_DIR -Force | Out-Null

Write-Host "Validating tooling..."
az version --output none
az config set bicep.check_version=false --only-show-errors --output none

Write-Host "Building Bicep template: $TemplateFile"
az bicep build --file $TemplateFile --stdout > $null

Write-Host "Compiling parameter files..."
az bicep build-params --file $DevParametersFile --stdout > $null
az bicep build-params --file $ProdParametersFile --stdout > $null

Write-Host "Validation complete. Templates are ready for what-if/deploy."
