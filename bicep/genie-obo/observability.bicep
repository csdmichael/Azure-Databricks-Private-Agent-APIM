param location string = 'westus2'
param insightsName string = 'caldova-genie-obo-insights'
param workspaceName string = 'caldova-apim-logs-westus'
param showcasePrincipalId string

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = { name: workspaceName }
resource insights 'Microsoft.Insights/components@2020-02-02' = {
  name: insightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: workspace.id
    IngestionMode: 'LogAnalytics'
    RetentionInDays: 90
    DisableIpMasking: false
    SamplingPercentage: 100
  }
}
resource queryRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: workspace
  name: guid(workspace.id, showcasePrincipalId, 'log-reader')
  properties: {
    principalId: showcasePrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '73c42c96-874c-492b-b04d-ab87d138a893')
  }
}
output insightsResourceId string = insights.id
output workspaceId string = workspace.properties.customerId
