targetScope = 'resourceGroup'

// ── Parameters ────────────────────────────────────────────────────────

@description('Azure region for monitoring resources.')
param location string

@description('Log Analytics workspace retention in days.')
param retentionDays int = 30

@description('Email address for alert notifications. Leave empty to skip alert deployment.')
param alertEmailAddress string = ''

@description('Tags applied to all resources.')
param tags object = {}

// ── Variables ─────────────────────────────────────────────────────────

var deployAlerts = !empty(alertEmailAddress)

// ═══════════════════════════════════════════════════════════════════════
// Log Analytics Workspace
// ═══════════════════════════════════════════════════════════════════════

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: 'law-${uniqueString(resourceGroup().id)}'
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: retentionDays
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Data Collection Rule
// ═══════════════════════════════════════════════════════════════════════

resource dcr 'Microsoft.Insights/dataCollectionRules@2022-06-01' = {
  name: 'dcr-windows-lab'
  location: location
  tags: tags
  properties: {
    dataSources: {
      windowsEventLogs: [
        {
          name: 'applicationEvents'
          streams: ['Microsoft-Event']
          xPathQueries: [
            'Application!*[System[(Level=1 or Level=2 or Level=3 or Level=4)]]'
          ]
        }
        {
          name: 'systemEvents'
          streams: ['Microsoft-Event']
          xPathQueries: [
            'System!*[System[(Level=1 or Level=2 or Level=3 or Level=4)]]'
          ]
        }
        {
          name: 'securityEvents'
          streams: ['Microsoft-Event']
          xPathQueries: [
            'Security!*[System[(band(Keywords,13510798882111488))]]'
          ]
        }
      ]
      performanceCounters: [
        {
          name: 'perfCounters'
          streams: ['Microsoft-Perf']
          samplingFrequencyInSeconds: 60
          counterSpecifiers: [
            '\\Processor Information(_Total)\\% Processor Time'
            '\\Memory\\Available MBytes'
            '\\Memory\\% Committed Bytes In Use'
            '\\LogicalDisk(_Total)\\% Free Space'
            '\\LogicalDisk(_Total)\\Avg. Disk sec/Read'
            '\\LogicalDisk(_Total)\\Avg. Disk sec/Write'
            '\\Network Interface(*)\\Bytes Total/sec'
          ]
        }
      ]
    }
    destinations: {
      logAnalytics: [
        {
          name: 'logAnalyticsDest'
          workspaceResourceId: logAnalyticsWorkspace.id
        }
      ]
    }
    dataFlows: [
      {
        streams: ['Microsoft-Event']
        destinations: ['logAnalyticsDest']
      }
      {
        streams: ['Microsoft-Perf']
        destinations: ['logAnalyticsDest']
      }
    ]
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Action Group (for alert notifications)
// ═══════════════════════════════════════════════════════════════════════

resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = if (deployAlerts) {
  name: 'ag-lab-alerts'
  location: 'global'
  tags: tags
  properties: {
    groupShortName: 'LabAlerts'
    enabled: true
    emailReceivers: [
      {
        name: 'LabAdmin'
        emailAddress: alertEmailAddress
        useCommonAlertSchema: true
      }
    ]
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Alert: VM Heartbeat Loss
// ═══════════════════════════════════════════════════════════════════════

resource heartbeatAlert 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = if (deployAlerts) {
  name: 'alert-vm-heartbeat-loss'
  location: location
  tags: tags
  properties: {
    displayName: 'VM Heartbeat Loss'
    description: 'Fires when a VM stops sending heartbeats for 5+ minutes.'
    severity: 1
    enabled: true
    evaluationFrequency: 'PT5M'
    windowSize: 'PT5M'
    scopes: [
      logAnalyticsWorkspace.id
    ]
    criteria: {
      allOf: [
        {
          query: 'Heartbeat | summarize LastHeartbeat = max(TimeGenerated) by Computer | where LastHeartbeat < ago(5m)'
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
        }
      ]
    }
    actions: {
      actionGroups: [
        actionGroup.id
      ]
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Alert: High CPU (> 90% for 5 minutes)
// ═══════════════════════════════════════════════════════════════════════

resource cpuAlert 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = if (deployAlerts) {
  name: 'alert-high-cpu'
  location: location
  tags: tags
  properties: {
    displayName: 'High CPU Usage'
    description: 'Fires when CPU exceeds 90% sustained for 5 minutes.'
    severity: 2
    enabled: true
    evaluationFrequency: 'PT5M'
    windowSize: 'PT5M'
    scopes: [
      logAnalyticsWorkspace.id
    ]
    criteria: {
      allOf: [
        {
          query: 'Perf | where ObjectName == "Processor Information" and CounterName == "% Processor Time" and InstanceName == "_Total" | summarize AvgCPU = avg(CounterValue) by Computer, bin(TimeGenerated, 5m) | where AvgCPU > 90'
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
        }
      ]
    }
    actions: {
      actionGroups: [
        actionGroup.id
      ]
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Alert: Low Disk Space (< 10% free)
// ═══════════════════════════════════════════════════════════════════════

resource diskAlert 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = if (deployAlerts) {
  name: 'alert-low-disk-space'
  location: location
  tags: tags
  properties: {
    displayName: 'Low Disk Space'
    description: 'Fires when any logical disk drops below 10% free space.'
    severity: 2
    enabled: true
    evaluationFrequency: 'PT15M'
    windowSize: 'PT15M'
    scopes: [
      logAnalyticsWorkspace.id
    ]
    criteria: {
      allOf: [
        {
          query: 'Perf | where ObjectName == "LogicalDisk" and CounterName == "% Free Space" and InstanceName == "_Total" | summarize MinFree = min(CounterValue) by Computer, bin(TimeGenerated, 15m) | where MinFree < 10'
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
        }
      ]
    }
    actions: {
      actionGroups: [
        actionGroup.id
      ]
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Alert: Account Lockout (Security Event 4740)
// ═══════════════════════════════════════════════════════════════════════

resource lockoutAlert 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = if (deployAlerts) {
  name: 'alert-account-lockout'
  location: location
  tags: tags
  properties: {
    displayName: 'Account Lockout Detected'
    description: 'Fires when an account lockout event (4740) is logged.'
    severity: 3
    enabled: true
    evaluationFrequency: 'PT5M'
    windowSize: 'PT5M'
    scopes: [
      logAnalyticsWorkspace.id
    ]
    criteria: {
      allOf: [
        {
          query: 'Event | where EventLog == "Security" and EventID == 4740'
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
        }
      ]
    }
    actions: {
      actionGroups: [
        actionGroup.id
      ]
    }
  }
}

// ── Outputs ───────────────────────────────────────────────────────────

output lawId string = logAnalyticsWorkspace.id
output lawName string = logAnalyticsWorkspace.name
output dcrId string = dcr.id
