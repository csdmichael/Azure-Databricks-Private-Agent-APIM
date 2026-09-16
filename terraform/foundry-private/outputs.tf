output "foundryAccountId" {
  description = "Resource ID of the Microsoft Foundry account."
  value       = azapi_resource.foundry_account.id
}

output "foundryAccountPrincipalId" {
  description = "Principal ID of the Foundry account system-assigned identity."
  value       = azapi_resource.foundry_account.identity[0].principal_id
}

output "foundryProjectId" {
  description = "Resource ID of the Microsoft Foundry project."
  value       = azapi_resource.foundry_project.id
}

output "foundryProjectPrincipalId" {
  description = "Principal ID of the Foundry project system-assigned identity."
  value       = azapi_resource.foundry_project.identity[0].principal_id
}

output "foundryProjectEndpoint" {
  description = "Microsoft Foundry project data-plane endpoint."
  value       = "https://${local.foundry_account_name}.services.ai.azure.com/api/projects/${local.project_name}"
}

output "agentSubnetId" {
  description = "Resource ID of the delegated Foundry Agent Service subnet."
  value       = azurerm_subnet.agent.id
}

output "privateEndpointId" {
  description = "Resource ID of the Foundry private endpoint."
  value       = azurerm_private_endpoint.foundry.id
}

output "projectCapabilityHostId" {
  description = "Resource ID of the project Agents capability host."
  value       = azapi_resource.project_capability_host.id
}

output "modelDeploymentName" {
  description = "Name of the Foundry model deployment."
  value       = azapi_resource.model_deployment.name
}