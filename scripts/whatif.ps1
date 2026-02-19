param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,

    [ValidateSet("dev", "prod")]
    [string]$Environment = "dev",

    [Parameter(Mandatory = $true)]
    [string]$AdminPassword
)

$ErrorActionPreference = "Stop"

$env:AZURE_CONFIG_DIR = Join-Path $PSScriptRoot ".azure"
New-Item -ItemType Directory -Path $env:AZURE_CONFIG_DIR -Force | Out-Null
az config set bicep.check_version=false --only-show-errors --output none

$parameterFile = "infra/parameters/$Environment.bicepparam"

Write-Host "Running what-if for environment '$Environment' in resource group '$ResourceGroupName'..."
az deployment group what-if `
    --resource-group $ResourceGroupName `
    --template-file "infra/main.bicep" `
    --parameters $parameterFile `
    --parameters adminPassword=$AdminPassword

Write-Host "What-if complete."
