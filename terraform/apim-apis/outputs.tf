output "databricksApiPath" {
  description = "Databricks SQL API gateway URL."
  value       = "${trimsuffix(local.apim_gateway_url, "/")}/databricks"
}

output "genieApiPath" {
  description = "Databricks Genie API gateway URL."
  value       = "${trimsuffix(local.apim_gateway_url, "/")}/databricks-genie"
}

output "productName" {
  description = "APIM product resource name."
  value       = azapi_resource.product.name
}

output "subscriptionName" {
  description = "APIM subscription resource name."
  value       = azapi_resource.databricks_subscription.name
}