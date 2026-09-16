variable "config_path" {
  description = "Path to the shared deployment JSON configuration file."
  type        = string
  default     = "../../config/deployment.json"
}

variable "subscription_id" {
  description = "Optional Azure subscription ID override. Defaults to azure.subscriptionId in config_path."
  type        = string
  default     = null
  nullable    = true
}

variable "tenant_id" {
  description = "Optional Microsoft Entra tenant ID override. Defaults to azure.tenantId in config_path."
  type        = string
  default     = null
  nullable    = true
}

variable "resource_group_name" {
  description = "Optional resource group override. Defaults to azure.resourceGroup in config_path."
  type        = string
  default     = null
  nullable    = true
}

variable "location" {
  description = "Optional Azure region override. Defaults to network.foundryLocation in config_path."
  type        = string
  default     = null
  nullable    = true
}

variable "foundry_account_name" {
  description = "Optional Foundry account name override. Defaults to foundry.private.accountName in config_path."
  type        = string
  default     = null
  nullable    = true
}

variable "foundry_sku_name" {
  description = "Optional Foundry account SKU override. Defaults to foundry.private.skuName or S0."
  type        = string
  default     = null
  nullable    = true
}

variable "public_network_access" {
  description = "Optional Foundry public network access override. Defaults to foundry.private.publicNetworkAccess in config_path."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition = var.public_network_access == null ? true : contains(
      ["Enabled", "Disabled"],
      var.public_network_access
    )
    error_message = "public_network_access must be Enabled or Disabled."
  }
}

variable "project_name" {
  description = "Optional Foundry project name override. Defaults to foundry.private.projectName in config_path."
  type        = string
  default     = null
  nullable    = true
}

variable "project_display_name" {
  description = "Optional project display name override. Defaults to foundry.private.projectDisplayName or project_name."
  type        = string
  default     = null
  nullable    = true
}

variable "project_description" {
  description = "Optional project description override. Defaults to foundry.private.projectDescription or the Bicep parameter value."
  type        = string
  default     = null
  nullable    = true
}

variable "project_capability_host_name" {
  description = "Optional Agents capability host name override. Defaults to foundry.private.capabilityHostName in config_path."
  type        = string
  default     = null
  nullable    = true
}

variable "model_deployment_name" {
  description = "Optional model deployment name override. Defaults to foundry.private.modelDeploymentName in config_path."
  type        = string
  default     = null
  nullable    = true
}

variable "model_name" {
  description = "Optional publisher model name override. Defaults to foundry.private.modelName in config_path."
  type        = string
  default     = null
  nullable    = true
}

variable "model_version" {
  description = "Optional publisher model version override. Defaults to foundry.private.modelVersion in config_path."
  type        = string
  default     = null
  nullable    = true
}

variable "model_sku_name" {
  description = "Optional model deployment SKU override. Defaults to foundry.private.modelSkuName in config_path."
  type        = string
  default     = null
  nullable    = true
}

variable "model_capacity" {
  description = "Optional model capacity override in thousands of tokens per minute. Defaults to foundry.private.modelCapacity in config_path."
  type        = number
  default     = null
  nullable    = true

  validation {
    condition     = var.model_capacity == null ? true : var.model_capacity >= 1
    error_message = "model_capacity must be at least 1."
  }
}

variable "model_version_upgrade_option" {
  description = "Optional model version upgrade policy. Defaults to foundry.private.modelVersionUpgradeOption or OnceNewDefaultVersionAvailable."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition = var.model_version_upgrade_option == null ? true : contains(
      ["NoAutoUpgrade", "OnceCurrentVersionExpired", "OnceNewDefaultVersionAvailable"],
      var.model_version_upgrade_option
    )
    error_message = "model_version_upgrade_option must be a supported Cognitive Services deployment upgrade policy."
  }
}

variable "vnet_name" {
  description = "Optional existing Foundry/APIM virtual network name override. Defaults to network.apimVnetName in config_path."
  type        = string
  default     = null
  nullable    = true
}

variable "client_vnet_name" {
  description = "Optional existing client virtual network name override. Defaults to network.databricksVnetName in config_path."
  type        = string
  default     = null
  nullable    = true
}

variable "private_endpoint_subnet_name" {
  description = "Optional existing private endpoint subnet name override. Defaults to network.privateEndpointSubnetName in config_path."
  type        = string
  default     = null
  nullable    = true
}

variable "agent_subnet_name" {
  description = "Optional Foundry Agent Service subnet name override. Defaults to network.foundryAgentSubnetName in config_path."
  type        = string
  default     = null
  nullable    = true
}

variable "agent_subnet_prefix" {
  description = "Optional Foundry Agent Service subnet CIDR override. Defaults to network.foundryAgentSubnetCidr in config_path."
  type        = string
  default     = null
  nullable    = true
}

variable "tags" {
  description = "Optional complete resource tag override. Defaults to config tags plus component=foundry-private."
  type        = map(string)
  default     = null
  nullable    = true
}