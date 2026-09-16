output "primaryPeeringId" {
  description = "Primary Power Platform-to-Databricks peering resource ID."
  value       = azurerm_virtual_network_peering.primary_to_databricks.id
}

output "secondaryPeeringId" {
  description = "Secondary Power Platform-to-Databricks peering resource ID."
  value       = azurerm_virtual_network_peering.secondary_to_databricks.id
}

output "primaryDnsLinkId" {
  description = "Databricks private DNS link resource ID for the primary Power Platform VNet."
  value       = azurerm_private_dns_zone_virtual_network_link.databricks_to_primary.id
}

output "secondaryDnsLinkId" {
  description = "Databricks private DNS link resource ID for the secondary Power Platform VNet."
  value       = azurerm_private_dns_zone_virtual_network_link.databricks_to_secondary.id
}