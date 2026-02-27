targetScope = 'resourceGroup'

// ── Parameters ────────────────────────────────────────────────────────

@description('Azure region for the Bastion host.')
param location string

@description('Name prefix for Bastion resources (typically the Houston VNet name).')
param namePrefix string

@description('Resource ID of the AzureBastionSubnet.')
param bastionSubnetId string

@description('Tags applied to all resources.')
param tags object = {}

// ═══════════════════════════════════════════════════════════════════════
// Azure Bastion
// ═══════════════════════════════════════════════════════════════════════

resource bastionPip 'Microsoft.Network/publicIPAddresses@2023-09-01' = {
  name: '${namePrefix}-bastion-pip'
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource bastion 'Microsoft.Network/bastionHosts@2023-09-01' = {
  name: '${namePrefix}-bastion'
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    enableTunneling: true
    ipConfigurations: [
      {
        name: 'bastionIpConfig'
        properties: {
          publicIPAddress: {
            id: bastionPip.id
          }
          subnet: {
            id: bastionSubnetId
          }
        }
      }
    ]
  }
}

// ── Outputs ───────────────────────────────────────────────────────────

output bastionName string = bastion.name
output bastionId string = bastion.id
