variable "config_path" {
  description = "Path to the shared deployment JSON configuration file."
  type        = string
  default     = "../../config/deployment.json"
}

variable "subscription_id" {
  description = "Optional Azure subscription ID override."
  type        = string
  default     = null
  nullable    = true
}

variable "tenant_id" {
  description = "Optional Microsoft Entra tenant ID override."
  type        = string
  default     = null
  nullable    = true
}

variable "resource_group_name" {
  description = "Optional resource group name override."
  type        = string
  default     = null
  nullable    = true
}

variable "original_foundry_account_name" {
  description = "Optional original Microsoft Foundry account name override."
  type        = string
  default     = null
  nullable    = true
}

variable "original_project_name" {
  description = "Optional original Microsoft Foundry project name override."
  type        = string
  default     = null
  nullable    = true
}

variable "private_foundry_account_name" {
  description = "Optional private-egress Microsoft Foundry account name override."
  type        = string
  default     = null
  nullable    = true
}

variable "private_project_name" {
  description = "Optional private-egress Microsoft Foundry project name override."
  type        = string
  default     = null
  nullable    = true
}

variable "log_analytics_workspace_name" {
  description = "Optional existing Log Analytics workspace name override."
  type        = string
  default     = null
  nullable    = true
}

variable "application_insights_name" {
  description = "Optional existing workspace-based Application Insights component name override."
  type        = string
  default     = null
  nullable    = true
}