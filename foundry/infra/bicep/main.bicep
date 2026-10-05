targetScope = 'resourceGroup'

@description('Azure region for the bot application and monitoring resources.')
param location string = resourceGroup().location

@description('Existing Microsoft Foundry account name.')
param foundryAccountName string

@description('Existing Microsoft Foundry project name.')
param foundryProjectName string

@description('Existing API Management service name.')
param apimName string

@description('Existing delegated Databricks Genie API identifier.')
param oboSourceApiId string = 'databricks-genie-obo'

@description('MCP API identifier created over the delegated Genie API.')
param oboMcpApiId string = 'databricks-genie-obo-mcp'

@description('MCP gateway path.')
param oboMcpPath string = 'databricks-genie-obo-mcp'

@description('Microsoft Entra tenant ID.')
param tenantId string

@description('Client ID of the single-tenant bot application registration.')
param botClientId string

@secure()
@description('Client secret of the bot application registration.')
param botClientSecret string

@description('Azure Bot resource name.')
param botName string

@description('Linux web app name that hosts the Teams-to-Foundry bridge.')
param botAppName string

@description('Existing Linux App Service plan name.')
param appServicePlanName string = 'caldova-tokenomics-api-plan'

@description('Application Insights name.')
param applicationInsightsName string = '${botAppName}-insights'

@description('Azure Bot OAuth connection name.')
param oauthConnectionName string = 'DatabricksGenieOBO'

@description('Delegated Microsoft Foundry scope requested by the Bot OAuth connection.')
param delegatedScope string = 'https://ai.azure.com/.default'

@description('Foundry prompt agent name.')
param foundryAgentName string

@description('Foundry OAuth project connection name.')
param foundryMcpConnectionName string = 'databricks-genie-obo-oauth'

@description('Client ID used by the Foundry custom OAuth MCP connection.')
param foundryMcpOAuthClientId string

@secure()
@description('Client secret used by the Foundry custom OAuth MCP connection.')
param foundryMcpOAuthClientSecret string

@description('Client ID of the APIM API application that exposes Genie.Access.')
param apimApiClientId string

@description('Resource tags.')
param tags object = {}

var foundryProjectEndpoint = 'https://${foundryAccountName}.services.ai.azure.com/api/projects/${foundryProjectName}'
var mcpServerUrl = 'https://${apimName}.azure-api.net/${oboMcpPath}/mcp'
var entraAuthority = '${environment().authentication.loginEndpoint}${tenantId}/oauth2/v2.0'

resource apim 'Microsoft.ApiManagement/service@2024-05-01' existing = {
  name: apimName
}

resource foundryAccount 'Microsoft.CognitiveServices/accounts@2025-06-01' existing = {
  name: foundryAccountName
}

resource foundryProject 'Microsoft.CognitiveServices/accounts/projects@2025-06-01' existing = {
  parent: foundryAccount
  name: foundryProjectName
}

resource foundryMcpConnection 'Microsoft.CognitiveServices/accounts/projects/connections@2025-06-01' = {
  parent: foundryProject
  name: foundryMcpConnectionName
  properties: any({
    authType: 'OAuth2'
    authorizationUrl: '${entraAuthority}/authorize'
    category: 'RemoteTool'
    credentials: {
      clientId: foundryMcpOAuthClientId
      clientSecret: foundryMcpOAuthClientSecret
    }
    group: 'GenericProtocol'
    isDefault: false
    isSharedToAll: false
    metadata: {
      type: 'custom_MCP'
    }
    refreshUrl: '${entraAuthority}/token'
    scopes: [
      'api://${apimApiClientId}/Genie.Access'
      'offline_access'
    ]
    target: mcpServerUrl
    tokenUrl: '${entraAuthority}/token'
    useCustomConnector: false
    useWorkspaceManagedIdentity: false
  })
}

resource sourceApi 'Microsoft.ApiManagement/service/apis@2024-06-01-preview' existing = {
  parent: apim
  name: oboSourceApiId
}

resource oboMcp 'Microsoft.ApiManagement/service/apis@2024-06-01-preview' = {
  parent: apim
  name: oboMcpApiId
  properties: {
    type: 'mcp'
    displayName: 'Databricks Genie OBO MCP'
    description: 'MCP facade that preserves the signed-in user through the existing APIM OBO policy.'
    path: oboMcpPath
    protocols: [
      'https'
    ]
    subscriptionRequired: false
    #disable-next-line BCP037
    mcpTools: [
      {
        name: 'ask'
        operationId: '${sourceApi.id}/operations/ask'
      }
      {
        name: 'follow-up'
        operationId: '${sourceApi.id}/operations/follow-up'
      }
      {
        name: 'message'
        operationId: '${sourceApi.id}/operations/message'
      }
      {
        name: 'result'
        operationId: '${sourceApi.id}/operations/result'
      }
    ]
  }
}

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: '${applicationInsightsName}-logs'
  location: location
  tags: tags
  properties: {
    retentionInDays: 30
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

resource insights 'Microsoft.Insights/components@2020-02-02' = {
  name: applicationInsightsName
  location: location
  kind: 'web'
  tags: tags
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalytics.id
  }
}

resource plan 'Microsoft.Web/serverfarms@2024-04-01' existing = {
  name: appServicePlanName
}

resource botApp 'Microsoft.Web/sites@2024-04-01' = {
  name: botAppName
  location: location
  kind: 'app,linux'
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: plan.id
    httpsOnly: true
    publicNetworkAccess: 'Enabled'
    siteConfig: {
      alwaysOn: true
      ftpsState: 'Disabled'
      http20Enabled: true
      linuxFxVersion: 'NODE|20-lts'
      minTlsVersion: '1.2'
      appCommandLine: 'node dist/index.js'
      appSettings: [
        {
          name: 'MicrosoftAppType'
          value: 'SingleTenant'
        }
        {
          name: 'MicrosoftAppId'
          value: botClientId
        }
        {
          name: 'MicrosoftAppPassword'
          value: botClientSecret
        }
        {
          name: 'MicrosoftAppTenantId'
          value: tenantId
        }
        {
          name: 'OAUTH_CONNECTION_NAME'
          value: oauthConnectionName
        }
        {
          name: 'FOUNDRY_PROJECT_ENDPOINT'
          value: foundryProjectEndpoint
        }
        {
          name: 'FOUNDRY_AGENT_NAME'
          value: foundryAgentName
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: insights.properties.ConnectionString
        }
        {
          name: 'SCM_DO_BUILD_DURING_DEPLOYMENT'
          value: 'true'
        }
      ]
    }
  }
}

resource bot 'Microsoft.BotService/botServices@2022-09-15' = {
  name: botName
  location: 'global'
  kind: 'azurebot'
  tags: tags
  sku: {
    name: 'F0'
  }
  properties: {
    displayName: 'Foundry Databricks Genie'
    description: 'Teams channel for a Microsoft Foundry agent with Databricks OBO.'
    endpoint: 'https://${botApp.properties.defaultHostName}/api/messages'
    msaAppId: botClientId
    msaAppTenantId: tenantId
    msaAppType: 'SingleTenant'
    publicNetworkAccess: 'Enabled'
  }
}

resource teamsChannel 'Microsoft.BotService/botServices/channels@2022-09-15' = {
  parent: bot
  name: 'MsTeamsChannel'
  location: 'global'
  properties: {
    channelName: 'MsTeamsChannel'
    properties: {
      acceptedTerms: true
      enableCalling: false
      isEnabled: true
    }
  }
}

resource botDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'bot-service-logs'
  scope: bot
  properties: {
    workspaceId: logAnalytics.id
    logs: [
      {
        category: 'BotRequest'
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

resource oauthConnection 'Microsoft.BotService/botServices/connections@2022-09-15' = {
  parent: bot
  name: oauthConnectionName
  location: 'global'
  properties: {
    clientId: botClientId
    clientSecret: botClientSecret
    scopes: delegatedScope
    serviceProviderId: '30dd229c-58e3-4a48-bdfd-91ec48eb906c'
    serviceProviderDisplayName: 'Azure Active Directory v2'
    parameters: [
      {
        key: 'tenantID'
        value: tenantId
      }
    ]
  }
}

output botEndpoint string = bot.properties.endpoint
output botPrincipalId string = botApp.identity.principalId
output foundryProjectEndpoint string = foundryProjectEndpoint
output mcpServerUrl string = mcpServerUrl
output publishedAgentUrl string = 'https://ai.azure.com/nextgen/build/agents/${foundryAgentName}'
output foundryMcpOAuthRedirectUrl string = any(foundryMcpConnection.properties).redirectUrl
