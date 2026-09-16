locals {
  config = jsondecode(file(var.config_path))

  subscription_id = coalesce(var.subscription_id, try(local.config.azure.subscriptionId, null))
  tenant_id       = coalesce(var.tenant_id, try(local.config.azure.tenantId, null))
  resource_group_name = coalesce(
    var.resource_group_name,
    try(local.config.azure.resourceGroup, null)
  )
  apim_service_name = coalesce(
    var.apim_service_name,
    try(local.config.apim.serviceName, null)
  )
  location = coalesce(
    var.location,
    try(local.config.network.apimLocation, null)
  )
  workspace_name = coalesce(
    var.workspace_name,
    try(local.config.observability.logAnalyticsWorkspaceName, null)
  )
  workspace_sku_name = coalesce(
    var.workspace_sku_name,
    try(local.config.observability.logAnalyticsWorkspaceSkuName, null),
    "PerGB2018"
  )
  retention_in_days = coalesce(
    var.retention_in_days,
    try(local.config.observability.retentionInDays, null)
  )
  daily_quota_gb = coalesce(
    var.daily_quota_gb,
    try(local.config.observability.dailyQuotaGb, null)
  )
  tags = coalesce(var.tags, try(tomap(local.config.tags), null), {})

  diagnostic_setting_name = "${local.apim_service_name}-to-log-analytics"
}

data "azurerm_resource_group" "this" {
  name = local.resource_group_name
}

data "azapi_resource" "apim" {
  type      = "Microsoft.ApiManagement/service@2024-05-01"
  name      = local.apim_service_name
  parent_id = data.azurerm_resource_group.this.id
}

resource "azapi_resource" "workspace" {
  type      = "Microsoft.OperationalInsights/workspaces@2023-09-01"
  name      = local.workspace_name
  parent_id = data.azurerm_resource_group.this.id
  location  = local.location
  tags      = local.tags

  body = {
    properties = {
      sku = {
        name = local.workspace_sku_name
      }
      retentionInDays = local.retention_in_days
      workspaceCapping = {
        dailyQuotaGb = local.daily_quota_gb
      }
      publicNetworkAccessForIngestion = "Enabled"
      publicNetworkAccessForQuery     = "Enabled"
      features = {
        enableLogAccessUsingOnlyResourcePermissions = true
      }
    }
  }

  response_export_values = [
    "properties.customerId",
  ]

  lifecycle {
    precondition {
      condition     = local.retention_in_days >= 30 && local.retention_in_days <= 730 && floor(local.retention_in_days) == local.retention_in_days
      error_message = "retention_in_days must be an integer between 30 and 730."
    }

    precondition {
      condition     = floor(local.daily_quota_gb) == local.daily_quota_gb
      error_message = "daily_quota_gb must be an integer."
    }
  }
}

resource "azapi_resource" "apim_diagnostics" {
  type      = "Microsoft.Insights/diagnosticSettings@2021-05-01-preview"
  name      = local.diagnostic_setting_name
  parent_id = data.azapi_resource.apim.id

  body = {
    properties = {
      workspaceId = azapi_resource.workspace.id
      logs = [
        {
          categoryGroup = "allLogs"
          enabled       = true
        }
      ]
      metrics = [
        {
          category = "AllMetrics"
          enabled  = true
        }
      ]
    }
  }
}