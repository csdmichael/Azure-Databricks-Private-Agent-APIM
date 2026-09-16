output "cosmosEndpoint" {
  description = "Cosmos DB document endpoint."
  value       = azurerm_cosmosdb_account.analytics.endpoint
}

output "cosmosAccountName" {
  description = "Cosmos DB account name."
  value       = azurerm_cosmosdb_account.analytics.name
}

output "subnetId" {
  description = "Web app integration subnet resource ID."
  value       = azurerm_subnet.integration.id
}