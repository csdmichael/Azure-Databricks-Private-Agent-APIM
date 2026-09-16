locals {
  config = jsondecode(file(var.config_path))

  subscription_id             = coalesce(var.subscription_id, try(local.config.azure.subscriptionId, null))
  resource_group_name         = coalesce(var.resource_group_name, try(local.config.azure.resourceGroup, null))
  apim_service_name           = coalesce(var.apim_service_name, try(local.config.apim.serviceName, null))
  apim_gateway_url            = coalesce(var.apim_gateway_url, try(local.config.apim.gatewayUrl, null))
  databricks_api_name         = coalesce(var.databricks_api_name, try(local.config.apim.sourceApiId, null))
  product_name                = coalesce(var.product_name, try(local.config.apim.productId, null))
  subscription_name           = coalesce(var.subscription_name, try(local.config.apim.subscriptionName, null))
  databricks_workspace_url    = coalesce(var.databricks_workspace_url, try(local.config.databricks.workspaceUrl, null))
  databricks_warehouse_id     = coalesce(var.databricks_warehouse_id, try(local.config.databricks.warehouseId, null))
  databricks_catalog          = coalesce(var.databricks_catalog, try(local.config.databricks.catalog, null))
  databricks_schema           = coalesce(var.databricks_schema, try(local.config.databricks.schema, null))
  databricks_rate_limit_calls = coalesce(var.databricks_rate_limit_calls, try(local.config.apim.rateLimits.databricksCalls, null))
  genie_rate_limit_calls      = coalesce(var.genie_rate_limit_calls, try(local.config.apim.rateLimits.genieCalls, null))
  rate_limit_renewal_period   = coalesce(var.rate_limit_renewal_period_seconds, try(local.config.apim.rateLimits.renewalPeriodSeconds, null))
  sql_wait_timeout            = coalesce(var.sql_wait_timeout, try(local.config.apim.timeouts.sqlWait, null))
  databricks_api_display_name = coalesce(var.databricks_api_display_name, try(local.config.apim.databricksApiDisplayName, null))
  databricks_api_description  = coalesce(var.databricks_api_description, try(local.config.apim.databricksApiDescription, null))
  genie_api_display_name      = coalesce(var.genie_api_display_name, try(local.config.apim.genieApiDisplayName, null))
  genie_api_description       = coalesce(var.genie_api_description, try(local.config.apim.genieApiDescription, null))
  product_display_name        = coalesce(var.product_display_name, try(local.config.apim.productDisplayName, null))
  product_description         = coalesce(var.product_description, try(local.config.apim.productDescription, null))
  subscription_display_name   = coalesce(var.subscription_display_name, try(local.config.apim.subscriptionDisplayName, null))

  named_values = {
    databricks-workspace-url             = local.databricks_workspace_url
    databricks-warehouse-id              = local.databricks_warehouse_id
    databricks-catalog                   = local.databricks_catalog
    databricks-schema                    = local.databricks_schema
    databricks-genie-space-id            = var.genie_space_id
    databricks-rate-limit-calls          = tostring(local.databricks_rate_limit_calls)
    databricks-rate-limit-renewal-period = tostring(local.rate_limit_renewal_period)
    genie-rate-limit-calls               = tostring(local.genie_rate_limit_calls)
    genie-rate-limit-renewal-period      = tostring(local.rate_limit_renewal_period)
    databricks-sql-wait-timeout          = local.sql_wait_timeout
  }
}

data "azurerm_api_management" "this" {
  name                = local.apim_service_name
  resource_group_name = local.resource_group_name
}

resource "azapi_resource" "named_value" {
  for_each = local.named_values

  type      = "Microsoft.ApiManagement/service/namedValues@2023-09-01-preview"
  name      = each.key
  parent_id = data.azurerm_api_management.this.id

  body = {
    properties = {
      displayName = each.key
      value       = each.value
      secret      = false
    }
  }
}

resource "azapi_resource" "databricks_api" {
  type      = "Microsoft.ApiManagement/service/apis@2023-09-01-preview"
  name      = local.databricks_api_name
  parent_id = data.azurerm_api_management.this.id

  body = {
    properties = {
      displayName          = local.databricks_api_display_name
      description          = local.databricks_api_description
      path                 = "databricks"
      protocols            = ["https"]
      subscriptionRequired = true
      subscriptionKeyParameterNames = {
        header = "Ocp-Apim-Subscription-Key"
      }
    }
  }
}

resource "azapi_resource" "databricks_api_policy" {
  type      = "Microsoft.ApiManagement/service/apis/policies@2023-09-01-preview"
  name      = "policy"
  parent_id = azapi_resource.databricks_api.id

  body = {
    properties = {
      format = "rawxml"
      value  = file("${path.module}/policies/databricks-api-policy.xml")
    }
  }

  depends_on = [
    azapi_resource.named_value["databricks-workspace-url"],
    azapi_resource.named_value["databricks-rate-limit-calls"],
    azapi_resource.named_value["databricks-rate-limit-renewal-period"]
  ]
}

resource "azapi_resource" "query_operation" {
  type      = "Microsoft.ApiManagement/service/apis/operations@2023-09-01-preview"
  name      = "query"
  parent_id = azapi_resource.databricks_api.id

  body = {
    properties = {
      displayName = "Run SQL query"
      method      = "POST"
      urlTemplate = "/query"
      description = "Body: { \"statement\": \"SELECT ...\" }. Returns JSON_ARRAY rows."
      request = {
        representations = [
          {
            contentType = "application/json"
            examples = {
              default = {
                value = {
                  statement = "SHOW TABLES IN ${local.databricks_catalog}.${local.databricks_schema}"
                }
              }
            }
          }
        ]
      }
      responses = [
        {
          statusCode  = 200
          description = "SQL result"
        }
      ]
    }
  }
}

resource "azapi_resource" "query_operation_policy" {
  type      = "Microsoft.ApiManagement/service/apis/operations/policies@2023-09-01-preview"
  name      = "policy"
  parent_id = azapi_resource.query_operation.id

  body = {
    properties = {
      format = "rawxml"
      value  = file("${path.module}/policies/databricks-query-operation-policy.xml")
    }
  }

  depends_on = [
    azapi_resource.named_value["databricks-warehouse-id"],
    azapi_resource.named_value["databricks-sql-wait-timeout"]
  ]
}

resource "azapi_resource" "tables_operation" {
  type      = "Microsoft.ApiManagement/service/apis/operations@2023-09-01-preview"
  name      = "tables"
  parent_id = azapi_resource.databricks_api.id

  body = {
    properties = {
      displayName = "List schema tables"
      method      = "GET"
      urlTemplate = "/tables"
      description = "Lists tables in the configured Unity Catalog schema."
      responses = [
        {
          statusCode  = 200
          description = "Table list"
        }
      ]
    }
  }
}

resource "azapi_resource" "tables_operation_policy" {
  type      = "Microsoft.ApiManagement/service/apis/operations/policies@2023-09-01-preview"
  name      = "policy"
  parent_id = azapi_resource.tables_operation.id

  body = {
    properties = {
      format = "rawxml"
      value  = file("${path.module}/policies/databricks-tables-operation-policy.xml")
    }
  }

  depends_on = [
    azapi_resource.named_value["databricks-warehouse-id"],
    azapi_resource.named_value["databricks-catalog"],
    azapi_resource.named_value["databricks-schema"],
    azapi_resource.named_value["databricks-sql-wait-timeout"]
  ]
}

resource "azapi_resource" "genie_api" {
  type      = "Microsoft.ApiManagement/service/apis@2023-09-01-preview"
  name      = "databricks-genie"
  parent_id = data.azurerm_api_management.this.id

  body = {
    properties = {
      displayName          = local.genie_api_display_name
      description          = local.genie_api_description
      path                 = "databricks-genie"
      protocols            = ["https"]
      subscriptionRequired = true
      subscriptionKeyParameterNames = {
        header = "Ocp-Apim-Subscription-Key"
      }
    }
  }
}

resource "azapi_resource" "genie_api_policy" {
  type      = "Microsoft.ApiManagement/service/apis/policies@2023-09-01-preview"
  name      = "policy"
  parent_id = azapi_resource.genie_api.id

  body = {
    properties = {
      format = "rawxml"
      value  = file("${path.module}/policies/genie-api-policy.xml")
    }
  }

  depends_on = [
    azapi_resource.named_value["databricks-workspace-url"],
    azapi_resource.named_value["genie-rate-limit-calls"],
    azapi_resource.named_value["genie-rate-limit-renewal-period"]
  ]
}

resource "azapi_resource" "genie_ask_operation" {
  type      = "Microsoft.ApiManagement/service/apis/operations@2023-09-01-preview"
  name      = "ask"
  parent_id = azapi_resource.genie_api.id

  body = {
    properties = {
      displayName = "Ask Genie (start conversation)"
      method      = "POST"
      urlTemplate = "/genie/ask"
      description = "Body: { \"content\": \"natural-language question\" }."
      request = {
        representations = [
          {
            contentType = "application/json"
            examples = {
              default = {
                value = {
                  content = "What was total revenue by region last quarter?"
                }
              }
            }
          }
        ]
      }
      responses = [
        {
          statusCode  = 200
          description = "Conversation + message ids"
        }
      ]
    }
  }
}

resource "azapi_resource" "genie_ask_operation_policy" {
  type      = "Microsoft.ApiManagement/service/apis/operations/policies@2023-09-01-preview"
  name      = "policy"
  parent_id = azapi_resource.genie_ask_operation.id

  body = {
    properties = {
      format = "rawxml"
      value  = file("${path.module}/policies/genie-start-operation-policy.xml")
    }
  }

  depends_on = [azapi_resource.named_value["databricks-genie-space-id"]]
}

resource "azapi_resource" "genie_follow_up_operation" {
  type      = "Microsoft.ApiManagement/service/apis/operations@2023-09-01-preview"
  name      = "follow-up"
  parent_id = azapi_resource.genie_api.id

  body = {
    properties = {
      displayName = "Ask Genie follow-up"
      method      = "POST"
      urlTemplate = "/genie/conversations/{conversationId}/messages"
      templateParameters = [
        {
          name     = "conversationId"
          type     = "string"
          required = true
        }
      ]
      responses = [
        {
          statusCode  = 200
          description = "Message"
        }
      ]
    }
  }
}

resource "azapi_resource" "genie_follow_up_operation_policy" {
  type      = "Microsoft.ApiManagement/service/apis/operations/policies@2023-09-01-preview"
  name      = "policy"
  parent_id = azapi_resource.genie_follow_up_operation.id

  body = {
    properties = {
      format = "rawxml"
      value  = file("${path.module}/policies/genie-followup-operation-policy.xml")
    }
  }

  depends_on = [azapi_resource.named_value["databricks-genie-space-id"]]
}

resource "azapi_resource" "genie_result_operation" {
  type      = "Microsoft.ApiManagement/service/apis/operations@2023-09-01-preview"
  name      = "result"
  parent_id = azapi_resource.genie_api.id

  body = {
    properties = {
      displayName = "Get Genie query result"
      method      = "GET"
      urlTemplate = "/genie/conversations/{conversationId}/messages/{messageId}/result"
      templateParameters = [
        {
          name     = "conversationId"
          type     = "string"
          required = true
        },
        {
          name     = "messageId"
          type     = "string"
          required = true
        }
      ]
      responses = [
        {
          statusCode  = 200
          description = "Query result"
        }
      ]
    }
  }
}

resource "azapi_resource" "genie_result_operation_policy" {
  type      = "Microsoft.ApiManagement/service/apis/operations/policies@2023-09-01-preview"
  name      = "policy"
  parent_id = azapi_resource.genie_result_operation.id

  body = {
    properties = {
      format = "rawxml"
      value  = file("${path.module}/policies/genie-result-operation-policy.xml")
    }
  }

  depends_on = [azapi_resource.named_value["databricks-genie-space-id"]]
}

resource "azapi_resource" "genie_message_operation" {
  type      = "Microsoft.ApiManagement/service/apis/operations@2023-09-01-preview"
  name      = "message"
  parent_id = azapi_resource.genie_api.id

  body = {
    properties = {
      displayName = "Get Genie message status"
      method      = "GET"
      urlTemplate = "/genie/conversations/{conversationId}/messages/{messageId}"
      description = "Poll until status is COMPLETED, then read the text answer and generated SQL from attachments."
      templateParameters = [
        {
          name     = "conversationId"
          type     = "string"
          required = true
        },
        {
          name     = "messageId"
          type     = "string"
          required = true
        }
      ]
      responses = [
        {
          statusCode  = 200
          description = "Message status and attachments"
        }
      ]
    }
  }
}

resource "azapi_resource" "genie_message_operation_policy" {
  type      = "Microsoft.ApiManagement/service/apis/operations/policies@2023-09-01-preview"
  name      = "policy"
  parent_id = azapi_resource.genie_message_operation.id

  body = {
    properties = {
      format = "rawxml"
      value  = file("${path.module}/policies/genie-message-operation-policy.xml")
    }
  }

  depends_on = [azapi_resource.named_value["databricks-genie-space-id"]]
}

resource "azapi_resource" "product" {
  type      = "Microsoft.ApiManagement/service/products@2023-09-01-preview"
  name      = local.product_name
  parent_id = data.azurerm_api_management.this.id

  body = {
    properties = {
      displayName          = local.product_display_name
      description          = local.product_description
      subscriptionRequired = true
      approvalRequired     = false
      state                = "published"
    }
  }
}

resource "azapi_resource" "product_databricks_api_link" {
  type      = "Microsoft.ApiManagement/service/products/apiLinks@2023-09-01-preview"
  name      = "link-databricks"
  parent_id = azapi_resource.product.id

  body = {
    properties = {
      apiId = azapi_resource.databricks_api.id
    }
  }
}

resource "azapi_resource" "product_genie_api_link" {
  type      = "Microsoft.ApiManagement/service/products/apiLinks@2023-09-01-preview"
  name      = "link-databricks-genie"
  parent_id = azapi_resource.product.id

  body = {
    properties = {
      apiId = azapi_resource.genie_api.id
    }
  }
}

resource "azapi_resource" "databricks_subscription" {
  type      = "Microsoft.ApiManagement/service/subscriptions@2023-09-01-preview"
  name      = local.subscription_name
  parent_id = data.azurerm_api_management.this.id

  body = {
    properties = {
      allowTracing = false
      displayName  = local.subscription_display_name
      scope        = azapi_resource.product.id
      state        = "active"
    }
  }

  depends_on = [
    azapi_resource.product_databricks_api_link,
    azapi_resource.product_genie_api_link
  ]
}