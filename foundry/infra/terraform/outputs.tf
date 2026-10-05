output "bot_endpoint" {
  description = "Azure Bot messaging endpoint."
  value       = "https://${azurerm_linux_web_app.bot.default_hostname}/api/messages"
}

output "foundry_project_endpoint" {
  description = "Microsoft Foundry project endpoint."
  value       = local.foundry_endpoint
}

output "mcp_server_url" {
  description = "APIM OBO MCP endpoint."
  value       = local.mcp_server_url
}

output "published_agent_url" {
  description = "Stable published-agent URL recorded by the deployment."
  value       = "https://ai.azure.com/nextgen/build/agents/${var.foundry_agent_name}"
}

output "foundry_mcp_oauth_redirect_url" {
  description = "Redirect URL that must be registered on the Foundry MCP OAuth app."
  value       = try(azapi_resource.foundry_mcp_connection.output.properties.redirectUrl, null)
}
