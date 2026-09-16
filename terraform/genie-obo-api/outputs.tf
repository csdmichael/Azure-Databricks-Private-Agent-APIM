output "apiUrl" {
  description = "Delegated Databricks Genie API gateway URL."
  value       = "${trimsuffix(local.apim_gateway_url, "/")}/databricks-genie-obo"
}