using './observability.bicep'

param location = 'westus2'
param insightsName = 'caldova-genie-obo-insights'
param workspaceName = 'caldova-apim-logs-westus'
param showcasePrincipalId = 'f10124fb-9db1-4a6c-b80a-6164254a4cb6'
param retentionInDays = 90
param samplingPercentage = 100
