locals {
  config = jsondecode(file(var.config_path))

  subscription_id = local.config.azure.subscriptionId
  tenant_id       = local.config.azure.tenantId
  resource_group  = local.config.azure.resourceGroup
  location        = local.config.appService.location

  insights_name             = local.config.observability.applicationInsightsName
  log_analytics_workspace   = local.config.observability.logAnalyticsWorkspaceName
  insights_retention_days   = local.config.observability.retentionInDays
  insights_sampling_percent = local.config.observability.samplingPercentage

  log_analytics_reader_role_id = "/subscriptions/${local.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/73c42c96-874c-492b-b04d-ab87d138a893"
}

data "azurerm_resource_group" "this" {
  name = local.resource_group
}

data "azurerm_log_analytics_workspace" "observability" {
  name                = local.log_analytics_workspace
  resource_group_name = data.azurerm_resource_group.this.name
}

resource "azapi_resource" "application_insights" {
  type      = "Microsoft.Insights/components@2020-02-02"
  name      = local.insights_name
  parent_id = data.azurerm_resource_group.this.id
  location  = local.location

  body = {
    kind = "web"
    properties = {
      Application_Type    = "web"
      WorkspaceResourceId = data.azurerm_log_analytics_workspace.observability.id
      IngestionMode       = "LogAnalytics"
      RetentionInDays     = local.insights_retention_days
      DisableIpMasking    = false
      SamplingPercentage  = local.insights_sampling_percent
    }
  }

  response_export_values = [
    "properties.ConnectionString",
  ]
}

resource "azurerm_role_assignment" "showcase_log_reader" {
  name               = uuidv5("11fb06fb-712d-4ddd-98c7-e71bbd588830", "${data.azurerm_log_analytics_workspace.observability.id}-${var.showcase_principal_id}-log-reader")
  scope              = data.azurerm_log_analytics_workspace.observability.id
  role_definition_id = local.log_analytics_reader_role_id
  principal_id       = var.showcase_principal_id
  principal_type     = "ServicePrincipal"
}