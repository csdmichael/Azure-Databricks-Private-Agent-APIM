@description('Existing API Management service to collect diagnostics from.')
param apimServiceName string = 'caldova-apim-westus'

@description('Azure region for the Log Analytics workspace. Keep it with API Management.')
param location string = 'westus'

@description('Log Analytics workspace name.')
param workspaceName string = 'caldova-apim-logs-westus'

@description('Retention in days for the workspace.')
@minValue(30)
@maxValue(730)
param retentionInDays int = 30

@description('Daily ingestion cap in GB. -1 disables the cap.')
param dailyQuotaGb int = 1

param tags object = {
  project: 'caldova-databricks-apim-private'
  environment: 'caldova'
  managed_by: 'bicep'
}

resource apim 'Microsoft.ApiManagement/service@2024-05-01' existing = {
  name: apimServiceName
}

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: workspaceName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: retentionInDays
    workspaceCapping: {
      dailyQuotaGb: dailyQuotaGb
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

// Diagnostic settings are an extension resource, so the APIM service is the scope.
resource apimDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: '${apimServiceName}-to-log-analytics'
  scope: apim
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

output workspaceName string = workspace.name
output workspaceResourceId string = workspace.id
output workspaceCustomerId string = workspace.properties.customerId
output diagnosticSettingName string = apimDiagnostics.name
