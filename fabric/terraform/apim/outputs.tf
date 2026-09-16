output "apim_principal_id" {
  description = "System-assigned managed identity principal ID that must receive the broker application role."
  value       = data.azurerm_api_management.this.identity[0].principal_id
}

output "lakehouse_api_url" {
  description = "Fabric Lakehouse OAuth REST API URL."
  value       = "${local.apim_gateway_url}/${local.config.apim.lakehouseApiPath}"
}

output "data_agent_api_url" {
  description = "Fabric Data Agent OAuth REST API URL."
  value       = "${local.apim_gateway_url}/${local.config.apim.dataAgentApiPath}"
}

output "lakehouse_mcp_url" {
  description = "Fabric Lakehouse MCP endpoint."
  value       = "${local.apim_gateway_url}/${local.config.apim.lakehouseMcpPath}/mcp"
}

output "data_agent_mcp_url" {
  description = "Fabric Data Agent MCP endpoint."
  value       = "${local.apim_gateway_url}/${local.config.apim.dataAgentMcpPath}/mcp"
}

output "product_id" {
  description = "Resource ID of the APIM product containing both REST APIs and both MCP APIs."
  value       = azapi_resource.product.id
}

output "private_dns_zone_id" {
  description = "Resource ID of the created or reused privatelink.azurewebsites.net zone."
  value       = local.private_dns_zone_id
}