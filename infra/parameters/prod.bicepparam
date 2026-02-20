using '../main.bicep'

param location = 'eastus2'
param westLocation = 'westus2'
param adminUsername = 'labadmin'
param houstonVnetName = 'HoustonNET1'
param houstonAddressSpace = '10.20.0.0/16'
param houstonSubnetPrefix = '10.20.1.0/24'
param westVnetName = 'WestNET1'
param westAddressSpace = '10.30.0.0/16'
param westSubnetPrefix = '10.30.1.0/24'
param allowedSourceAddressPrefix = '203.0.113.10/32'
param domainControllerVmSize = 'Standard_D2s_v5'
param memberVmSize = 'Standard_D2s_v5'
param houstonDc1PublicIp = false
param houstonDc2PublicIp = false
param westDc1PublicIp = false
param houstonVm1PublicIp = true
param houstonVm2PublicIp = false
param tags = {
  environment: 'prod'
  workload: 'windows-hybrid-lab'
  owner: 'jaredio'
}

// Set with secure value at deployment time:
// --parameters adminPassword="<StrongPassword>"
// Replace allowedSourceAddressPrefix with your real public IP before deployment.
