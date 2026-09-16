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

variable "apim_service_name" {
  description = "Optional existing API Management service name override."
  type        = string
  default     = null
  nullable    = true
}

variable "location" {
  description = "Optional Log Analytics workspace region override."
  type        = string
  default     = null
  nullable    = true
}

variable "workspace_name" {
  description = "Optional Log Analytics workspace name override."
  type        = string
  default     = null
  nullable    = true
}

variable "workspace_sku_name" {
  description = "Optional Log Analytics workspace SKU override."
  type        = string
  default     = null
  nullable    = true
}

variable "retention_in_days" {
  description = "Optional Log Analytics retention override in days."
  type        = number
  default     = null
  nullable    = true
}

variable "daily_quota_gb" {
  description = "Optional daily Log Analytics ingestion cap in GB; -1 disables the cap."
  type        = number
  default     = null
  nullable    = true
}

variable "tags" {
  description = "Optional Log Analytics workspace tag override."
  type        = map(string)
  default     = null
  nullable    = true
}