output "apimServiceName" {
  description = "API Management service name."
  value       = azurerm_api_management.this.name
}

output "apimResourceId" {
  description = "API Management resource ID."
  value       = azurerm_api_management.this.id
}

output "apimPrincipalId" {
  description = "API Management system-assigned managed identity principal ID."
  value       = azurerm_api_management.this.identity[0].principal_id
}

output "apimVnetName" {
  description = "API Management virtual network name."
  value       = azurerm_virtual_network.apim.name
}

output "apimVnetResourceId" {
  description = "API Management virtual network resource ID."
  value       = azurerm_virtual_network.apim.id
}

output "apimPrivateDnsZoneName" {
  description = "API Management private DNS zone name."
  value       = azurerm_private_dns_zone.apim.name
}

output "gatewayUrl" {
  description = "API Management gateway URL."
  value       = "https://${azurerm_api_management.this.name}.azure-api.net"
}

output "privateEndpointResourceId" {
  description = "API Management gateway private endpoint resource ID."
  value       = azurerm_private_endpoint.apim_gateway.id
}

output "publicNetworkAccessState" {
  description = "Configured API Management public network access state."
  value       = var.public_network_access
}