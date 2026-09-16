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

variable "location" {
  description = "Optional Azure region override for API Management resources."
  type        = string
  default     = null
  nullable    = true
}

variable "apim_service_name" {
  description = "Optional API Management service name override."
  type        = string
  default     = null
  nullable    = true
}

variable "publisher_name" {
  description = "API Management publisher display name."
  type        = string
}

variable "publisher_email" {
  description = "API Management publisher email address."
  type        = string
}

variable "databricks_vnet_name" {
  description = "Optional existing Databricks virtual network name override."
  type        = string
  default     = null
  nullable    = true
}

variable "apim_to_databricks_peering_name" {
  description = "Optional APIM-to-Databricks peering name override."
  type        = string
  default     = null
  nullable    = true
}

variable "databricks_to_apim_peering_name" {
  description = "Optional Databricks-to-APIM peering name override."
  type        = string
  default     = null
  nullable    = true
}

variable "apim_vnet_name" {
  description = "Optional API Management virtual network name override."
  type        = string
  default     = null
  nullable    = true
}

variable "apim_vnet_cidr" {
  description = "Optional API Management virtual network address space override."
  type        = string
  default     = null
  nullable    = true
}

variable "integration_subnet_name" {
  description = "Optional outbound integration subnet name override."
  type        = string
  default     = null
  nullable    = true
}

variable "integration_subnet_cidr" {
  description = "Optional outbound integration subnet CIDR override."
  type        = string
  default     = null
  nullable    = true
}

variable "private_endpoint_subnet_name" {
  description = "Optional private endpoint subnet name override."
  type        = string
  default     = null
  nullable    = true
}

variable "private_endpoint_subnet_cidr" {
  description = "Optional private endpoint subnet CIDR override."
  type        = string
  default     = null
  nullable    = true
}

variable "apim_sku_name" {
  description = "API Management SKU name without the capacity suffix."
  type        = string
}

variable "apim_capacity" {
  description = "API Management service capacity."
  type        = number

  validation {
    condition     = var.apim_capacity >= 1
    error_message = "apim_capacity must be at least 1."
  }
}

variable "public_network_access" {
  description = "Public ingress state. Use Enabled for stage 1 and Disabled for stage 2."
  type        = string

  validation {
    condition     = contains(["Enabled", "Disabled"], var.public_network_access)
    error_message = "public_network_access must be Enabled or Disabled."
  }
}

variable "tags" {
  description = "Optional resource tag override."
  type        = map(string)
  default     = null
  nullable    = true
}