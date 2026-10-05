data "azurerm_resource_group" "this" {
  name = var.resource_group_name
}

data "azurerm_api_management" "this" {
  name                = var.apim_name
  resource_group_name = data.azurerm_resource_group.this.name
}

locals {
  foundry_endpoint = "https://${var.foundry_account_name}.services.ai.azure.com/api/projects/${var.foundry_project_name}"
  mcp_server_url   = "https://${var.apim_name}.azure-api.net/${var.obo_mcp_path}/mcp"
  source_api_id    = "${data.azurerm_api_management.this.id}/apis/${var.obo_source_api_id}"
}

resource "azapi_resource" "obo_mcp" {
  type                      = "Microsoft.ApiManagement/service/apis@2024-06-01-preview"
  name                      = var.obo_mcp_api_id
  parent_id                 = data.azurerm_api_management.this.id
  schema_validation_enabled = false

  body = {
    properties = {
      type                 = "mcp"
      displayName          = "Databricks Genie OBO MCP"
      description          = "MCP facade over the existing APIM delegated-user API."
      path                 = var.obo_mcp_path
      protocols            = ["https"]
      subscriptionRequired = false
      mcpTools = [
        for operation in ["ask", "follow-up", "message", "result"] : {
          name        = operation
          operationId = "${local.source_api_id}/operations/${operation}"
        }
      ]
    }
  }
}

resource "azurerm_log_analytics_workspace" "this" {
  name                = "${var.bot_app_name}-logs"
  location            = var.location
  resource_group_name = data.azurerm_resource_group.this.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = var.tags
}

resource "azurerm_application_insights" "this" {
  name                = "${var.bot_app_name}-insights"
  location            = var.location
  resource_group_name = data.azurerm_resource_group.this.name
  application_type    = "web"
  workspace_id        = azurerm_log_analytics_workspace.this.id
  tags                = var.tags
}

data "azurerm_service_plan" "this" {
  name                = var.app_service_plan_name
  resource_group_name = data.azurerm_resource_group.this.name
}

resource "azurerm_linux_web_app" "bot" {
  name                = var.bot_app_name
  location            = var.location
  resource_group_name = data.azurerm_resource_group.this.name
  service_plan_id     = data.azurerm_service_plan.this.id
  https_only          = true
  tags                = var.tags

  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on           = true
    ftps_state          = "Disabled"
    minimum_tls_version = "1.2"
    app_command_line    = "node dist/index.js"

    application_stack {
      node_version = "20-lts"
    }
  }

  app_settings = {
    MicrosoftAppType                      = "SingleTenant"
    MicrosoftAppId                        = var.bot_client_id
    MicrosoftAppPassword                  = var.bot_client_secret
    MicrosoftAppTenantId                  = var.tenant_id
    OAUTH_CONNECTION_NAME                 = var.oauth_connection_name
    FOUNDRY_PROJECT_ENDPOINT              = local.foundry_endpoint
    FOUNDRY_AGENT_NAME                    = var.foundry_agent_name
    APPLICATIONINSIGHTS_CONNECTION_STRING = azurerm_application_insights.this.connection_string
    SCM_DO_BUILD_DURING_DEPLOYMENT        = "true"
  }
}

resource "azapi_resource" "bot" {
  type      = "Microsoft.BotService/botServices@2022-09-15"
  name      = var.bot_name
  parent_id = data.azurerm_resource_group.this.id
  location  = "global"
  tags      = var.tags

  body = {
    kind = "azurebot"
    sku = {
      name = "F0"
    }
    properties = {
      displayName         = "Foundry Databricks Genie"
      description         = "Teams channel for a Microsoft Foundry agent with Databricks OBO."
      endpoint            = "https://${azurerm_linux_web_app.bot.default_hostname}/api/messages"
      msaAppId            = var.bot_client_id
      msaAppTenantId      = var.tenant_id
      msaAppType          = "SingleTenant"
      publicNetworkAccess = "Enabled"
    }
  }
}

resource "azapi_resource" "teams_channel" {
  type      = "Microsoft.BotService/botServices/channels@2022-09-15"
  name      = "MsTeamsChannel"
  parent_id = azapi_resource.bot.id
  location  = "global"

  body = {
    properties = {
      channelName = "MsTeamsChannel"
      properties = {
        acceptedTerms = true
        enableCalling = false
        isEnabled     = true
      }
    }
  }
}

resource "azurerm_monitor_diagnostic_setting" "bot" {
  name                       = "bot-service-logs"
  target_resource_id         = azapi_resource.bot.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  enabled_log {
    category = "BotRequest"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

resource "azapi_resource" "oauth_connection" {
  type      = "Microsoft.BotService/botServices/connections@2022-09-15"
  name      = var.oauth_connection_name
  parent_id = azapi_resource.bot.id
  location  = "global"

  body = {
    properties = {
      clientId                   = var.bot_client_id
      clientSecret               = var.bot_client_secret
      scopes                     = var.delegated_scope
      serviceProviderId          = "30dd229c-58e3-4a48-bdfd-91ec48eb906c"
      serviceProviderDisplayName = "Azure Active Directory v2"
      parameters = [
        {
          key   = "tenantID"
          value = var.tenant_id
        }
      ]
    }
  }
}
