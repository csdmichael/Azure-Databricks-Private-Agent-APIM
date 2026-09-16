output "primaryVnetResourceId" {
  description = "Primary Power Platform virtual network resource ID."
  value       = azurerm_virtual_network.primary.id
}

output "primarySubnetResourceId" {
  description = "Primary delegated Power Platform subnet resource ID."
  value       = azurerm_subnet.primary.id
}

output "secondaryVnetResourceId" {
  description = "Secondary Power Platform virtual network resource ID."
  value       = azurerm_virtual_network.secondary.id
}

output "secondarySubnetResourceId" {
  description = "Secondary delegated Power Platform subnet resource ID."
  value       = azurerm_subnet.secondary.id
}

output "enterprisePolicyName" {
  description = "Power Platform network-injection enterprise-policy name."
  value       = azapi_resource.network_injection_policy.name
}

output "enterprisePolicyResourceId" {
  description = "Power Platform network-injection enterprise-policy resource ID."
  value       = azapi_resource.network_injection_policy.id
}