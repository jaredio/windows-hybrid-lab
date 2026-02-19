using '../main.bicep'

param location = 'eastus2'
param namePrefix = 'az800prd'
param adminUsername = 'labadmin'
param vnetAddressSpace = '10.30.0.0/16'
param subnetAddressPrefix = '10.30.1.0/24'
param allowedSourceAddressPrefix = '203.0.113.10/32'
param serverVmSize = 'Standard_D2s_v5'
param clientVmSize = 'Standard_D2s_v5'
param dc1PublicIp = false
param dc2PublicIp = false
param clientPublicIp = true
param tags = {
  environment: 'prod'
  workload: 'az800-lab'
}

// Set with secure value at deployment time:
// --parameters adminPassword="<StrongPassword>"
// Replace allowedSourceAddressPrefix with your real public IP before deployment.
