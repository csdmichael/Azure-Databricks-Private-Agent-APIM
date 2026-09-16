locals {
  config = jsondecode(file(var.config_path))

  subscription_id = coalesce(var.subscription_id, try(local.config.azure.subscriptionId, null))
  tenant_id       = coalesce(var.tenant_id, try(local.config.azure.tenantId, null))
  resource_group_name = coalesce(
    var.resource_group_name,
    try(local.config.azure.resourceGroup, null)
  )
  original_foundry_account_name = coalesce(
    var.original_foundry_account_name,
    try(local.config.foundry.original.accountName, null)
  )
  original_project_name = coalesce(
    var.original_project_name,
    try(local.config.foundry.original.projectName, null)
  )
  private_foundry_account_name = coalesce(
    var.private_foundry_account_name,
    try(local.config.foundry.private.accountName, null)
  )
  private_project_name = coalesce(
    var.private_project_name,
    try(local.config.foundry.private.projectName, null)
  )
  log_analytics_workspace_name = coalesce(
    var.log_analytics_workspace_name,
    try(local.config.observability.logAnalyticsWorkspaceName, null)
  )
  application_insights_name = coalesce(
    var.application_insights_name,
    try(local.config.observability.applicationInsightsName, null)
  )

  trace_reader_role_definition_ids = [
    "73c42c96-874c-492b-b04d-ab87d138a893",
    "dbc9c667-e97f-4491-aee6-90b9cf960190",
  ]

  role_assignment_guid_namespace = "11fb06fb-712d-4ddd-98c7-e71bbd588830"
}

data "azurerm_resource_group" "this" {
  name = local.resource_group_name
}

data "azapi_resource" "workspace" {
  type      = "Microsoft.OperationalInsights/workspaces@2023-09-01"
  name      = local.log_analytics_workspace_name
  parent_id = data.azurerm_resource_group.this.id
}

data "azapi_resource" "application_insights" {
  type      = "Microsoft.Insights/components@2020-02-02"
  name      = local.application_insights_name
  parent_id = data.azurerm_resource_group.this.id

  response_export_values = [
    "properties.ConnectionString",
  ]
}

data "azapi_resource" "original_foundry_account" {
  type      = "Microsoft.CognitiveServices/accounts@2026-05-01"
  name      = local.original_foundry_account_name
  parent_id = data.azurerm_resource_group.this.id
}

data "azapi_resource" "original_project" {
  type      = "Microsoft.CognitiveServices/accounts/projects@2025-06-01"
  name      = local.original_project_name
  parent_id = data.azapi_resource.original_foundry_account.id

  response_export_values = [
    "identity.principalId",
  ]
}

data "azapi_resource" "private_foundry_account" {
  type      = "Microsoft.CognitiveServices/accounts@2026-05-01"
  name      = local.private_foundry_account_name
  parent_id = data.azurerm_resource_group.this.id
}

data "azapi_resource" "private_project" {
  type      = "Microsoft.CognitiveServices/accounts/projects@2025-06-01"
  name      = local.private_project_name
  parent_id = data.azapi_resource.private_foundry_account.id

  response_export_values = [
    "identity.principalId",
  ]
}

resource "azapi_resource" "original_account_insights_connection" {
  type      = "Microsoft.CognitiveServices/accounts/connections@2025-04-01-preview"
  name      = local.application_insights_name
  parent_id = data.azapi_resource.original_foundry_account.id

  body = {
    properties = {
      category      = "AppInsights"
      target        = data.azapi_resource.application_insights.id
      authType      = "ApiKey"
      isSharedToAll = true
      credentials = {
        key = sensitive(data.azapi_resource.application_insights.output.properties.ConnectionString)
      }
      metadata = {
        ApiType    = "Azure"
        ResourceId = data.azapi_resource.application_insights.id
      }
    }
  }
}

resource "azapi_resource" "private_account_insights_connection" {
  type      = "Microsoft.CognitiveServices/accounts/connections@2025-04-01-preview"
  name      = local.application_insights_name
  parent_id = data.azapi_resource.private_foundry_account.id

  body = {
    properties = {
      category      = "AppInsights"
      target        = data.azapi_resource.application_insights.id
      authType      = "ApiKey"
      isSharedToAll = true
      credentials = {
        key = sensitive(data.azapi_resource.application_insights.output.properties.ConnectionString)
      }
      metadata = {
        ApiType    = "Azure"
        ResourceId = data.azapi_resource.application_insights.id
      }
    }
  }
}

resource "azapi_resource" "original_project_trace_readers" {
  for_each = toset(local.trace_reader_role_definition_ids)

  type = "Microsoft.Authorization/roleAssignments@2022-04-01"
  name = uuidv5(
    local.role_assignment_guid_namespace,
    join("-", [data.azapi_resource.application_insights.id, data.azapi_resource.original_project.id, each.value])
  )
  parent_id = data.azapi_resource.application_insights.id

  body = {
    properties = {
      principalId      = data.azapi_resource.original_project.output.identity.principalId
      principalType    = "ServicePrincipal"
      roleDefinitionId = "/subscriptions/${local.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/${each.value}"
    }
  }
}

resource "azapi_resource" "private_project_trace_readers" {
  for_each = toset(local.trace_reader_role_definition_ids)

  type = "Microsoft.Authorization/roleAssignments@2022-04-01"
  name = uuidv5(
    local.role_assignment_guid_namespace,
    join("-", [data.azapi_resource.application_insights.id, data.azapi_resource.private_project.id, each.value])
  )
  parent_id = data.azapi_resource.application_insights.id

  body = {
    properties = {
      principalId      = data.azapi_resource.private_project.output.identity.principalId
      principalType    = "ServicePrincipal"
      roleDefinitionId = "/subscriptions/${local.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/${each.value}"
    }
  }
}

resource "azapi_resource" "original_project_diagnostics" {
  type      = "Microsoft.Insights/diagnosticSettings@2021-05-01-preview"
  name      = "${local.original_foundry_account_name}-${local.original_project_name}-logs"
  parent_id = data.azapi_resource.original_project.id

  body = {
    properties = {
      workspaceId = data.azapi_resource.workspace.id
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

resource "azapi_resource" "private_project_diagnostics" {
  type      = "Microsoft.Insights/diagnosticSettings@2021-05-01-preview"
  name      = "${local.private_foundry_account_name}-${local.private_project_name}-logs"
  parent_id = data.azapi_resource.private_project.id

  body = {
    properties = {
      workspaceId = data.azapi_resource.workspace.id
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