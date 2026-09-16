locals {
  config = jsondecode(file(var.config_path))

  subscription_id          = coalesce(var.subscription_id, try(local.config.azure.subscriptionId, null))
  resource_group_name      = coalesce(var.resource_group_name, try(local.config.azure.resourceGroup, null))
  apim_service_name        = coalesce(var.apim_service_name, try(local.config.apim.serviceName, null))
  apim_gateway_url         = coalesce(var.apim_gateway_url, try(local.config.apim.gatewayUrl, null))
  tenant_id                = coalesce(var.tenant_id, try(local.config.azure.tenantId, null))
  api_client_id            = coalesce(var.api_client_id, try(local.config.obo.apiClientId, null))
  connector_client_id      = coalesce(var.connector_client_id, try(local.config.obo.connectorClientId, null))
  allowed_user_id          = coalesce(var.allowed_user_id, try(local.config.obo.allowedUserId, null))
  databricks_workspace_url = coalesce(var.databricks_workspace_url, try(local.config.databricks.workspaceUrl, null))
  broker_url = coalesce(
    var.broker_url,
    try(local.config.obo.brokerUrl, null),
    try("https://${local.config.obo.functionName}.azurewebsites.net/api/exchange", null)
  )
  insights_name                         = coalesce(var.insights_name, try(local.config.observability.applicationInsightsName, null))
  obo_scope                             = coalesce(var.obo_scope, try(local.config.obo.scope, null))
  obo_rate_limit_calls                  = coalesce(var.obo_rate_limit_calls, try(local.config.apim.rateLimits.oboCalls, null))
  obo_rate_limit_renewal_period_seconds = coalesce(var.obo_rate_limit_renewal_period_seconds, try(local.config.apim.rateLimits.renewalPeriodSeconds, null))
  obo_broker_timeout_seconds            = coalesce(var.obo_broker_timeout_seconds, try(local.config.apim.timeouts.oboBrokerSeconds, null))
  api_display_name                      = coalesce(var.api_display_name, try(local.config.obo.apiDisplayName, null))
  diagnostic_sampling_percentage        = coalesce(var.diagnostic_sampling_percentage, try(local.config.observability.samplingPercentage, null))

  named_values = {
    databricks-workspace-url            = local.databricks_workspace_url
    databricks-genie-space-id           = var.genie_space_id
    genie-obo-tenant-id                 = local.tenant_id
    genie-obo-api-client-id             = local.api_client_id
    genie-obo-connector-client-id       = local.connector_client_id
    genie-obo-allowed-user-id           = local.allowed_user_id
    genie-obo-broker-url                = local.broker_url
    genie-obo-scope                     = local.obo_scope
    genie-obo-rate-limit-calls          = tostring(local.obo_rate_limit_calls)
    genie-obo-rate-limit-renewal-period = tostring(local.obo_rate_limit_renewal_period_seconds)
    genie-obo-broker-timeout            = tostring(local.obo_broker_timeout_seconds)
  }

  operations = {
    ask = {
      method      = "POST"
      path        = "/genie/ask"
      parameters  = []
      policy_file = "genie-start-operation-policy.xml"
    }
    follow-up = {
      method = "POST"
      path   = "/genie/conversations/{conversationId}/messages"
      parameters = [
        {
          name     = "conversationId"
          type     = "string"
          required = true
        }
      ]
      policy_file = "genie-followup-operation-policy.xml"
    }
    message = {
      method = "GET"
      path   = "/genie/conversations/{conversationId}/messages/{messageId}"
      parameters = [
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
      policy_file = "genie-message-operation-policy.xml"
    }
    result = {
      method = "GET"
      path   = "/genie/conversations/{conversationId}/messages/{messageId}/result"
      parameters = [
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
      policy_file = "genie-result-operation-policy.xml"
    }
  }
}

data "azurerm_api_management" "this" {
  name                = local.apim_service_name
  resource_group_name = local.resource_group_name
}

data "azurerm_application_insights" "this" {
  name                = local.insights_name
  resource_group_name = local.resource_group_name
}

resource "azapi_resource" "logger" {
  type      = "Microsoft.ApiManagement/service/loggers@2023-09-01-preview"
  name      = "genie-obo-insights"
  parent_id = data.azurerm_api_management.this.id

  body = {
    properties = {
      loggerType = "applicationInsights"
      credentials = {
        instrumentationKey = data.azurerm_application_insights.this.instrumentation_key
      }
      resourceId = data.azurerm_application_insights.this.id
      isBuffered = true
    }
  }
}

resource "azapi_resource" "audit_fragment" {
  type      = "Microsoft.ApiManagement/service/policyFragments@2023-09-01-preview"
  name      = "genie-obo-audit"
  parent_id = data.azurerm_api_management.this.id

  body = {
    properties = {
      format = "rawxml"
      value  = file("${path.module}/policies/genie-obo-audit-fragment.xml")
    }
  }
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

resource "azapi_resource" "api" {
  type      = "Microsoft.ApiManagement/service/apis@2023-09-01-preview"
  name      = "databricks-genie-obo"
  parent_id = data.azurerm_api_management.this.id

  body = {
    properties = {
      displayName          = local.api_display_name
      description          = var.api_description
      path                 = "databricks-genie-obo"
      protocols            = ["https"]
      subscriptionRequired = false
    }
  }
}

resource "azapi_resource" "api_policy" {
  type      = "Microsoft.ApiManagement/service/apis/policies@2023-09-01-preview"
  name      = "policy"
  parent_id = azapi_resource.api.id

  body = {
    properties = {
      format = "rawxml"
      value  = file("${path.module}/policies/genie-obo-api-policy.xml")
    }
  }

  depends_on = [
    azapi_resource.named_value,
    azapi_resource.audit_fragment
  ]
}

resource "azapi_resource" "diagnostic" {
  type      = "Microsoft.ApiManagement/service/apis/diagnostics@2023-09-01-preview"
  name      = "applicationinsights"
  parent_id = azapi_resource.api.id

  body = {
    properties = {
      loggerId  = azapi_resource.logger.id
      alwaysLog = "allErrors"
      sampling = {
        samplingType = "fixed"
        percentage   = local.diagnostic_sampling_percentage
      }
      verbosity               = "information"
      logClientIp             = false
      httpCorrelationProtocol = "W3C"
      frontend = {
        request = {
          headers = []
          body = {
            bytes = 0
          }
        }
        response = {
          headers = []
          body = {
            bytes = 0
          }
        }
      }
      backend = {
        request = {
          headers = []
          body = {
            bytes = 0
          }
        }
        response = {
          headers = []
          body = {
            bytes = 0
          }
        }
      }
    }
  }
}

resource "azapi_resource" "operation" {
  for_each = local.operations

  type      = "Microsoft.ApiManagement/service/apis/operations@2023-09-01-preview"
  name      = each.key
  parent_id = azapi_resource.api.id

  body = {
    properties = {
      displayName        = each.key
      method             = each.value.method
      urlTemplate        = each.value.path
      templateParameters = each.value.parameters
      responses = [
        {
          statusCode = 200
        }
      ]
    }
  }
}

resource "azapi_resource" "operation_policy" {
  for_each = local.operations

  type      = "Microsoft.ApiManagement/service/apis/operations/policies@2023-09-01-preview"
  name      = "policy"
  parent_id = azapi_resource.operation[each.key].id

  body = {
    properties = {
      format = "rawxml"
      value  = file("${path.module}/policies/${each.value.policy_file}")
    }
  }

  depends_on = [azapi_resource.named_value]
}