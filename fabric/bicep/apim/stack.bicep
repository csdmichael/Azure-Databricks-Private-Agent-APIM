targetScope = 'resourceGroup'

param apimServiceName string
param resourceTenantId string
param callerTenantId string
param resourceApiClientId string
param delegatedScope string
param connectorClientIds array
param allowedFabricGuestObjectIds array
param brokerAudience string
param brokerRole string
param brokerPrivateUrl string
param rateLimitCalls int
param rateLimitRenewalSeconds int
param requestTimeoutSeconds int
param lakehouseApiId string
param lakehouseApiPath string
param lakehouseMcpDisplayName string
param lakehouseMcpPath string
param dataAgentApiId string
param dataAgentApiPath string
param dataAgentMcpDisplayName string
param dataAgentMcpPath string
param productId string
param applicationInsightsName string
param applicationInsightsResourceGroupName string

var diagnosticsEnabled = !empty(applicationInsightsName)
var loggerName = 'fabric-obo-insights'
var lakehouseMcpId = '${lakehouseApiId}-mcp'
var dataAgentMcpId = '${dataAgentApiId}-mcp'
var commonApiPolicy = loadTextContent('../../apim/policies/fabric-obo-api-policy.xml')
var namedValueSettings = [
  { name: 'fabric-obo-resource-tenant-id', value: resourceTenantId }
  { name: 'fabric-obo-caller-tenant-id', value: callerTenantId }
  { name: 'fabric-obo-resource-api-client-id', value: resourceApiClientId }
  { name: 'fabric-obo-delegated-scope', value: delegatedScope }
  { name: 'fabric-obo-connector-client-ids', value: join(connectorClientIds, ',') }
  { name: 'fabric-obo-allowed-guest-oids', value: join(allowedFabricGuestObjectIds, ',') }
  { name: 'fabric-obo-broker-audience', value: brokerAudience }
  { name: 'fabric-obo-broker-role', value: brokerRole }
  { name: 'fabric-obo-broker-private-url', value: brokerPrivateUrl }
  { name: 'fabric-obo-rate-limit-calls', value: string(rateLimitCalls) }
  { name: 'fabric-obo-rate-limit-renewal-seconds', value: string(rateLimitRenewalSeconds) }
  { name: 'fabric-obo-request-timeout-seconds', value: string(requestTimeoutSeconds) }
]

resource apim 'Microsoft.ApiManagement/service@2024-05-01' existing = {
  name: apimServiceName
}

resource namedValues 'Microsoft.ApiManagement/service/namedValues@2024-06-01-preview' = [for setting in namedValueSettings: {
  parent: apim
  name: setting.name
  properties: {
    displayName: setting.name
    value: setting.value
    secret: false
  }
}]

resource lakehouseApi 'Microsoft.ApiManagement/service/apis@2024-06-01-preview' = {
  parent: apim
  name: lakehouseApiId
  properties: {
    displayName: 'Fabric Lakehouse OAuth'
    description: 'Read-only Fabric Lakehouse operations using delegated OAuth through the private broker.'
    path: lakehouseApiPath
    protocols: [
      'https'
    ]
    subscriptionRequired: false
    format: 'openapi+json'
    value: loadTextContent('../../apim/openapi/lakehouse.json')
  }
}

resource dataAgentApi 'Microsoft.ApiManagement/service/apis@2024-06-01-preview' = {
  parent: apim
  name: dataAgentApiId
  properties: {
    displayName: 'Fabric Data Agent OAuth'
    description: 'Fabric Data Agent queries using delegated OAuth through the private broker.'
    path: dataAgentApiPath
    protocols: [
      'https'
    ]
    subscriptionRequired: false
    format: 'openapi+json'
    value: loadTextContent('../../apim/openapi/data-agent.json')
  }
}

resource lakehouseApiPolicy 'Microsoft.ApiManagement/service/apis/policies@2024-06-01-preview' = {
  parent: lakehouseApi
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: commonApiPolicy
  }
  dependsOn: [
    namedValues
  ]
}

resource dataAgentApiPolicy 'Microsoft.ApiManagement/service/apis/policies@2024-06-01-preview' = {
  parent: dataAgentApi
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: commonApiPolicy
  }
  dependsOn: [
    namedValues
  ]
}

resource lakehouseQueryOperation 'Microsoft.ApiManagement/service/apis/operations@2024-06-01-preview' existing = {
  parent: lakehouseApi
  name: 'query'
}

resource lakehouseTablesOperation 'Microsoft.ApiManagement/service/apis/operations@2024-06-01-preview' existing = {
  parent: lakehouseApi
  name: 'tables'
}

resource dataAgentQueryOperation 'Microsoft.ApiManagement/service/apis/operations@2024-06-01-preview' existing = {
  parent: dataAgentApi
  name: 'query'
}

resource lakehouseQueryPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2024-06-01-preview' = {
  parent: lakehouseQueryOperation
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: loadTextContent('../../apim/policies/lakehouse-query-operation-policy.xml')
  }
}

resource lakehouseTablesPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2024-06-01-preview' = {
  parent: lakehouseTablesOperation
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: loadTextContent('../../apim/policies/lakehouse-tables-operation-policy.xml')
  }
}

resource dataAgentQueryPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2024-06-01-preview' = {
  parent: dataAgentQueryOperation
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: loadTextContent('../../apim/policies/data-agent-query-operation-policy.xml')
  }
}

resource lakehouseMcp 'Microsoft.ApiManagement/service/apis@2024-06-01-preview' = {
  parent: apim
  name: lakehouseMcpId
  properties: any({
    type: 'mcp'
    displayName: lakehouseMcpDisplayName
    description: 'MCP tools for the Fabric Lakehouse OAuth API.'
    path: lakehouseMcpPath
    protocols: [
      'https'
    ]
    subscriptionRequired: false
    mcpTools: [
      {
        name: 'query'
        operationId: lakehouseQueryOperation.id
      }
      {
        name: 'tables'
        operationId: lakehouseTablesOperation.id
      }
    ]
  })
  dependsOn: [
    lakehouseQueryPolicy
    lakehouseTablesPolicy
  ]
}

resource dataAgentMcp 'Microsoft.ApiManagement/service/apis@2024-06-01-preview' = {
  parent: apim
  name: dataAgentMcpId
  properties: any({
    type: 'mcp'
    displayName: dataAgentMcpDisplayName
    description: 'MCP tool for the Fabric Data Agent OAuth API.'
    path: dataAgentMcpPath
    protocols: [
      'https'
    ]
    subscriptionRequired: false
    mcpTools: [
      {
        name: 'query'
        operationId: dataAgentQueryOperation.id
      }
    ]
  })
  dependsOn: [
    dataAgentQueryPolicy
  ]
}

resource product 'Microsoft.ApiManagement/service/products@2024-06-01-preview' = {
  parent: apim
  name: productId
  properties: {
    displayName: 'Fabric Agents'
    description: 'Delegated Fabric REST APIs and MCP servers.'
    subscriptionRequired: false
    approvalRequired: false
    state: 'published'
  }
}

var productApis = [
  { name: 'link-${lakehouseApiId}', apiId: lakehouseApi.id }
  { name: 'link-${dataAgentApiId}', apiId: dataAgentApi.id }
  { name: 'link-${lakehouseMcpId}', apiId: lakehouseMcp.id }
  { name: 'link-${dataAgentMcpId}', apiId: dataAgentMcp.id }
]

resource productApiLinks 'Microsoft.ApiManagement/service/products/apiLinks@2024-06-01-preview' = [for item in productApis: {
  parent: product
  name: item.name
  properties: {
    apiId: item.apiId
  }
}]

resource insights 'Microsoft.Insights/components@2020-02-02' existing = if (diagnosticsEnabled) {
  scope: resourceGroup(applicationInsightsResourceGroupName)
  name: applicationInsightsName
}

resource logger 'Microsoft.ApiManagement/service/loggers@2024-06-01-preview' = if (diagnosticsEnabled) {
  parent: apim
  name: loggerName
  properties: {
    loggerType: 'applicationInsights'
    credentials: {
      instrumentationKey: insights!.properties.InstrumentationKey
    }
    resourceId: insights!.id
    isBuffered: true
  }
}

var diagnosticProperties = {
  loggerId: resourceId('Microsoft.ApiManagement/service/loggers', apimServiceName, loggerName)
  alwaysLog: 'allErrors'
  sampling: {
    samplingType: 'fixed'
    percentage: 100
  }
  verbosity: 'information'
  logClientIp: false
  httpCorrelationProtocol: 'W3C'
  frontend: {
    request: { headers: [], body: { bytes: 0 } }
    response: { headers: [], body: { bytes: 0 } }
  }
  backend: {
    request: { headers: [], body: { bytes: 0 } }
    response: { headers: [], body: { bytes: 0 } }
  }
}

resource lakehouseDiagnostic 'Microsoft.ApiManagement/service/apis/diagnostics@2024-06-01-preview' = if (diagnosticsEnabled) {
  parent: lakehouseApi
  name: 'applicationinsights'
  properties: diagnosticProperties
  dependsOn: [
    logger
  ]
}

resource dataAgentDiagnostic 'Microsoft.ApiManagement/service/apis/diagnostics@2024-06-01-preview' = if (diagnosticsEnabled) {
  parent: dataAgentApi
  name: 'applicationinsights'
  properties: diagnosticProperties
  dependsOn: [
    logger
  ]
}

resource lakehouseMcpDiagnostic 'Microsoft.ApiManagement/service/apis/diagnostics@2024-06-01-preview' = if (diagnosticsEnabled) {
  parent: lakehouseMcp
  name: 'applicationinsights'
  properties: diagnosticProperties
  dependsOn: [
    logger
  ]
}

resource dataAgentMcpDiagnostic 'Microsoft.ApiManagement/service/apis/diagnostics@2024-06-01-preview' = if (diagnosticsEnabled) {
  parent: dataAgentMcp
  name: 'applicationinsights'
  properties: diagnosticProperties
  dependsOn: [
    logger
  ]
}

output apimPrincipalId string = apim.identity.principalId
output lakehouseApiId string = lakehouseApi.id
output dataAgentApiId string = dataAgentApi.id
output lakehouseMcpId string = lakehouseMcp.id
output dataAgentMcpId string = dataAgentMcp.id
