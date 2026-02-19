using '../main.bicep'

param location = 'eastus'
param namePrefix = 'az800dev'
param adminUsername = 'labadmin'
param vnetAddressSpace = '10.20.0.0/16'
param subnetAddressPrefix = '10.20.1.0/24'
param allowedSourceAddressPrefix = '203.0.113.10/32'
param serverVmSize = 'Standard_B2ms'
param clientVmSize = 'Standard_B2s'
param dc1PublicIp = false
param dc2PublicIp = false
param clientPublicIp = true
param tags = {
  environment: 'dev'
  workload: 'az800-lab'
}

// Set with secure value at deployment time:
// --parameters adminPassword="<StrongPassword>"
// Replace allowedSourceAddressPrefix with your real public IP before deployment.
