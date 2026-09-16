output "workspaceName" {
  description = "Name of the Log Analytics workspace."
  value       = azapi_resource.workspace.name
}

output "workspaceResourceId" {
  description = "Resource ID of the Log Analytics workspace."
  value       = azapi_resource.workspace.id
}

output "workspaceCustomerId" {
  description = "Customer ID of the Log Analytics workspace."
  value       = azapi_resource.workspace.output.properties.customerId
}

output "diagnosticSettingName" {
  description = "Name of the APIM diagnostic setting."
  value       = azapi_resource.apim_diagnostics.name
}