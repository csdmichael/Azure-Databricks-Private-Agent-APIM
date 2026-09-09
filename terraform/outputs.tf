output "resource_group_name" {
  description = "Resource group that holds every Caldova resource."
  value       = data.azurerm_resource_group.this.name
}

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

output "managed_resource_group" {
  description = "Auto-created managed resource group for the workspace data plane."
  value       = azurerm_databricks_workspace.this.managed_resource_group_name
}

output "vnet_name" {
  description = "Injected virtual network name, consumed by the APIM deployment."
  value       = azurerm_virtual_network.this.name
}

output "vnet_id" {
  description = "Injected virtual network resource ID."
  value       = azurerm_virtual_network.this.id
}

output "databricks_private_dns_zone_name" {
  description = "Private DNS zone that resolves the workspace private endpoints."
  value       = azurerm_private_dns_zone.databricks.name
}

output "public_network_access_enabled" {
  description = "False once the stage 2 lockdown has been applied."
  value       = azurerm_databricks_workspace.this.public_network_access_enabled
}
