param apimServiceName string = 'caldova-apim-westus'
param tenantId string = tenant().tenantId
param apiClientId string
param connectorClientId string
param allowedUserId string = '715bb744-31d0-4f76-ac85-7193bcf5a4eb'
param brokerUrl string
param insightsName string = 'caldova-genie-obo-insights'

resource apim 'Microsoft.ApiManagement/service@2023-09-01-preview' existing = { name: apimServiceName }
resource insights 'Microsoft.Insights/components@2020-02-02' existing = { name: insightsName }
resource logger 'Microsoft.ApiManagement/service/loggers@2023-09-01-preview' = {
  parent: apim
  name: 'genie-obo-insights'
  properties: {
    loggerType: 'applicationInsights'
    credentials: { instrumentationKey: insights.properties.InstrumentationKey }
    resourceId: insights.id
    isBuffered: true
  }
}
resource auditFragment 'Microsoft.ApiManagement/service/policyFragments@2023-09-01-preview' = {
  parent: apim
  name: 'genie-obo-audit'
  properties: { format: 'rawxml', value: loadTextContent('./policies/genie-obo-audit-fragment.xml') }
}
var settings = [
  { name: 'genie-obo-tenant-id', value: tenantId }
  { name: 'genie-obo-api-client-id', value: apiClientId }
  { name: 'genie-obo-connector-client-id', value: connectorClientId }
  { name: 'genie-obo-allowed-user-id', value: allowedUserId }
  { name: 'genie-obo-broker-url', value: brokerUrl }
]
resource namedValues 'Microsoft.ApiManagement/service/namedValues@2023-09-01-preview' = [for setting in settings: {
  parent: apim
  name: setting.name
  properties: { displayName: setting.name, value: setting.value, secret: false }
}]
resource api 'Microsoft.ApiManagement/service/apis@2023-09-01-preview' = {
  parent: apim
  name: 'databricks-genie-obo'
  properties: {
    displayName: 'Databricks Genie - delegated user'
    description: 'Private Genie API with per-user Entra tokens and Databricks token federation.'
    path: 'databricks-genie-obo'
    protocols: ['https']
    subscriptionRequired: false
  }
}
resource policy 'Microsoft.ApiManagement/service/apis/policies@2023-09-01-preview' = {
  parent: api
  name: 'policy'
  properties: { format: 'rawxml', value: loadTextContent('./policies/genie-obo-api-policy.xml') }
  dependsOn: [namedValues, auditFragment]
}
resource diagnostic 'Microsoft.ApiManagement/service/apis/diagnostics@2023-09-01-preview' = {
  parent: api
  name: 'applicationinsights'
  properties: {
    loggerId: logger.id
    alwaysLog: 'allErrors'
    sampling: { samplingType: 'fixed', percentage: 100 }
    verbosity: 'information'
    logClientIp: false
    httpCorrelationProtocol: 'W3C'
    frontend: { request: { headers: [], body: { bytes: 0 } }, response: { headers: [], body: { bytes: 0 } } }
    backend: { request: { headers: [], body: { bytes: 0 } }, response: { headers: [], body: { bytes: 0 } } }
  }
}
var operations = [
  { name: 'ask', method: 'POST', path: '/genie/ask', parameters: [], policy: loadTextContent('./policies/genie-start-operation-policy.xml') }
  { name: 'follow-up', method: 'POST', path: '/genie/conversations/{conversationId}/messages', parameters: [{ name: 'conversationId', type: 'string', required: true }], policy: loadTextContent('./policies/genie-followup-operation-policy.xml') }
  { name: 'message', method: 'GET', path: '/genie/conversations/{conversationId}/messages/{messageId}', parameters: [{ name: 'conversationId', type: 'string', required: true }, { name: 'messageId', type: 'string', required: true }], policy: loadTextContent('./policies/genie-message-operation-policy.xml') }
  { name: 'result', method: 'GET', path: '/genie/conversations/{conversationId}/messages/{messageId}/result', parameters: [{ name: 'conversationId', type: 'string', required: true }, { name: 'messageId', type: 'string', required: true }], policy: loadTextContent('./policies/genie-result-operation-policy.xml') }
]
resource operation 'Microsoft.ApiManagement/service/apis/operations@2023-09-01-preview' = [for item in operations: {
  parent: api
  name: item.name
  properties: { displayName: item.name, method: item.method, urlTemplate: item.path, templateParameters: item.parameters, responses: [{ statusCode: 200 }] }
}]
resource operationPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2023-09-01-preview' = [for (item, index) in operations: {
  parent: operation[index]
  name: 'policy'
  properties: { format: 'rawxml', value: item.policy }
}]
output apiUrl string = 'https://${apimServiceName}.azure-api.net/databricks-genie-obo'
