variable "subscription_id" {
  description = "Azure subscription ID."
  type        = string
}

variable "resource_group_name" {
  description = "Existing resource group."
  type        = string
}

variable "location" {
  description = "Azure region for the web app and monitoring resources."
  type        = string
}

variable "tenant_id" {
  description = "Microsoft Entra tenant ID."
  type        = string
}

variable "foundry_account_name" {
  description = "Existing Microsoft Foundry account name."
  type        = string
}

variable "foundry_project_name" {
  description = "Existing Microsoft Foundry project name."
  type        = string
}

variable "foundry_agent_name" {
  description = "Foundry prompt agent name."
  type        = string
}

variable "apim_name" {
  description = "Existing API Management service name."
  type        = string
}

variable "obo_source_api_id" {
  description = "Existing delegated Databricks Genie API identifier."
  type        = string
  default     = "databricks-genie-obo"
}

variable "obo_mcp_api_id" {
  description = "MCP API identifier created over the delegated API."
  type        = string
  default     = "databricks-genie-obo-mcp"
}

variable "obo_mcp_path" {
  description = "MCP gateway path."
  type        = string
  default     = "databricks-genie-obo-mcp"
}

variable "bot_client_id" {
  description = "Single-tenant bot application client ID."
  type        = string
}

variable "bot_client_secret" {
  description = "Single-tenant bot application client secret."
  type        = string
  sensitive   = true
}

variable "bot_name" {
  description = "Azure Bot resource name."
  type        = string
}

variable "bot_app_name" {
  description = "Linux web app name."
  type        = string
}

variable "app_service_plan_name" {
  description = "Existing Linux App Service plan name."
  type        = string
  default     = "caldova-tokenomics-api-plan"
}

variable "oauth_connection_name" {
  description = "Azure Bot OAuth connection name."
  type        = string
  default     = "DatabricksGenieOBO"
}

variable "delegated_scope" {
  description = "Full delegated scope URI requested by the OAuth connection."
  type        = string
}

variable "tags" {
  description = "Resource tags."
  type        = map(string)
  default     = {}
}
