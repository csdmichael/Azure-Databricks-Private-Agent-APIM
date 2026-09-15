@description('Name of the original Microsoft Foundry account.')
param originalFoundryAccountName string = 'foundry-myaacoub'

@description('Name of the project in the original Microsoft Foundry account.')
param originalProjectName string = 'proj-default'

@description('Name of the private-egress Microsoft Foundry account.')
param privateFoundryAccountName string = 'foundry-myaacoub-private'

@description('Name of the project in the private-egress Microsoft Foundry account.')
param privateProjectName string = 'sales-poc'

@description('Name of the existing Log Analytics workspace that receives Foundry diagnostics.')
param logAnalyticsWorkspaceName string = 'caldova-apim-logs-westus'

@description('Name of the existing workspace-based Application Insights component used for agent traces.')
param applicationInsightsName string = 'caldova-genie-obo-insights'

var traceReaderRoleDefinitionIds = [
  '73c42c96-874c-492b-b04d-ab87d138a893' // Log Analytics Reader
  'dbc9c667-e97f-4491-aee6-90b9cf960190' // Privileged Monitoring Data Reader
]

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: logAnalyticsWorkspaceName
}

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' existing = {
  name: applicationInsightsName
}

resource originalFoundryAccount 'Microsoft.CognitiveServices/accounts@2026-05-01' existing = {
  name: originalFoundryAccountName
}

resource originalProject 'Microsoft.CognitiveServices/accounts/projects@2025-06-01' existing = {
  parent: originalFoundryAccount
  name: originalProjectName
}

resource privateFoundryAccount 'Microsoft.CognitiveServices/accounts@2026-05-01' existing = {
  name: privateFoundryAccountName
}

resource privateProject 'Microsoft.CognitiveServices/accounts/projects@2025-06-01' existing = {
  parent: privateFoundryAccount
  name: privateProjectName
}

resource originalAccountInsightsConnection 'Microsoft.CognitiveServices/accounts/connections@2025-04-01-preview' = {
  parent: originalFoundryAccount
  name: applicationInsightsName
  properties: {
    category: 'AppInsights'
    target: applicationInsights.id
    authType: 'ApiKey'
    isSharedToAll: true
    credentials: {
      key: applicationInsights.properties.ConnectionString
    }
    metadata: {
      ApiType: 'Azure'
      ResourceId: applicationInsights.id
    }
  }
}

resource privateAccountInsightsConnection 'Microsoft.CognitiveServices/accounts/connections@2025-04-01-preview' = {
  parent: privateFoundryAccount
  name: applicationInsightsName
  properties: {
    category: 'AppInsights'
    target: applicationInsights.id
    authType: 'ApiKey'
    isSharedToAll: true
    credentials: {
      key: applicationInsights.properties.ConnectionString
    }
    metadata: {
      ApiType: 'Azure'
      ResourceId: applicationInsights.id
    }
  }
}

resource originalProjectTraceReaders 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for roleDefinitionId in traceReaderRoleDefinitionIds: {
  scope: applicationInsights
  name: guid(applicationInsights.id, originalProject.id, roleDefinitionId)
  properties: {
    principalId: originalProject.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitionId)
  }
}]

resource privateProjectTraceReaders 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for roleDefinitionId in traceReaderRoleDefinitionIds: {
  scope: applicationInsights
  name: guid(applicationInsights.id, privateProject.id, roleDefinitionId)
  properties: {
    principalId: privateProject.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitionId)
  }
}]

resource originalProjectDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: '${originalFoundryAccountName}-${originalProjectName}-logs'
  scope: originalProject
  properties: {
    workspaceId: workspace.id
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

resource privateProjectDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: '${privateFoundryAccountName}-${privateProjectName}-logs'
  scope: privateProject
  properties: {
    workspaceId: workspace.id
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

output logAnalyticsWorkspaceId string = workspace.id
output applicationInsightsId string = applicationInsights.id
output originalProjectId string = originalProject.id
output privateProjectId string = privateProject.id
