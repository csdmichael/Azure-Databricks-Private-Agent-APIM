@description('Existing API Management service name.')
param apimServiceName string

@description('Microsoft Entra tenant ID accepted by the delegated API.')
param tenantId string

@description('Application client ID for the delegated API.')
param apiClientId string

@description('Application client ID allowed to call the delegated API.')
param connectorClientId string

@description('User object ID authorized to call the delegated API.')
param allowedUserId string

@description('Private Databricks workspace URL.')
param databricksWorkspaceUrl string

@description('Databricks Genie space ID.')
@minLength(1)
param genieSpaceId string

@description('Token broker endpoint used for delegated token exchange.')
param brokerUrl string

@description('Existing Application Insights component name.')
param insightsName string

@description('Delegated OAuth scope required from callers.')
param oboScope string

@description('Maximum calls allowed per verified user in each renewal period.')
@minValue(1)
param oboRateLimitCalls int

@description('Per-user rate-limit renewal period in seconds.')
@minValue(1)
param oboRateLimitRenewalPeriodSeconds int

@description('Maximum number of seconds APIM waits for the token broker.')
@minValue(1)
param oboBrokerTimeoutSeconds int

@description('Delegated Genie API display name.')
param apiDisplayName string

@description('Delegated Genie API description.')
param apiDescription string

@description('Percentage of API requests sampled for diagnostics.')
@minValue(0)
@maxValue(100)
param diagnosticSamplingPercentage int

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
  { name: 'databricks-workspace-url', value: databricksWorkspaceUrl }
  { name: 'databricks-genie-space-id', value: genieSpaceId }
  { name: 'genie-obo-tenant-id', value: tenantId }
  { name: 'genie-obo-api-client-id', value: apiClientId }
  { name: 'genie-obo-connector-client-id', value: connectorClientId }
  { name: 'genie-obo-allowed-user-id', value: allowedUserId }
  { name: 'genie-obo-broker-url', value: brokerUrl }
  { name: 'genie-obo-scope', value: oboScope }
  { name: 'genie-obo-rate-limit-calls', value: string(oboRateLimitCalls) }
  { name: 'genie-obo-rate-limit-renewal-period', value: string(oboRateLimitRenewalPeriodSeconds) }
  { name: 'genie-obo-broker-timeout', value: string(oboBrokerTimeoutSeconds) }
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
    displayName: apiDisplayName
    description: apiDescription
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
    sampling: { samplingType: 'fixed', percentage: diagnosticSamplingPercentage }
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
