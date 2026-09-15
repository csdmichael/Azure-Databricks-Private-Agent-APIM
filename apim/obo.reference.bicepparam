using './obo.bicep'

param apimServiceName = 'caldova-apim-westus'
param tenantId = '12a4b86b-e64c-43f9-af05-d9130a72dfd2'
param apiClientId = 'bdd127ff-fd4c-45f5-b553-ff77a7755161'
param connectorClientId = '8127fb92-0641-4f6e-9d6e-f508e18e9606'
param allowedUserId = '715bb744-31d0-4f76-ac85-7193bcf5a4eb'
param databricksWorkspaceUrl = 'https://adb-7405616934814750.10.azuredatabricks.net'
param genieSpaceId = readEnvironmentVariable('DATABRICKS_GENIE_SPACE_ID')
param brokerUrl = 'https://caldova-genie-obo-fn.azurewebsites.net/api/exchange'
param insightsName = 'caldova-genie-obo-insights'
param oboScope = 'Genie.Access'
param oboRateLimitCalls = 30
param oboRateLimitRenewalPeriodSeconds = 60
param oboBrokerTimeoutSeconds = 20
param apiDisplayName = 'Databricks Genie - delegated user'
param apiDescription = 'Private Genie API with per-user Entra tokens and Databricks token federation.'
param diagnosticSamplingPercentage = 100
