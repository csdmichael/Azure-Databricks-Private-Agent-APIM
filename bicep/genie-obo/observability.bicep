@description('Azure region for the Application Insights component.')
param location string

@description('Application Insights component name.')
param insightsName string

@description('Existing Log Analytics workspace name.')
param workspaceName string

@description('Principal ID granted permission to query the workspace.')
param showcasePrincipalId string

@description('Application Insights retention in days.')
@minValue(30)
@maxValue(730)
param retentionInDays int

@description('Application Insights sampling percentage.')
@minValue(0)
@maxValue(100)
param samplingPercentage int

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = { name: workspaceName }
resource insights 'Microsoft.Insights/components@2020-02-02' = {
  name: insightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: workspace.id
    IngestionMode: 'LogAnalytics'
    RetentionInDays: retentionInDays
    DisableIpMasking: false
    SamplingPercentage: samplingPercentage
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
