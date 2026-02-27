param location string
param vmName string
param vmSize string = 'Standard_B2ms'
param subnetId string
param privateIpAddress string
param adminUsername string
@secure()
param adminPassword string
param publisher string
param offer string
param sku string
param imageVersion string = 'latest'
param createPublicIp bool = false
param tags object = {}

@description('PowerShell command to run via CustomScriptExtension. Empty string skips the extension.')
param commandToExecute string = ''

@description('Assign a system-managed identity to the VM (required for Azure Monitor Agent).')
param enableSystemIdentity bool = false

@description('Deploy the Azure Monitor Agent extension.')
param enableAma bool = false

@description('Resource ID of the Data Collection Rule to associate with the VM.')
param dataCollectionRuleId string = ''

resource publicIp 'Microsoft.Network/publicIPAddresses@2023-09-01' = if (createPublicIp) {
  name: '${vmName}-pip'
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource nic 'Microsoft.Network/networkInterfaces@2023-09-01' = {
  name: '${vmName}-nic'
  location: location
  tags: tags
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: subnetId
          }
          privateIPAllocationMethod: 'Static'
          privateIPAddress: privateIpAddress
          publicIPAddress: createPublicIp ? {
            id: publicIp.id
          } : null
        }
      }
    ]
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2023-09-01' = {
  name: vmName
  location: location
  tags: tags
  identity: enableSystemIdentity ? {
    type: 'SystemAssigned'
  } : null
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      adminPassword: adminPassword
    }
    storageProfile: {
      imageReference: {
        publisher: publisher
        offer: offer
        sku: sku
        version: imageVersion
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'StandardSSD_LRS'
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
        }
      ]
    }
  }
}

resource cse 'Microsoft.Compute/virtualMachines/extensions@2023-09-01' = if (!empty(commandToExecute)) {
  parent: vm
  name: 'CustomScriptExtension'
  location: location
  tags: tags
  properties: {
    publisher: 'Microsoft.Compute'
    type: 'CustomScriptExtension'
    typeHandlerVersion: '1.10'
    autoUpgradeMinorVersion: true
    protectedSettings: {
      commandToExecute: commandToExecute
    }
  }
}

resource ama 'Microsoft.Compute/virtualMachines/extensions@2023-09-01' = if (enableAma) {
  parent: vm
  name: 'AzureMonitorWindowsAgent'
  location: location
  tags: tags
  properties: {
    publisher: 'Microsoft.Azure.Monitor'
    type: 'AzureMonitorWindowsAgent'
    typeHandlerVersion: '1.0'
    autoUpgradeMinorVersion: true
    enableAutomaticUpgrade: true
  }
  dependsOn: [
    cse
  ]
}

resource dcrAssociation 'Microsoft.Insights/dataCollectionRuleAssociations@2022-06-01' = if (!empty(dataCollectionRuleId)) {
  name: '${vmName}-dcr-association'
  scope: vm
  properties: {
    dataCollectionRuleId: dataCollectionRuleId
  }
  dependsOn: [
    ama
  ]
}

// Module outputs support post-deployment scripting and evidence collection.
output vmId string = vm.id
output vmName string = vm.name
output nicId string = nic.id
output privateIp string = privateIpAddress
output publicIpResourceId string = createPublicIp ? publicIp.id : ''
