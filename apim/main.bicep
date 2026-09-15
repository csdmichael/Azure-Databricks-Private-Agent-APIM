// Exposes a private Azure Databricks workspace through an existing API
// Management service. APIM authenticates to Databricks with its managed
// identity, so no secrets are stored. Consumers use an APIM subscription key.

@description('Existing API Management service name.')
param apimServiceName string

@description('Databricks workspace URL, e.g. https://adb-123.11.azuredatabricks.net')
param databricksWorkspaceUrl string

@description('Databricks serverless SQL warehouse id.')
param databricksWarehouseId string

@description('Unity Catalog catalog exposed through the Databricks SQL API.')
param databricksCatalog string

@description('Unity Catalog schema exposed through the Databricks SQL API.')
param databricksSchema string

@description('Databricks Genie space id.')
@minLength(1)
param genieSpaceId string

@description('Maximum Databricks SQL API calls allowed in each renewal period.')
@minValue(1)
param databricksRateLimitCalls int

@description('Maximum Databricks Genie API calls allowed in each renewal period.')
@minValue(1)
param genieRateLimitCalls int

@description('Rate-limit renewal period in seconds for the Databricks APIs.')
@minValue(1)
param rateLimitRenewalPeriodSeconds int

@description('Databricks SQL statement wait timeout, such as 50s.')
param sqlWaitTimeout string

@description('Display name for the Databricks SQL API.')
param databricksApiDisplayName string

@description('Description for the Databricks SQL API.')
param databricksApiDescription string

@description('Display name for the Databricks Genie API.')
param genieApiDisplayName string

@description('Description for the Databricks Genie API.')
param genieApiDescription string

@description('Display name for the APIM product that groups the Databricks APIs.')
param productDisplayName string

@description('Description for the APIM product that groups the Databricks APIs.')
param productDescription string

@description('Display name for the product subscription.')
param subscriptionDisplayName string

resource apim 'Microsoft.ApiManagement/service@2023-09-01-preview' existing = {
  name: apimServiceName
}

// ---------------- Named values -----------------------------------------
resource nvWorkspaceUrl 'Microsoft.ApiManagement/service/namedValues@2023-09-01-preview' = {
  parent: apim
  name: 'databricks-workspace-url'
  properties: {
    displayName: 'databricks-workspace-url'
    value: databricksWorkspaceUrl
    secret: false
  }
}

resource nvWarehouseId 'Microsoft.ApiManagement/service/namedValues@2023-09-01-preview' = {
  parent: apim
  name: 'databricks-warehouse-id'
  properties: {
    displayName: 'databricks-warehouse-id'
    value: databricksWarehouseId
    secret: false
  }
}

resource nvCatalog 'Microsoft.ApiManagement/service/namedValues@2023-09-01-preview' = {
  parent: apim
  name: 'databricks-catalog'
  properties: {
    displayName: 'databricks-catalog'
    value: databricksCatalog
    secret: false
  }
}

resource nvSchema 'Microsoft.ApiManagement/service/namedValues@2023-09-01-preview' = {
  parent: apim
  name: 'databricks-schema'
  properties: {
    displayName: 'databricks-schema'
    value: databricksSchema
    secret: false
  }
}

resource nvGenieSpace 'Microsoft.ApiManagement/service/namedValues@2023-09-01-preview' = {
  parent: apim
  name: 'databricks-genie-space-id'
  properties: {
    displayName: 'databricks-genie-space-id'
    value: genieSpaceId
    secret: false
  }
}

resource nvDatabricksRateLimitCalls 'Microsoft.ApiManagement/service/namedValues@2023-09-01-preview' = {
  parent: apim
  name: 'databricks-rate-limit-calls'
  properties: {
    displayName: 'databricks-rate-limit-calls'
    value: string(databricksRateLimitCalls)
    secret: false
  }
}

resource nvDatabricksRateLimitPeriod 'Microsoft.ApiManagement/service/namedValues@2023-09-01-preview' = {
  parent: apim
  name: 'databricks-rate-limit-renewal-period'
  properties: {
    displayName: 'databricks-rate-limit-renewal-period'
    value: string(rateLimitRenewalPeriodSeconds)
    secret: false
  }
}

resource nvGenieRateLimitCalls 'Microsoft.ApiManagement/service/namedValues@2023-09-01-preview' = {
  parent: apim
  name: 'genie-rate-limit-calls'
  properties: {
    displayName: 'genie-rate-limit-calls'
    value: string(genieRateLimitCalls)
    secret: false
  }
}

resource nvGenieRateLimitPeriod 'Microsoft.ApiManagement/service/namedValues@2023-09-01-preview' = {
  parent: apim
  name: 'genie-rate-limit-renewal-period'
  properties: {
    displayName: 'genie-rate-limit-renewal-period'
    value: string(rateLimitRenewalPeriodSeconds)
    secret: false
  }
}

resource nvSqlWaitTimeout 'Microsoft.ApiManagement/service/namedValues@2023-09-01-preview' = {
  parent: apim
  name: 'databricks-sql-wait-timeout'
  properties: {
    displayName: 'databricks-sql-wait-timeout'
    value: sqlWaitTimeout
    secret: false
  }
}

// ---------------- Databricks SQL API -----------------------------------
resource dbxApi 'Microsoft.ApiManagement/service/apis@2023-09-01-preview' = {
  parent: apim
  name: 'databricks'
  properties: {
    displayName: databricksApiDisplayName
    description: databricksApiDescription
    path: 'databricks'
    protocols: [ 'https' ]
    subscriptionRequired: true
    subscriptionKeyParameterNames: {
      header: 'Ocp-Apim-Subscription-Key'
    }
  }
}

resource dbxApiPolicy 'Microsoft.ApiManagement/service/apis/policies@2023-09-01-preview' = {
  parent: dbxApi
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: loadTextContent('./policies/databricks-api-policy.xml')
  }
  dependsOn: [
    nvWorkspaceUrl
    nvDatabricksRateLimitCalls
    nvDatabricksRateLimitPeriod
  ]
}

resource opQuery 'Microsoft.ApiManagement/service/apis/operations@2023-09-01-preview' = {
  parent: dbxApi
  name: 'query'
  properties: {
    displayName: 'Run SQL query'
    method: 'POST'
    urlTemplate: '/query'
    description: 'Body: { "statement": "SELECT ..." }. Returns JSON_ARRAY rows.'
    request: {
      representations: [
        {
          contentType: 'application/json'
          examples: {
            default: {
              value: {
                statement: 'SHOW TABLES IN ${databricksCatalog}.${databricksSchema}'
              }
            }
          }
        }
      ]
    }
    responses: [ { statusCode: 200, description: 'SQL result' } ]
  }
}

resource opQueryPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2023-09-01-preview' = {
  parent: opQuery
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: loadTextContent('./policies/databricks-query-operation-policy.xml')
  }
  dependsOn: [
    nvWarehouseId
    nvSqlWaitTimeout
  ]
}

resource opTables 'Microsoft.ApiManagement/service/apis/operations@2023-09-01-preview' = {
  parent: dbxApi
  name: 'tables'
  properties: {
    displayName: 'List schema tables'
    method: 'GET'
    urlTemplate: '/tables'
    description: 'Lists tables in the configured Unity Catalog schema.'
    responses: [ { statusCode: 200, description: 'Table list' } ]
  }
}

resource opTablesPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2023-09-01-preview' = {
  parent: opTables
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: loadTextContent('./policies/databricks-tables-operation-policy.xml')
  }
  dependsOn: [
    nvWarehouseId
    nvCatalog
    nvSchema
    nvSqlWaitTimeout
  ]
}

// ---------------- Databricks Genie API ---------------------------------
resource genieApi 'Microsoft.ApiManagement/service/apis@2023-09-01-preview' = {
  parent: apim
  name: 'databricks-genie'
  properties: {
    displayName: genieApiDisplayName
    description: genieApiDescription
    path: 'databricks-genie'
    protocols: [ 'https' ]
    subscriptionRequired: true
    subscriptionKeyParameterNames: {
      header: 'Ocp-Apim-Subscription-Key'
    }
  }
}

resource genieApiPolicy 'Microsoft.ApiManagement/service/apis/policies@2023-09-01-preview' = {
  parent: genieApi
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: loadTextContent('./policies/genie-api-policy.xml')
  }
  dependsOn: [
    nvWorkspaceUrl
    nvGenieRateLimitCalls
    nvGenieRateLimitPeriod
  ]
}

resource opGenieAsk 'Microsoft.ApiManagement/service/apis/operations@2023-09-01-preview' = {
  parent: genieApi
  name: 'ask'
  properties: {
    displayName: 'Ask Genie (start conversation)'
    method: 'POST'
    urlTemplate: '/genie/ask'
    description: 'Body: { "content": "natural-language question" }.'
    request: {
      representations: [
        {
          contentType: 'application/json'
          examples: {
            default: {
              value: {
                content: 'What was total revenue by region last quarter?'
              }
            }
          }
        }
      ]
    }
    responses: [ { statusCode: 200, description: 'Conversation + message ids' } ]
  }
}

resource opGenieAskPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2023-09-01-preview' = {
  parent: opGenieAsk
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: loadTextContent('./policies/genie-start-operation-policy.xml')
  }
  dependsOn: [ nvGenieSpace ]
}

resource opGenieFollow 'Microsoft.ApiManagement/service/apis/operations@2023-09-01-preview' = {
  parent: genieApi
  name: 'follow-up'
  properties: {
    displayName: 'Ask Genie follow-up'
    method: 'POST'
    urlTemplate: '/genie/conversations/{conversationId}/messages'
    templateParameters: [ { name: 'conversationId', type: 'string', required: true } ]
    responses: [ { statusCode: 200, description: 'Message' } ]
  }
}

resource opGenieFollowPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2023-09-01-preview' = {
  parent: opGenieFollow
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: loadTextContent('./policies/genie-followup-operation-policy.xml')
  }
  dependsOn: [ nvGenieSpace ]
}

resource opGenieResult 'Microsoft.ApiManagement/service/apis/operations@2023-09-01-preview' = {
  parent: genieApi
  name: 'result'
  properties: {
    displayName: 'Get Genie query result'
    method: 'GET'
    urlTemplate: '/genie/conversations/{conversationId}/messages/{messageId}/result'
    templateParameters: [
      { name: 'conversationId', type: 'string', required: true }
      { name: 'messageId', type: 'string', required: true }
    ]
    responses: [ { statusCode: 200, description: 'Query result' } ]
  }
}

resource opGenieResultPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2023-09-01-preview' = {
  parent: opGenieResult
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: loadTextContent('./policies/genie-result-operation-policy.xml')
  }
  dependsOn: [ nvGenieSpace ]
}

resource opGenieMessage 'Microsoft.ApiManagement/service/apis/operations@2023-09-01-preview' = {
  parent: genieApi
  name: 'message'
  properties: {
    displayName: 'Get Genie message status'
    method: 'GET'
    urlTemplate: '/genie/conversations/{conversationId}/messages/{messageId}'
    description: 'Poll until status is COMPLETED, then read the text answer and generated SQL from attachments.'
    templateParameters: [
      { name: 'conversationId', type: 'string', required: true }
      { name: 'messageId', type: 'string', required: true }
    ]
    responses: [ { statusCode: 200, description: 'Message status and attachments' } ]
  }
}

resource opGenieMessagePolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2023-09-01-preview' = {
  parent: opGenieMessage
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: loadTextContent('./policies/genie-message-operation-policy.xml')
  }
  dependsOn: [ nvGenieSpace ]
}

// ---------------- Product grouping the two APIs ------------------------
resource product 'Microsoft.ApiManagement/service/products@2023-09-01-preview' = {
  parent: apim
  name: 'databricks-agents'
  properties: {
    displayName: productDisplayName
    description: productDescription
    subscriptionRequired: true
    approvalRequired: false
    state: 'published'
  }
}

resource productDbxApi 'Microsoft.ApiManagement/service/products/apiLinks@2023-09-01-preview' = {
  parent: product
  name: 'link-databricks'
  properties: {
    apiId: dbxApi.id
  }
}

resource productGenieApi 'Microsoft.ApiManagement/service/products/apiLinks@2023-09-01-preview' = {
  parent: product
  name: 'link-databricks-genie'
  properties: {
    apiId: genieApi.id
  }
}

resource databricksSubscription 'Microsoft.ApiManagement/service/subscriptions@2023-09-01-preview' = {
  parent: apim
  name: 'DatabricksSubscription'
  properties: {
    allowTracing: false
    displayName: subscriptionDisplayName
    scope: product.id
    state: 'active'
  }
  dependsOn: [
    productDbxApi
    productGenieApi
  ]
}

output databricksApiPath string = 'https://${apimServiceName}.azure-api.net/databricks'
output genieApiPath string = 'https://${apimServiceName}.azure-api.net/databricks-genie'
output productName string = product.name
output subscriptionName string = databricksSubscription.name
