targetScope = 'subscription'

var config = loadJsonContent('../../config/deployment.json')
var apimConfig = config.apim
var identityConfig = config.identity
var networkConfig = config.network
var brokerConfig = config.broker

@minLength(36)
@maxLength(36)
type entraIdentifier = string

@description('Generated client ID of the Fabric resource API application registration.')
param resourceApiClientId entraIdentifier

@description('Generated client IDs of connector application registrations allowed to call the APIs.')
@minLength(1)
param connectorClientIds entraIdentifier[]

@description('Fabric-tenant guest object IDs allowed to call the APIs.')
@minLength(1)
param allowedFabricGuestObjectIds entraIdentifier[]

@description('Generated application client ID used as the private broker audience.')
param brokerAudience entraIdentifier

@description('Fixed private broker origin, without an /api path or trailing slash.')
@minLength(1)
param brokerPrivateUrl string

@description('IPv4 address assigned to the broker private endpoint.')
@minLength(7)
@maxLength(15)
param brokerPrivateEndpointIp string

@description('Optional existing Application Insights component name. Diagnostics are omitted when empty.')
param applicationInsightsName string = ''

@description('Resource group of the existing Application Insights component.')
param applicationInsightsResourceGroupName string = ''

@description('Create the Caldova-side privatelink.azurewebsites.net zone. Set false to reuse an existing zone.')
param createPrivateDnsZone bool = true

@description('Resource group in the APIM subscription that contains or will contain the private DNS zone.')
param privateDnsZoneResourceGroupName string = ''

var effectiveApplicationInsightsResourceGroupName = empty(applicationInsightsResourceGroupName) ? apimConfig.resourceGroup : applicationInsightsResourceGroupName
var effectivePrivateDnsZoneResourceGroupName = empty(privateDnsZoneResourceGroupName) ? apimConfig.resourceGroup : privateDnsZoneResourceGroupName

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
    allowedFabricGuestObjectIds: allowedFabricGuestObjectIds
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

module privateDnsZone './private-dns-zone.bicep' = if (createPrivateDnsZone) {
  name: 'fabric-broker-private-dns-zone'
  scope: resourceGroup(apimConfig.subscriptionId, effectivePrivateDnsZoneResourceGroupName)
  params: {
    tags: config.tags
  }
}

module privateDns './private-dns.bicep' = {
  name: 'fabric-broker-private-dns'
  scope: resourceGroup(apimConfig.subscriptionId, effectivePrivateDnsZoneResourceGroupName)
  params: {
    brokerAppName: brokerConfig.appName
    brokerPrivateEndpointIp: brokerPrivateEndpointIp
    apimServiceName: apimConfig.serviceName
    apimVnetResourceId: networkConfig.apimVnetResourceId
    tags: config.tags
  }
  dependsOn: [
    privateDnsZone
  ]
}

output apimPrincipalId string = apimStack.outputs.apimPrincipalId
output lakehouseApiUrl string = '${apimConfig.gatewayUrl}/${apimConfig.lakehouseApiPath}'
output dataAgentApiUrl string = '${apimConfig.gatewayUrl}/${apimConfig.dataAgentApiPath}'
output lakehouseMcpUrl string = '${apimConfig.gatewayUrl}/${apimConfig.lakehouseMcpPath}/mcp'
output dataAgentMcpUrl string = '${apimConfig.gatewayUrl}/${apimConfig.dataAgentMcpPath}/mcp'
output privateDnsZoneId string = privateDns.outputs.privateDnsZoneId
