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
