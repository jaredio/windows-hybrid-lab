targetScope = 'resourceGroup'

// ── Region ──────────────────────────────────────────────────────────────────
@description('Primary Azure region for Houston resources.')
param location string = resourceGroup().location

@description('Optional region override for West resources. Uses location when empty.')
param westLocation string = ''

// ── Credentials ─────────────────────────────────────────────────────────────
@description('Local administrator username for all VMs.')
param adminUsername string = 'labadmin'

@secure()
@minLength(12)
@description('Local administrator password for all VMs.')
param adminPassword string

// ── Networking ──────────────────────────────────────────────────────────────
@description('Public source CIDR allowed for RDP (3389). Set to your public IP for security.')
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

// ── VM sizing ───────────────────────────────────────────────────────────────
@description('VM size for domain controllers.')
param domainControllerVmSize string = 'Standard_B2ms'

@description('VM size for member VMs.')
param memberVmSize string = 'Standard_B2s'

// ── VM names ────────────────────────────────────────────────────────────────
@description('Name of the Houston primary domain controller.')
param houstonDc1Name string = 'HOUSTONDC1'

@description('Name of the Houston replica domain controller.')
param houstonDc2Name string = 'HOUSTONDC2'

@description('Name of the West domain controller.')
param westDc1Name string = 'WESTDC1'

@description('Name of the first Houston member VM.')
param houstonVm1Name string = 'HOUSTONVM1'

@description('Name of the second Houston member VM.')
param houstonVm2Name string = 'HOUSTONVM2'

@description('Name of the Houston file server.')
param houstonFs1Name string = 'HOUSTONFS1'

@description('Name of the Houston DHCP/WSUS server.')
param houstonDhcp1Name string = 'HOUSTONDHCP1'

@description('Name of the Entra Connect sync server.')
param houstonAac1Name string = 'HOUSTAAC1'

@description('Name of the West file server.')
param westFs1Name string = 'WESTFS1'

// ── Private IPs ─────────────────────────────────────────────────────────────
@description('Private IP address for HOUSTONDC1.')
param houstonDc1Ip string = '10.20.1.10'

@description('Private IP address for HOUSTONDC2.')
param houstonDc2Ip string = '10.20.1.11'

@description('Private IP address for WESTDC1.')
param westDc1Ip string = '10.30.1.10'

@description('Private IP address for HOUSTONVM1.')
param houstonVm1Ip string = '10.20.1.20'

@description('Private IP address for HOUSTONVM2.')
param houstonVm2Ip string = '10.20.1.21'

@description('Private IP address for HOUSTONFS1.')
param houstonFs1Ip string = '10.20.1.30'

@description('Private IP address for HOUSTONDHCP1.')
param houstonDhcp1Ip string = '10.20.1.40'

@description('Private IP address for HOUSTAAC1.')
param houstonAac1Ip string = '10.20.1.50'

@description('Private IP address for WESTFS1.')
param westFs1Ip string = '10.30.1.20'

// ── Public IP toggles ──────────────────────────────────────────────────────
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

@description('Whether HOUSTONFS1 gets a public IP.')
param houstonFs1PublicIp bool = false

@description('Whether HOUSTONDHCP1 gets a public IP.')
param houstonDhcp1PublicIp bool = false

@description('Whether HOUSTAAC1 gets a public IP.')
param houstonAac1PublicIp bool = false

@description('Whether WESTFS1 gets a public IP.')
param westFs1PublicIp bool = false

// ── AD DS role ──────────────────────────────────────────────────────────────
@allowed(['WritableReplica', 'RODC'])
@description('Role for HOUSTONDC2: writable replica DC or Read-Only Domain Controller.')
param houstonDc2Role string = 'WritableReplica'

// ── Bastion ─────────────────────────────────────────────────────────────────
@description('Deploy Azure Bastion for secure RDP access (replaces public IP RDP).')
param deployBastion bool = true

@description('Address prefix for the AzureBastionSubnet. Must be /26 or larger within Houston VNet.')
param bastionSubnetPrefix string = '10.20.0.0/26'

// ── DC Promotion ────────────────────────────────────────────────────────────
@description('Automatically promote DCs and join member VMs via CustomScriptExtension.')
param enableDCPromotion bool = false

@description('FQDN for the Houston forest root domain.')
param houstonDomainName string = 'lab.local'

@description('NetBIOS name for the Houston domain.')
param houstonNetbiosName string = 'LAB'

@description('FQDN for the West forest root domain.')
param westDomainName string = 'west.lab.local'

@description('NetBIOS name for the West domain.')
param westNetbiosName string = 'WEST'

@description('AD site name used during automated DC promotion.')
param dcPromotionSiteName string = 'Default-First-Site-Name'

// ── Monitoring ──────────────────────────────────────────────────────────────
@description('Deploy Log Analytics workspace and Azure Monitor Agent for centralized logging.')
param deployMonitoring bool = true

@description('Log Analytics workspace retention in days.')
param logAnalyticsRetentionDays int = 30

@description('Email address for Azure Monitor alert notifications. Leave empty to skip alert deployment.')
param alertEmailAddress string = ''

// ── Tags ────────────────────────────────────────────────────────────────────
@description('Tags applied to all resources.')
param tags object = {
  workload: 'windows-hybrid-lab'
  managedBy: 'bicep'
  project: 'windows-hybrid-lab'
}

// ── Variables ───────────────────────────────────────────────────────────────
var resolvedWestLocation = empty(westLocation) ? location : westLocation

// ── DC Promotion Scripts ────────────────────────────────────────────────────
// Triple-quoted strings (''') avoid Bicep quoting issues. replace() substitutes params.

var houstonDc1Template = '''powershell -ExecutionPolicy Bypass -Command "Install-WindowsFeature AD-Domain-Services, DNS -IncludeManagementTools; Import-Module ADDSDeployment; $pw = ConvertTo-SecureString '__PASSWORD__' -AsPlainText -Force; Install-ADDSForest -DomainName '__DOMAIN__' -DomainNetbiosName '__NETBIOS__' -InstallDNS -SafeModeAdministratorPassword $pw -NoRebootOnCompletion -Force; Add-DnsServerPrimaryZone -NetworkId '10.20.1.0/24' -ReplicationScope Forest -ErrorAction SilentlyContinue; shutdown /r /t 15 /f"'''

var westDc1Template = '''powershell -ExecutionPolicy Bypass -Command "Install-WindowsFeature AD-Domain-Services, DNS -IncludeManagementTools; Import-Module ADDSDeployment; $pw = ConvertTo-SecureString '__PASSWORD__' -AsPlainText -Force; Install-ADDSForest -DomainName '__DOMAIN__' -DomainNetbiosName '__NETBIOS__' -InstallDNS -SafeModeAdministratorPassword $pw -NoRebootOnCompletion -Force; Add-DnsServerPrimaryZone -NetworkId '10.30.1.0/24' -ReplicationScope Forest -ErrorAction SilentlyContinue; shutdown /r /t 15 /f"'''

var houstonDc2RodcTemplate = '''powershell -ExecutionPolicy Bypass -Command "$ifIndex = (Get-NetAdapter | Where-Object { $_.Status -eq 'Up' } | Select-Object -First 1 -ExpandProperty ifIndex); if ($ifIndex) { Set-DnsClientServerAddress -InterfaceIndex $ifIndex -ServerAddresses __DC1IP__ }; Install-WindowsFeature AD-Domain-Services, DNS -IncludeManagementTools; Import-Module ADDSDeployment; $pw = ConvertTo-SecureString '__PASSWORD__' -AsPlainText -Force; $cred = New-Object System.Management.Automation.PSCredential('__NETBIOS__\__USER__', $pw); $retries = 0; while ($retries -lt 10) { try { Install-ADDSDomainController -DomainName '__DOMAIN__' -Credential $cred -ReadOnlyReplica -InstallDNS -SafeModeAdministratorPassword $pw -SiteName '__SITENAME__' -NoRebootOnCompletion -Force; break } catch { $retries++; Start-Sleep -Seconds 30 } }; shutdown /r /t 15 /f"'''

var houstonDc2ReplicaTemplate = '''powershell -ExecutionPolicy Bypass -Command "$ifIndex = (Get-NetAdapter | Where-Object { $_.Status -eq 'Up' } | Select-Object -First 1 -ExpandProperty ifIndex); if ($ifIndex) { Set-DnsClientServerAddress -InterfaceIndex $ifIndex -ServerAddresses __DC1IP__ }; Install-WindowsFeature AD-Domain-Services, DNS -IncludeManagementTools; Import-Module ADDSDeployment; $pw = ConvertTo-SecureString '__PASSWORD__' -AsPlainText -Force; $cred = New-Object System.Management.Automation.PSCredential('__NETBIOS__\__USER__', $pw); $retries = 0; while ($retries -lt 10) { try { Install-ADDSDomainController -DomainName '__DOMAIN__' -Credential $cred -InstallDNS -SafeModeAdministratorPassword $pw -NoRebootOnCompletion -Force; break } catch { $retries++; Start-Sleep -Seconds 30 } }; shutdown /r /t 15 /f"'''

var domainJoinTemplate = '''powershell -ExecutionPolicy Bypass -Command "$ifIndex = (Get-NetAdapter | Where-Object { $_.Status -eq 'Up' } | Select-Object -First 1 -ExpandProperty ifIndex); if ($ifIndex) { Set-DnsClientServerAddress -InterfaceIndex $ifIndex -ServerAddresses __DC1IP__ }; $pw = ConvertTo-SecureString '__PASSWORD__' -AsPlainText -Force; $cred = New-Object System.Management.Automation.PSCredential('__NETBIOS__\__USER__', $pw); $retries = 0; $joined = $false; while ($retries -lt 10 -and -not $joined) { try { Add-Computer -DomainName '__DOMAIN__' -Credential $cred -Force; $joined = $true } catch { $retries++; Start-Sleep -Seconds 30 } }; if ($joined) { shutdown /r /t 15 /f }"'''

// #disable-next-line secure-parameter-in-expression
var houstonDc1Script = enableDCPromotion ? replace(replace(replace(houstonDc1Template, '__PASSWORD__', adminPassword), '__DOMAIN__', houstonDomainName), '__NETBIOS__', houstonNetbiosName) : ''

// #disable-next-line secure-parameter-in-expression
var westDc1Script = enableDCPromotion ? replace(replace(replace(westDc1Template, '__PASSWORD__', adminPassword), '__DOMAIN__', westDomainName), '__NETBIOS__', westNetbiosName) : ''

// #disable-next-line secure-parameter-in-expression
var houstonDc2Script = enableDCPromotion ? (houstonDc2Role == 'RODC'
  ? replace(replace(replace(replace(replace(replace(houstonDc2RodcTemplate, '__DC1IP__', houstonDc1Ip), '__PASSWORD__', adminPassword), '__NETBIOS__', houstonNetbiosName), '__USER__', adminUsername), '__DOMAIN__', houstonDomainName), '__SITENAME__', dcPromotionSiteName)
  : replace(replace(replace(replace(replace(houstonDc2ReplicaTemplate, '__DC1IP__', houstonDc1Ip), '__PASSWORD__', adminPassword), '__NETBIOS__', houstonNetbiosName), '__USER__', adminUsername), '__DOMAIN__', houstonDomainName)) : ''

// #disable-next-line secure-parameter-in-expression
var domainJoinScript = enableDCPromotion ? replace(replace(replace(replace(replace(domainJoinTemplate, '__DC1IP__', houstonDc1Ip), '__PASSWORD__', adminPassword), '__NETBIOS__', houstonNetbiosName), '__USER__', adminUsername), '__DOMAIN__', houstonDomainName) : ''

// #disable-next-line secure-parameter-in-expression
var westDomainJoinScript = enableDCPromotion ? replace(replace(replace(replace(replace(domainJoinTemplate, '__DC1IP__', westDc1Ip), '__PASSWORD__', adminPassword), '__NETBIOS__', westNetbiosName), '__USER__', adminUsername), '__DOMAIN__', westDomainName) : ''

// ═══════════════════════════════════════════════════════════════════════════
// Networking (VNets, NSGs, Peering)
// ═══════════════════════════════════════════════════════════════════════════

module networking './modules/networking.bicep' = {
  name: 'networking'
  params: {
    location: location
    westLocation: resolvedWestLocation
    houstonVnetName: houstonVnetName
    houstonAddressSpace: houstonAddressSpace
    houstonSubnetPrefix: houstonSubnetPrefix
    westVnetName: westVnetName
    westAddressSpace: westAddressSpace
    westSubnetPrefix: westSubnetPrefix
    allowedSourceAddressPrefix: allowedSourceAddressPrefix
    deployBastionSubnet: deployBastion
    bastionSubnetPrefix: bastionSubnetPrefix
    tags: tags
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Azure Bastion
// ═══════════════════════════════════════════════════════════════════════════

module bastion './modules/bastion.bicep' = if (deployBastion) {
  name: 'bastion'
  params: {
    location: location
    namePrefix: houstonVnetName
    bastionSubnetId: networking.outputs.bastionSubnetId
    tags: tags
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Monitoring (Log Analytics, DCR, Alerts)
// ═══════════════════════════════════════════════════════════════════════════

module monitoring './modules/monitoring.bicep' = if (deployMonitoring) {
  name: 'monitoring'
  params: {
    location: location
    retentionDays: logAnalyticsRetentionDays
    alertEmailAddress: alertEmailAddress
    tags: tags
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Virtual Machines
// ═══════════════════════════════════════════════════════════════════════════

module houstonDc1 './modules/windows-vm.bicep' = {
  name: 'vm-houston-dc1'
  params: {
    location: location
    vmName: houstonDc1Name
    vmSize: domainControllerVmSize
    subnetId: networking.outputs.houstonSubnetId
    privateIpAddress: houstonDc1Ip
    adminUsername: adminUsername
    adminPassword: adminPassword
    publisher: 'MicrosoftWindowsServer'
    offer: 'WindowsServer'
    sku: '2022-datacenter-azure-edition'
    createPublicIp: houstonDc1PublicIp
    tags: tags
    commandToExecute: houstonDc1Script
    enableSystemIdentity: deployMonitoring
    enableAma: deployMonitoring
    dataCollectionRuleId: deployMonitoring ? monitoring.outputs.dcrId : ''
  }
}

module houstonDc2 './modules/windows-vm.bicep' = {
  name: 'vm-houston-dc2'
  dependsOn: [
    houstonDc1
  ]
  params: {
    location: location
    vmName: houstonDc2Name
    vmSize: domainControllerVmSize
    subnetId: networking.outputs.houstonSubnetId
    privateIpAddress: houstonDc2Ip
    adminUsername: adminUsername
    adminPassword: adminPassword
    publisher: 'MicrosoftWindowsServer'
    offer: 'WindowsServer'
    sku: '2022-datacenter-azure-edition'
    createPublicIp: houstonDc2PublicIp
    tags: union(tags, { adRole: houstonDc2Role })
    commandToExecute: houstonDc2Script
    enableSystemIdentity: deployMonitoring
    enableAma: deployMonitoring
    dataCollectionRuleId: deployMonitoring ? monitoring.outputs.dcrId : ''
  }
}

module westDc1 './modules/windows-vm.bicep' = {
  name: 'vm-west-dc1'
  params: {
    location: resolvedWestLocation
    vmName: westDc1Name
    vmSize: domainControllerVmSize
    subnetId: networking.outputs.westSubnetId
    privateIpAddress: westDc1Ip
    adminUsername: adminUsername
    adminPassword: adminPassword
    publisher: 'MicrosoftWindowsServer'
    offer: 'WindowsServer'
    sku: '2022-datacenter-azure-edition'
    createPublicIp: westDc1PublicIp
    tags: tags
    commandToExecute: westDc1Script
    enableSystemIdentity: deployMonitoring
    enableAma: deployMonitoring
    dataCollectionRuleId: deployMonitoring ? monitoring.outputs.dcrId : ''
  }
}

module houstonVm1 './modules/windows-vm.bicep' = {
  name: 'vm-houston-vm1'
  dependsOn: [
    houstonDc1
  ]
  params: {
    location: location
    vmName: houstonVm1Name
    vmSize: memberVmSize
    subnetId: networking.outputs.houstonSubnetId
    privateIpAddress: houstonVm1Ip
    adminUsername: adminUsername
    adminPassword: adminPassword
    publisher: 'MicrosoftWindowsServer'
    offer: 'WindowsServer'
    sku: '2022-datacenter-azure-edition'
    createPublicIp: houstonVm1PublicIp
    tags: tags
    commandToExecute: domainJoinScript
    enableSystemIdentity: deployMonitoring
    enableAma: deployMonitoring
    dataCollectionRuleId: deployMonitoring ? monitoring.outputs.dcrId : ''
  }
}

module houstonVm2 './modules/windows-vm.bicep' = {
  name: 'vm-houston-vm2'
  dependsOn: [
    houstonDc1
  ]
  params: {
    location: location
    vmName: houstonVm2Name
    vmSize: memberVmSize
    subnetId: networking.outputs.houstonSubnetId
    privateIpAddress: houstonVm2Ip
    adminUsername: adminUsername
    adminPassword: adminPassword
    publisher: 'MicrosoftWindowsServer'
    offer: 'WindowsServer'
    sku: '2022-datacenter-azure-edition'
    createPublicIp: houstonVm2PublicIp
    tags: tags
    commandToExecute: domainJoinScript
    enableSystemIdentity: deployMonitoring
    enableAma: deployMonitoring
    dataCollectionRuleId: deployMonitoring ? monitoring.outputs.dcrId : ''
  }
}

module houstonFs1 './modules/windows-vm.bicep' = {
  name: 'vm-houston-fs1'
  dependsOn: [
    houstonDc1
  ]
  params: {
    location: location
    vmName: houstonFs1Name
    vmSize: memberVmSize
    subnetId: networking.outputs.houstonSubnetId
    privateIpAddress: houstonFs1Ip
    adminUsername: adminUsername
    adminPassword: adminPassword
    publisher: 'MicrosoftWindowsServer'
    offer: 'WindowsServer'
    sku: '2022-datacenter-azure-edition'
    createPublicIp: houstonFs1PublicIp
    tags: tags
    commandToExecute: domainJoinScript
    enableSystemIdentity: deployMonitoring
    enableAma: deployMonitoring
    dataCollectionRuleId: deployMonitoring ? monitoring.outputs.dcrId : ''
  }
}

module houstonDhcp1 './modules/windows-vm.bicep' = {
  name: 'vm-houston-dhcp1'
  dependsOn: [
    houstonDc1
  ]
  params: {
    location: location
    vmName: houstonDhcp1Name
    vmSize: memberVmSize
    subnetId: networking.outputs.houstonSubnetId
    privateIpAddress: houstonDhcp1Ip
    adminUsername: adminUsername
    adminPassword: adminPassword
    publisher: 'MicrosoftWindowsServer'
    offer: 'WindowsServer'
    sku: '2022-datacenter-azure-edition'
    createPublicIp: houstonDhcp1PublicIp
    tags: tags
    commandToExecute: domainJoinScript
    enableSystemIdentity: deployMonitoring
    enableAma: deployMonitoring
    dataCollectionRuleId: deployMonitoring ? monitoring.outputs.dcrId : ''
  }
}

module houstonAac1 './modules/windows-vm.bicep' = {
  name: 'vm-houston-aac1'
  dependsOn: [
    houstonDc1
  ]
  params: {
    location: location
    vmName: houstonAac1Name
    vmSize: memberVmSize
    subnetId: networking.outputs.houstonSubnetId
    privateIpAddress: houstonAac1Ip
    adminUsername: adminUsername
    adminPassword: adminPassword
    publisher: 'MicrosoftWindowsServer'
    offer: 'WindowsServer'
    sku: '2022-datacenter-azure-edition'
    createPublicIp: houstonAac1PublicIp
    tags: tags
    commandToExecute: domainJoinScript
    enableSystemIdentity: deployMonitoring
    enableAma: deployMonitoring
    dataCollectionRuleId: deployMonitoring ? monitoring.outputs.dcrId : ''
  }
}

module westFs1 './modules/windows-vm.bicep' = {
  name: 'vm-west-fs1'
  dependsOn: [
    westDc1
  ]
  params: {
    location: resolvedWestLocation
    vmName: westFs1Name
    vmSize: memberVmSize
    subnetId: networking.outputs.westSubnetId
    privateIpAddress: westFs1Ip
    adminUsername: adminUsername
    adminPassword: adminPassword
    publisher: 'MicrosoftWindowsServer'
    offer: 'WindowsServer'
    sku: '2022-datacenter-azure-edition'
    createPublicIp: westFs1PublicIp
    tags: tags
    commandToExecute: westDomainJoinScript
    enableSystemIdentity: deployMonitoring
    enableAma: deployMonitoring
    dataCollectionRuleId: deployMonitoring ? monitoring.outputs.dcrId : ''
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Outputs
// ═══════════════════════════════════════════════════════════════════════════

output houstonVnetResourceId string = networking.outputs.houstonVnetId
output westVnetResourceId string = networking.outputs.westVnetId
output houstonPeeringName string = networking.outputs.houstonPeeringName
output westPeeringName string = networking.outputs.westPeeringName
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
output houstonFs1VmName string = houstonFs1.outputs.vmName
output houstonDhcp1VmName string = houstonDhcp1.outputs.vmName
output houstonAac1VmName string = houstonAac1.outputs.vmName
output westFs1VmName string = westFs1.outputs.vmName
output houstonFs1PrivateIp string = houstonFs1.outputs.privateIp
output houstonDhcp1PrivateIp string = houstonDhcp1.outputs.privateIp
output houstonAac1PrivateIp string = houstonAac1.outputs.privateIp
output westFs1PrivateIp string = westFs1.outputs.privateIp
output bastionName string = deployBastion ? bastion.outputs.bastionName : ''
output logAnalyticsWorkspaceId string = deployMonitoring ? monitoring.outputs.lawId : ''
output logAnalyticsWorkspaceName string = deployMonitoring ? monitoring.outputs.lawName : ''
