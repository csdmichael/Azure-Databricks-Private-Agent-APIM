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

variable "apim_service_name" {
  description = "Existing API Management service-name override. Defaults to apim.serviceName in config_path."
  type        = string
  default     = null
  nullable    = true
}

variable "apim_vnet_name" {
  description = "Existing API Management VNet-name override. Defaults to network.apimVnetName in config_path."
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
  description = "Primary Power Platform VNet-name override. Defaults to network.powerPlatformPrimaryVnetName in config_path."
  type        = string
  default     = null
  nullable    = true
}

variable "secondary_vnet_name" {
  description = "Secondary Power Platform VNet-name override. Defaults to network.powerPlatformSecondaryVnetName in config_path."
  type        = string
  default     = null
  nullable    = true
}

variable "power_platform_subnet_name" {
  description = "Power Platform subnet-name override. Defaults to network.powerPlatformSubnetName in config_path."
  type        = string
  default     = null
  nullable    = true
}

variable "primary_vnet_cidr" {
  description = "Primary Power Platform VNet CIDR override. Defaults to network.powerPlatformPrimaryVnetCidr in config_path."
  type        = string
  default     = null
  nullable    = true
}

variable "primary_subnet_cidr" {
  description = "Primary delegated-subnet CIDR override. Defaults to network.powerPlatformPrimarySubnetCidr in config_path."
  type        = string
  default     = null
  nullable    = true
}

variable "secondary_vnet_cidr" {
  description = "Secondary Power Platform VNet CIDR override. Defaults to network.powerPlatformSecondaryVnetCidr in config_path."
  type        = string
  default     = null
  nullable    = true
}

variable "secondary_subnet_cidr" {
  description = "Secondary delegated-subnet CIDR override. Defaults to network.powerPlatformSecondarySubnetCidr in config_path."
  type        = string
  default     = null
  nullable    = true
}

variable "policy_location" {
  description = "Power Platform policy geo override. By default it is derived from the configured primary region."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition = var.policy_location == null || contains([
      "unitedstates",
      "canada",
      "europe",
      "unitedkingdom",
      "asia",
      "australia",
      "japan",
      "india",
      "southamerica",
      "france",
      "germany",
      "switzerland",
      "unitedarabemirates",
      "korea",
      "norway",
      "singapore",
      "southafrica",
      "sweden",
    ], var.policy_location)
    error_message = "policy_location must be a supported Power Platform policy geography."
  }
}

variable "enterprise_policy_name" {
  description = "Network-injection enterprise-policy name override. Defaults to powerPlatform.enterprisePolicyName in config_path."
  type        = string
  default     = null
  nullable    = true
}

variable "tags" {
  description = "Resource tag override. Defaults to tags in config_path."
  type        = map(string)
  default     = null
  nullable    = true
}