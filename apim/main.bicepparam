using './main.bicep'

param apimServiceName = 'caldova-apim-westus'
param databricksWorkspaceUrl = 'https://adb-7405616934814750.10.azuredatabricks.net'
param databricksWarehouseId = 'a3c7c9526aa58992'
param databricksCatalog = 'caldova_dbx_westus2'
param databricksSchema = 'arrow_semiconductor'
param genieSpaceId = readEnvironmentVariable('DATABRICKS_GENIE_SPACE_ID')
param databricksRateLimitCalls = 60
param genieRateLimitCalls = 30
param rateLimitRenewalPeriodSeconds = 60
param sqlWaitTimeout = '50s'
param databricksApiDisplayName = 'Databricks SQL'
param databricksApiDescription = 'Query the private Databricks warehouse through managed identity authentication.'
param genieApiDisplayName = 'Databricks Genie'
param genieApiDescription = 'Ask natural-language questions of Databricks data through AI/BI Genie.'
param productDisplayName = 'Databricks Agents'
param productDescription = 'APIs and MCP tools for agents over private Databricks.'
param subscriptionDisplayName = 'Databricks Subscription'
