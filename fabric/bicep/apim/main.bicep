targetScope = 'subscription'

var config = loadJsonContent('../../config/deployment.json')
var apimConfig = config.apim
var identityConfig = config.identity

@minLength(36)
@maxLength(36)
type entraIdentifier = string

@description('Generated client ID of the Fabric resource API application registration.')
param resourceApiClientId entraIdentifier

@description('Generated client IDs of connector application registrations allowed to call the APIs.')
@minLength(1)
param connectorClientIds entraIdentifier[]

@description('Fabric-tenant user object IDs allowed to call the APIs.')
@minLength(1)
param allowedUserObjectIds entraIdentifier[]

@description('Generated application client ID used as the private broker audience.')
param brokerAudience entraIdentifier

@description('Fixed private broker origin, without an /api path or trailing slash.')
@minLength(1)
param brokerPrivateUrl string

@description('Optional existing Application Insights component name. Diagnostics are omitted when empty.')
param applicationInsightsName string = ''

@description('Resource group of the existing Application Insights component.')
param applicationInsightsResourceGroupName string = ''

var effectiveApplicationInsightsResourceGroupName = empty(applicationInsightsResourceGroupName) ? apimConfig.resourceGroup : applicationInsightsResourceGroupName

module apimStack './stack.bicep' = {
  name: 'fabric-apim-stack'
  scope: resourceGroup(apimConfig.subscriptionId, apimConfig.resourceGroup)
  params: {
    apimServiceName: apimConfig.serviceName
    resourceTenantId: identityConfig.resourceTenantId
    callerTenantId: identityConfig.callerTenantId
    resourceApiClientId: resourceApiClientId
    delegatedScope: identityConfig.delegatedScope
    connectorClientIds: connectorClientIds
    allowedUserObjectIds: allowedUserObjectIds
    brokerAudience: brokerAudience
    brokerRole: identityConfig.brokerApplicationRole
    brokerPrivateUrl: brokerPrivateUrl
    rateLimitCalls: apimConfig.rateLimitCalls
    rateLimitRenewalSeconds: apimConfig.rateLimitRenewalSeconds
    requestTimeoutSeconds: apimConfig.requestTimeoutSeconds
    lakehouseApiId: apimConfig.lakehouseApiId
    lakehouseApiPath: apimConfig.lakehouseApiPath
    lakehouseMcpDisplayName: apimConfig.lakehouseMcpDisplayName
    lakehouseMcpPath: apimConfig.lakehouseMcpPath
    dataAgentApiId: apimConfig.dataAgentApiId
    dataAgentApiPath: apimConfig.dataAgentApiPath
    dataAgentMcpDisplayName: apimConfig.dataAgentMcpDisplayName
    dataAgentMcpPath: apimConfig.dataAgentMcpPath
    productId: apimConfig.productId
    applicationInsightsName: applicationInsightsName
    applicationInsightsResourceGroupName: effectiveApplicationInsightsResourceGroupName
  }
}

output apimPrincipalId string = apimStack.outputs.apimPrincipalId
output lakehouseApiUrl string = '${apimConfig.gatewayUrl}/${apimConfig.lakehouseApiPath}'
output dataAgentApiUrl string = '${apimConfig.gatewayUrl}/${apimConfig.dataAgentApiPath}'
output lakehouseMcpUrl string = '${apimConfig.gatewayUrl}/${apimConfig.lakehouseMcpPath}/mcp'
output dataAgentMcpUrl string = '${apimConfig.gatewayUrl}/${apimConfig.dataAgentMcpPath}/mcp'
