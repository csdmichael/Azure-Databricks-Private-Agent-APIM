variable "config_path" {
  description = "Path to the shared deployment JSON configuration file."
  type        = string
  default     = "../../config/deployment.json"
}

variable "subscription_id" {
  description = "Azure subscription ID override. Defaults to azure.subscriptionId in config_path."
  type        = string
  default     = null
  nullable    = true
}

variable "tenant_id" {
  description = "Microsoft Entra tenant ID override. Defaults to azure.tenantId in config_path."
  type        = string
  default     = null
  nullable    = true
}

variable "resource_group_name" {
  description = "Resource group override. Defaults to azure.resourceGroup in config_path."
  type        = string
  default     = null
  nullable    = true
}

variable "databricks_vnet_name" {
  description = "Existing Databricks VNet-name override. Defaults to network.databricksVnetName in config_path."
  type        = string
  default     = null
  nullable    = true
}

variable "primary_region" {
  description = "Primary Power Platform region override. Defaults to network.powerPlatformPrimaryRegion in config_path."
  type        = string
  default     = null
  nullable    = true
}

variable "secondary_region" {
  description = "Secondary Power Platform region override. Defaults to network.powerPlatformSecondaryRegion in config_path."
  type        = string
  default     = null
  nullable    = true
}

variable "primary_vnet_name" {
  description = "Existing primary Power Platform VNet-name override. Defaults to network.powerPlatformPrimaryVnetName in config_path."
  type        = string
  default     = null
  nullable    = true
}

variable "secondary_vnet_name" {
  description = "Existing secondary Power Platform VNet-name override. Defaults to network.powerPlatformSecondaryVnetName in config_path."
  type        = string
  default     = null
  nullable    = true
}

variable "tags" {
  description = "DNS-link tag override. Defaults to tags in config_path."
  type        = map(string)
  default     = null
  nullable    = true
}