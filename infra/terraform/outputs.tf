output "workspace_name" {
  description = "Databricks workspace name."
  value       = azurerm_databricks_workspace.this.name
}

output "workspace_id" {
  description = "Databricks workspace Azure resource ID."
  value       = azurerm_databricks_workspace.this.id
}

output "workspace_url" {
  description = "Databricks workspace URL (host)."
  value       = "https://${azurerm_databricks_workspace.this.workspace_url}"
}

output "workspace_resource_id_short" {
  description = "Databricks workspace unique organization ID."
  value       = azurerm_databricks_workspace.this.workspace_id
}

output "managed_resource_group" {
  description = "Auto-created managed resource group for the workspace data plane."
  value       = azurerm_databricks_workspace.this.managed_resource_group_name
}

output "vnet_id" {
  description = "Injected virtual network ID."
  value       = azurerm_virtual_network.this.id
}

output "private_link_enabled" {
  description = "Whether the back-end Private Link endpoint was created."
  value       = var.enable_private_link
}

output "replica_workspace_name" {
  description = "Databricks replica workspace name."
  value       = azurerm_databricks_workspace.replica.name
}

output "replica_workspace_id" {
  description = "Databricks replica workspace Azure resource ID."
  value       = azurerm_databricks_workspace.replica.id
}

output "replica_workspace_url" {
  description = "Databricks replica workspace URL (host)."
  value       = "https://${azurerm_databricks_workspace.replica.workspace_url}"
}

output "replica_workspace_resource_id_short" {
  description = "Databricks replica workspace unique organization ID."
  value       = azurerm_databricks_workspace.replica.workspace_id
}

output "replica_managed_resource_group" {
  description = "Auto-created managed resource group for the replica data plane."
  value       = azurerm_databricks_workspace.replica.managed_resource_group_name
}

output "replica_vnet_id" {
  description = "Replica injected virtual network ID."
  value       = azurerm_virtual_network.replica.id
}
