using './main.bicep'

param apimServiceName = 'caldova-apim-westus'
param location = 'westus'
param workspaceName = 'caldova-apim-logs-westus'
param workspaceSkuName = 'PerGB2018'
param retentionInDays = 30
param dailyQuotaGb = 1
param tags = {
  project: 'caldova-databricks-apim-private'
  environment: 'caldova'
  managed_by: 'bicep'
}
