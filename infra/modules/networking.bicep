targetScope = 'resourceGroup'

// ── Parameters ────────────────────────────────────────────────────────

@description('Primary Azure region for Houston resources.')
param location string

@description('Azure region for West resources.')
param westLocation string

@description('Houston VNet name.')
param houstonVnetName string

@description('Houston VNet CIDR block.')
param houstonAddressSpace string

@description('Houston subnet CIDR block.')
param houstonSubnetPrefix string

@description('West VNet name.')
param westVnetName string

@description('West VNet CIDR block.')
param westAddressSpace string

@description('West subnet CIDR block.')
param westSubnetPrefix string

@description('Public source CIDR allowed for RDP (3389).')
param allowedSourceAddressPrefix string

@description('Deploy AzureBastionSubnet in the Houston VNet.')
param deployBastionSubnet bool

@description('Address prefix for the AzureBastionSubnet.')
param bastionSubnetPrefix string

@description('Tags applied to all resources.')
param tags object = {}

// ── Variables ─────────────────────────────────────────────────────────

var houstonSubnetName = 'HoustonServers'
var westSubnetName = 'WestServers'

// ═══════════════════════════════════════════════════════════════════════
// NSGs
// ═══════════════════════════════════════════════════════════════════════

resource houstonNsg 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: '${houstonVnetName}-nsg'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'allow-rdp-inbound'
        properties: {
          priority: 100
          access: 'Allow'
          direction: 'Inbound'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '3389'
          sourceAddressPrefix: allowedSourceAddressPrefix
          destinationAddressPrefix: '*'
        }
      }
    ]
  }
}

resource westNsg 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: '${westVnetName}-nsg'
  location: westLocation
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'allow-rdp-inbound'
        properties: {
          priority: 100
          access: 'Allow'
          direction: 'Inbound'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '3389'
          sourceAddressPrefix: allowedSourceAddressPrefix
          destinationAddressPrefix: '*'
        }
      }
    ]
  }
}

// ═══════════════════════════════════════════════════════════════════════
// VNets
// ═══════════════════════════════════════════════════════════════════════

resource houstonVnet 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: houstonVnetName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        houstonAddressSpace
      ]
    }
    subnets: concat([
      {
        name: houstonSubnetName
        properties: {
          addressPrefix: houstonSubnetPrefix
          networkSecurityGroup: {
            id: houstonNsg.id
          }
        }
      }
    ], deployBastionSubnet ? [
      {
        name: 'AzureBastionSubnet'
        properties: {
          addressPrefix: bastionSubnetPrefix
        }
      }
    ] : [])
  }
}

resource westVnet 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: westVnetName
  location: westLocation
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        westAddressSpace
      ]
    }
    subnets: [
      {
        name: westSubnetName
        properties: {
          addressPrefix: westSubnetPrefix
          networkSecurityGroup: {
            id: westNsg.id
          }
        }
      }
    ]
  }
}

// ═══════════════════════════════════════════════════════════════════════
// VNet Peering
// ═══════════════════════════════════════════════════════════════════════

resource houstonToWestPeering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-09-01' = {
  parent: houstonVnet
  name: 'HoustonToWest'
  properties: {
    remoteVirtualNetwork: {
      id: westVnet.id
    }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: false
    useRemoteGateways: false
  }
}

resource westToHoustonPeering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-09-01' = {
  parent: westVnet
  name: 'WestToHouston'
  properties: {
    remoteVirtualNetwork: {
      id: houstonVnet.id
    }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: false
    useRemoteGateways: false
  }
}

// ── Outputs ───────────────────────────────────────────────────────────

output houstonVnetId string = houstonVnet.id
output houstonVnetName string = houstonVnet.name
output westVnetId string = westVnet.id
output westVnetName string = westVnet.name
output houstonSubnetId string = resourceId('Microsoft.Network/virtualNetworks/subnets', houstonVnet.name, houstonSubnetName)
output westSubnetId string = resourceId('Microsoft.Network/virtualNetworks/subnets', westVnet.name, westSubnetName)
output bastionSubnetId string = deployBastionSubnet ? resourceId('Microsoft.Network/virtualNetworks/subnets', houstonVnet.name, 'AzureBastionSubnet') : ''
output houstonPeeringName string = houstonToWestPeering.name
output westPeeringName string = westToHoustonPeering.name
