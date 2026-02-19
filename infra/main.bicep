targetScope = 'resourceGroup'

@description('Azure region for all resources.')
param location string = resourceGroup().location

@description('Project-specific name prefix for resources.')
param namePrefix string = 'az800lab'

@description('Local administrator username for all VMs.')
param adminUsername string = 'labadmin'

@secure()
@description('Admin password for all VMs.')
param adminPassword string

@description('Address space for the lab VNet.')
param vnetAddressSpace string = '10.20.0.0/16'

@description('Subnet prefix for all lab VMs.')
param subnetAddressPrefix string = '10.20.1.0/24'

@description('Public source CIDR allowed for RDP (3389), for example 203.0.113.4/32.')
param allowedSourceAddressPrefix string = '*'

@description('VM size for both domain controller VMs.')
param serverVmSize string = 'Standard_B2ms'

@description('VM size for the Windows client VM.')
param clientVmSize string = 'Standard_B2s'

@description('Whether domain controller 1 gets a public IP.')
param dc1PublicIp bool = false

@description('Whether domain controller 2 gets a public IP.')
param dc2PublicIp bool = false

@description('Whether client VM gets a public IP.')
param clientPublicIp bool = true

@description('Tags applied to all resources.')
param tags object = {
  workload: 'az800-lab'
  managedBy: 'bicep'
  project: 'windows-hybrid-infra-lab'
}

var vnetName = '${namePrefix}-vnet'
var nsgName = '${namePrefix}-nsg'
var subnetName = 'servers'

var dc1Name = '${namePrefix}-dc1'
var dc2Name = '${namePrefix}-dc2'
var clientName = '${namePrefix}-cl1'

resource nsg 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: nsgName
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

resource vnet 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: vnetName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressSpace
      ]
    }
    subnets: [
      {
        name: subnetName
        properties: {
          addressPrefix: subnetAddressPrefix
          networkSecurityGroup: {
            id: nsg.id
          }
        }
      }
    ]
  }
}

module dc1 './modules/windows-vm.bicep' = {
  name: 'vm-dc1'
  params: {
    location: location
    vmName: dc1Name
    vmSize: serverVmSize
    subnetId: resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, subnetName)
    networkSecurityGroupId: nsg.id
    privateIpAddress: '10.20.1.10'
    adminUsername: adminUsername
    adminPassword: adminPassword
    publisher: 'MicrosoftWindowsServer'
    offer: 'WindowsServer'
    sku: '2022-datacenter-azure-edition'
    createPublicIp: dc1PublicIp
    tags: tags
  }
}

module dc2 './modules/windows-vm.bicep' = {
  name: 'vm-dc2'
  params: {
    location: location
    vmName: dc2Name
    vmSize: serverVmSize
    subnetId: resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, subnetName)
    networkSecurityGroupId: nsg.id
    privateIpAddress: '10.20.1.11'
    adminUsername: adminUsername
    adminPassword: adminPassword
    publisher: 'MicrosoftWindowsServer'
    offer: 'WindowsServer'
    sku: '2022-datacenter-azure-edition'
    createPublicIp: dc2PublicIp
    tags: tags
  }
}

module client './modules/windows-vm.bicep' = {
  name: 'vm-client'
  params: {
    location: location
    vmName: clientName
    vmSize: clientVmSize
    subnetId: resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, subnetName)
    networkSecurityGroupId: nsg.id
    privateIpAddress: '10.20.1.20'
    adminUsername: adminUsername
    adminPassword: adminPassword
    publisher: 'MicrosoftWindowsDesktop'
    offer: 'windows-10'
    sku: 'win10-22h2-pro-g2'
    createPublicIp: clientPublicIp
    tags: tags
  }
}

output virtualNetworkName string = vnet.name
output subnetResourceId string = resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, subnetName)
output dc1VmName string = dc1.outputs.vmName
output dc2VmName string = dc2.outputs.vmName
output clientVmName string = client.outputs.vmName
output dc1PrivateIp string = dc1.outputs.privateIp
output dc2PrivateIp string = dc2.outputs.privateIp
output clientPrivateIp string = client.outputs.privateIp
