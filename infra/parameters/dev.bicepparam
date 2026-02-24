using '../main.bicep'

// ── Region ──────────────────────────────────────────────────────────
param location = 'eastus'
param westLocation = 'westus2'

// ── Credentials ─────────────────────────────────────────────────────
param adminUsername = 'labadmin'
// Set adminPassword at deploy time:  --parameters adminPassword="<StrongPassword>"

// ── Networking ──────────────────────────────────────────────────────
param houstonVnetName = 'HoustonNET1'
param houstonAddressSpace = '10.20.0.0/16'
param houstonSubnetPrefix = '10.20.1.0/24'
param westVnetName = 'WestNET1'
param westAddressSpace = '10.30.0.0/16'
param westSubnetPrefix = '10.30.1.0/24'

// Replace '*' with your public IP (e.g. '203.0.113.10/32') before deploying
param allowedSourceAddressPrefix = '*'

// ── VM sizing ───────────────────────────────────────────────────────
param domainControllerVmSize = 'Standard_B2ms'
param memberVmSize = 'Standard_B2s'

// ── VM names ────────────────────────────────────────────────────────
param houstonDc1Name = 'HOUSTONDC1'
param houstonDc2Name = 'HOUSTONDC2'
param westDc1Name = 'WESTDC1'
param houstonVm1Name = 'HOUSTONVM1'
param houstonVm2Name = 'HOUSTONVM2'

// ── Private IPs ─────────────────────────────────────────────────────
param houstonDc1Ip = '10.20.1.10'
param houstonDc2Ip = '10.20.1.11'
param westDc1Ip = '10.30.1.10'
param houstonVm1Ip = '10.20.1.20'
param houstonVm2Ip = '10.20.1.21'

// ── Public IP toggles ───────────────────────────────────────────────
param houstonDc1PublicIp = false
param houstonDc2PublicIp = false
param westDc1PublicIp = false
param houstonVm1PublicIp = true
param houstonVm2PublicIp = false

// ── AD DS role overrides ────────────────────────────────────────────
// Change to 'RODC' to promote HOUSTONDC2 as a Read-Only Domain Controller
param houstonDc2Role = 'WritableReplica'

// ── Tags ────────────────────────────────────────────────────────────
param tags = {
  environment: 'dev'
  workload: 'windows-hybrid-lab'
  managedBy: 'bicep'
  project: 'windows-hybrid-lab'
  owner: 'jaredio'
}
