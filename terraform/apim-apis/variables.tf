variable "config_path" {
  description = "Path to the deployment JSON configuration file."
  type        = string
  default     = "../../config/deployment.json"
}

variable "subscription_id" {
  description = "Azure subscription ID override. Defaults to azure.subscriptionId in config_path."
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
  description = "Existing API Management service name override. Defaults to apim.serviceName in config_path."
  type        = string
  default     = null
  nullable    = true
}

variable "apim_gateway_url" {
  description = "API Management gateway URL override. Defaults to apim.gatewayUrl in config_path."
  type        = string
  default     = null
  nullable    = true
}

variable "databricks_api_name" {
  description = "Databricks SQL API resource-name override. Defaults to apim.sourceApiId in config_path."
  type        = string
  default     = null
  nullable    = true
}

variable "product_name" {
  description = "APIM product resource-name override. Defaults to apim.productId in config_path."
  type        = string
  default     = null
  nullable    = true
}

variable "subscription_name" {
  description = "APIM subscription resource-name override. Defaults to apim.subscriptionName in config_path."
  type        = string
  default     = null
  nullable    = true
}

variable "databricks_workspace_url" {
  description = "Databricks workspace URL override. Defaults to databricks.workspaceUrl in config_path."
  type        = string
  default     = null
  nullable    = true
}

variable "databricks_warehouse_id" {
  description = "Databricks SQL warehouse ID override. Defaults to databricks.warehouseId in config_path."
  type        = string
  default     = null
  nullable    = true
}

variable "databricks_catalog" {
  description = "Unity Catalog catalog override. Defaults to databricks.catalog in config_path."
  type        = string
  default     = null
  nullable    = true
}

variable "databricks_schema" {
  description = "Unity Catalog schema override. Defaults to databricks.schema in config_path."
  type        = string
  default     = null
  nullable    = true
}

variable "genie_space_id" {
  description = "Databricks Genie space ID. This value is not stored in config_path and must be supplied."
  type        = string

  validation {
    condition     = length(trimspace(var.genie_space_id)) > 0
    error_message = "genie_space_id must not be empty."
  }
}

variable "databricks_rate_limit_calls" {
  description = "Databricks SQL API rate-limit override. Defaults to apim.rateLimits.databricksCalls in config_path."
  type        = number
  default     = null
  nullable    = true

  validation {
    condition     = var.databricks_rate_limit_calls == null ? true : var.databricks_rate_limit_calls >= 1 && floor(var.databricks_rate_limit_calls) == var.databricks_rate_limit_calls
    error_message = "databricks_rate_limit_calls must be a positive integer."
  }
}

variable "genie_rate_limit_calls" {
  description = "Databricks Genie API rate-limit override. Defaults to apim.rateLimits.genieCalls in config_path."
  type        = number
  default     = null
  nullable    = true

  validation {
    condition     = var.genie_rate_limit_calls == null ? true : var.genie_rate_limit_calls >= 1 && floor(var.genie_rate_limit_calls) == var.genie_rate_limit_calls
    error_message = "genie_rate_limit_calls must be a positive integer."
  }
}

variable "rate_limit_renewal_period_seconds" {
  description = "Rate-limit renewal-period override. Defaults to apim.rateLimits.renewalPeriodSeconds in config_path."
  type        = number
  default     = null
  nullable    = true

  validation {
    condition     = var.rate_limit_renewal_period_seconds == null ? true : var.rate_limit_renewal_period_seconds >= 1 && floor(var.rate_limit_renewal_period_seconds) == var.rate_limit_renewal_period_seconds
    error_message = "rate_limit_renewal_period_seconds must be a positive integer."
  }
}

variable "sql_wait_timeout" {
  description = "Databricks SQL wait-timeout override. Defaults to apim.timeouts.sqlWait in config_path."
  type        = string
  default     = null
  nullable    = true
}

variable "databricks_api_display_name" {
  description = "Databricks SQL API display-name override. Defaults to apim.databricksApiDisplayName in config_path."
  type        = string
  default     = null
  nullable    = true
}

variable "databricks_api_description" {
  description = "Databricks SQL API description override. Defaults to apim.databricksApiDescription in config_path."
  type        = string
  default     = null
  nullable    = true
}

variable "genie_api_display_name" {
  description = "Databricks Genie API display-name override. Defaults to apim.genieApiDisplayName in config_path."
  type        = string
  default     = null
  nullable    = true
}

variable "genie_api_description" {
  description = "Databricks Genie API description override. Defaults to apim.genieApiDescription in config_path."
  type        = string
  default     = null
  nullable    = true
}

variable "product_display_name" {
  description = "APIM product display-name override. Defaults to apim.productDisplayName in config_path."
  type        = string
  default     = null
  nullable    = true
}

variable "product_description" {
  description = "APIM product description override. Defaults to apim.productDescription in config_path."
  type        = string
  default     = null
  nullable    = true
}

variable "subscription_display_name" {
  description = "APIM subscription display-name override. Defaults to apim.subscriptionDisplayName in config_path."
  type        = string
  default     = null
  nullable    = true
}