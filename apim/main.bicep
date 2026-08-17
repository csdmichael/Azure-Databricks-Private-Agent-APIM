// =====================================================================
//  Exposes the PRIVATE Azure Databricks workspace through the existing
//  APIM instance (ai-gateway-apim-poc-my) as:
//    - "Databricks SQL"  : POST /databricks/query, GET /databricks/tables
//    - "Databricks Genie": POST /databricks-genie/genie/ask (+ follow-up, result)
//  APIM authenticates to Databricks with its managed identity, so no secrets
//  are stored. Consumers use an APIM subscription key.
//
//  Deploy:
//    az deployment group create -g ai-myaacoub -f apim/main.bicep \
//      -p databricksWorkspaceUrl=<url> databricksWarehouseId=<id> genieSpaceId=<id>
// =====================================================================

@description('Existing API Management service name.')
param apimServiceName string = 'ai-gateway-apim-poc-my'

@description('Databricks workspace URL, e.g. https://adb-123.11.azuredatabricks.net')
param databricksWorkspaceUrl string

@description('Databricks serverless SQL warehouse id.')
param databricksWarehouseId string

@description('Databricks Genie space id (optional; set later if not ready).')
param genieSpaceId string = ''

var apiVersion = '2023-09-01-preview'

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

resource nvGenieSpace 'Microsoft.ApiManagement/service/namedValues@2023-09-01-preview' = {
  parent: apim
  name: 'databricks-genie-space-id'
  properties: {
    displayName: 'databricks-genie-space-id'
    value: empty(genieSpaceId) ? 'REPLACE_WITH_GENIE_SPACE_ID' : genieSpaceId
    secret: false
  }
}

// ---------------- Databricks SQL API -----------------------------------
resource dbxApi 'Microsoft.ApiManagement/service/apis@2023-09-01-preview' = {
  parent: apim
  name: 'databricks'
  properties: {
    displayName: 'Databricks SQL'
    description: 'Query the private Databricks warehouse (arrow_semiconductor sample data).'
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
  dependsOn: [ nvWorkspaceUrl ]
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
                statement: 'SELECT region, ROUND(SUM(revenue_usd)/1e6,2) AS revenue_musd FROM arrow_semiconductor.manufacturing.product_sales GROUP BY region ORDER BY revenue_musd DESC'
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
  dependsOn: [ nvWarehouseId ]
}

resource opTables 'Microsoft.ApiManagement/service/apis/operations@2023-09-01-preview' = {
  parent: dbxApi
  name: 'tables'
  properties: {
    displayName: 'List sample tables'
    method: 'GET'
    urlTemplate: '/tables'
    description: 'Lists tables in arrow_semiconductor.manufacturing.'
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
  dependsOn: [ nvWarehouseId ]
}

// ---------------- Databricks Genie API ---------------------------------
resource genieApi 'Microsoft.ApiManagement/service/apis@2023-09-01-preview' = {
  parent: apim
  name: 'databricks-genie'
  properties: {
    displayName: 'Databricks Genie'
    description: 'Ask natural-language questions of the Databricks data via AI/BI Genie.'
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
  dependsOn: [ nvWorkspaceUrl ]
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

// ---------------- Product grouping the two APIs ------------------------
resource product 'Microsoft.ApiManagement/service/products@2023-09-01-preview' = {
  parent: apim
  name: 'databricks-agents'
  properties: {
    displayName: 'Databricks Agents'
    description: 'APIs and MCP tools for Foundry / Copilot Studio agents over private Databricks.'
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

output databricksApiPath string = 'https://${apimServiceName}.azure-api.net/databricks'
output genieApiPath string = 'https://${apimServiceName}.azure-api.net/databricks-genie'
output productName string = product.name
