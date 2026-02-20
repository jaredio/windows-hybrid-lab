targetScope = 'resourceGroup'

@description('Primary Azure region for Houston resources.')
param location string = resourceGroup().location

@description('Optional region override for West resources. Uses location when empty.')
param westLocation string = ''

@description('Local administrator username for all VMs.')
param adminUsername string = 'labadmin'

@secure()
@description('Local administrator password for all VMs.')
param adminPassword string

@description('Public source CIDR allowed for RDP (3389), for example 203.0.113.4/32.')
param allowedSourceAddressPrefix string = '*'

@description('Houston VNet name.')
param houstonVnetName string = 'HoustonNET1'

@description('Houston VNet CIDR block.')
param houstonAddressSpace string = '10.20.0.0/16'

@description('Houston subnet CIDR block.')
param houstonSubnetPrefix string = '10.20.1.0/24'

@description('West VNet name.')
param westVnetName string = 'WestNET1'

@description('West VNet CIDR block.')
param westAddressSpace string = '10.30.0.0/16'

@description('West subnet CIDR block.')
param westSubnetPrefix string = '10.30.1.0/24'

@description('VM size for domain controllers.')
param domainControllerVmSize string = 'Standard_B2ms'

@description('VM size for member VMs.')
param memberVmSize string = 'Standard_B2s'

@description('Whether HOUSTONDC1 gets a public IP.')
param houstonDc1PublicIp bool = false

@description('Whether HOUSTONDC2 gets a public IP.')
param houstonDc2PublicIp bool = false

@description('Whether WESTDC1 gets a public IP.')
param westDc1PublicIp bool = false

@description('Whether HOUSTONVM1 gets a public IP.')
param houstonVm1PublicIp bool = true

@description('Whether HOUSTONVM2 gets a public IP.')
param houstonVm2PublicIp bool = false

@description('Tags applied to all resources.')
param tags object = {
  workload: 'windows-hybrid-lab'
  managedBy: 'bicep'
  project: 'windows-hybrid-lab'
}

var resolvedWestLocation = empty(westLocation) ? location : westLocation
var houstonSubnetName = 'HoustonServers'
var westSubnetName = 'WestServers'

var houstonDc1Name = 'HOUSTONDC1'
var houstonDc2Name = 'HOUSTONDC2'
var westDc1Name = 'WESTDC1'
var houstonVm1Name = 'HOUSTONVM1'
var houstonVm2Name = 'HOUSTONVM2'

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
  location: resolvedWestLocation
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
    subnets: [
      {
        name: houstonSubnetName
        properties: {
          addressPrefix: houstonSubnetPrefix
          networkSecurityGroup: {
            id: houstonNsg.id
          }
        }
      }
    ]
  }
}

resource westVnet 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: westVnetName
  location: resolvedWestLocation
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

resource houstonToWestPeering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-09-01' = {
  name: '${houstonVnet.name}/HoustonToWest'
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
  name: '${westVnet.name}/WestToHouston'
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

module houstonDc1 './modules/windows-vm.bicep' = {
  name: 'vm-houston-dc1'
  params: {
    location: location
    vmName: houstonDc1Name
    vmSize: domainControllerVmSize
    subnetId: resourceId('Microsoft.Network/virtualNetworks/subnets', houstonVnet.name, houstonSubnetName)
    networkSecurityGroupId: houstonNsg.id
    privateIpAddress: '10.20.1.10'
    adminUsername: adminUsername
    adminPassword: adminPassword
    publisher: 'MicrosoftWindowsServer'
    offer: 'WindowsServer'
    sku: '2022-datacenter-azure-edition'
    createPublicIp: houstonDc1PublicIp
    tags: tags
  }
}

module houstonDc2 './modules/windows-vm.bicep' = {
  name: 'vm-houston-dc2'
  params: {
    location: location
    vmName: houstonDc2Name
    vmSize: domainControllerVmSize
    subnetId: resourceId('Microsoft.Network/virtualNetworks/subnets', houstonVnet.name, houstonSubnetName)
    networkSecurityGroupId: houstonNsg.id
    privateIpAddress: '10.20.1.11'
    adminUsername: adminUsername
    adminPassword: adminPassword
    publisher: 'MicrosoftWindowsServer'
    offer: 'WindowsServer'
    sku: '2022-datacenter-azure-edition'
    createPublicIp: houstonDc2PublicIp
    tags: tags
  }
}

module westDc1 './modules/windows-vm.bicep' = {
  name: 'vm-west-dc1'
  params: {
    location: resolvedWestLocation
    vmName: westDc1Name
    vmSize: domainControllerVmSize
    subnetId: resourceId('Microsoft.Network/virtualNetworks/subnets', westVnet.name, westSubnetName)
    networkSecurityGroupId: westNsg.id
    privateIpAddress: '10.30.1.10'
    adminUsername: adminUsername
    adminPassword: adminPassword
    publisher: 'MicrosoftWindowsServer'
    offer: 'WindowsServer'
    sku: '2022-datacenter-azure-edition'
    createPublicIp: westDc1PublicIp
    tags: tags
  }
}

module houstonVm1 './modules/windows-vm.bicep' = {
  name: 'vm-houston-vm1'
  params: {
    location: location
    vmName: houstonVm1Name
    vmSize: memberVmSize
    subnetId: resourceId('Microsoft.Network/virtualNetworks/subnets', houstonVnet.name, houstonSubnetName)
    networkSecurityGroupId: houstonNsg.id
    privateIpAddress: '10.20.1.20'
    adminUsername: adminUsername
    adminPassword: adminPassword
    publisher: 'MicrosoftWindowsDesktop'
    offer: 'windows-10'
    sku: 'win10-22h2-pro-g2'
    createPublicIp: houstonVm1PublicIp
    tags: tags
  }
}

module houstonVm2 './modules/windows-vm.bicep' = {
  name: 'vm-houston-vm2'
  params: {
    location: location
    vmName: houstonVm2Name
    vmSize: memberVmSize
    subnetId: resourceId('Microsoft.Network/virtualNetworks/subnets', houstonVnet.name, houstonSubnetName)
    networkSecurityGroupId: houstonNsg.id
    privateIpAddress: '10.20.1.21'
    adminUsername: adminUsername
    adminPassword: adminPassword
    publisher: 'MicrosoftWindowsDesktop'
    offer: 'windows-10'
    sku: 'win10-22h2-pro-g2'
    createPublicIp: houstonVm2PublicIp
    tags: tags
  }
}

output houstonVnetResourceId string = houstonVnet.id
output westVnetResourceId string = westVnet.id
output houstonPeeringName string = houstonToWestPeering.name
output westPeeringName string = westToHoustonPeering.name
output houstonDc1VmName string = houstonDc1.outputs.vmName
output houstonDc2VmName string = houstonDc2.outputs.vmName
output westDc1VmName string = westDc1.outputs.vmName
output houstonVm1VmName string = houstonVm1.outputs.vmName
output houstonVm2VmName string = houstonVm2.outputs.vmName
output houstonDc1PrivateIp string = houstonDc1.outputs.privateIp
output houstonDc2PrivateIp string = houstonDc2.outputs.privateIp
output westDc1PrivateIp string = westDc1.outputs.privateIp
output houstonVm1PrivateIp string = houstonVm1.outputs.privateIp
output houstonVm2PrivateIp string = houstonVm2.outputs.privateIp

