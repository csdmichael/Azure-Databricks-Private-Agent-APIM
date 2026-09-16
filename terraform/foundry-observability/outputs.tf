output "logAnalyticsWorkspaceId" {
  description = "Resource ID of the existing Log Analytics workspace."
  value       = data.azapi_resource.workspace.id
}

output "applicationInsightsId" {
  description = "Resource ID of the existing Application Insights component."
  value       = data.azapi_resource.application_insights.id
}

output "originalProjectId" {
  description = "Resource ID of the original Microsoft Foundry project."
  value       = data.azapi_resource.original_project.id
}

output "privateProjectId" {
  description = "Resource ID of the private-egress Microsoft Foundry project."
  value       = data.azapi_resource.private_project.id
}