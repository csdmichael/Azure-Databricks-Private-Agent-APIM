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

variable "tenant_id" {
  description = "Microsoft Entra tenant ID override. Defaults to azure.tenantId in config_path."
  type        = string
  default     = null
  nullable    = true
}

variable "api_client_id" {
  description = "Delegated API application client-ID override. Defaults to obo.apiClientId in config_path."
  type        = string
  default     = null
  nullable    = true
}

variable "connector_client_id" {
  description = "Allowed connector application client-ID override. Defaults to obo.connectorClientId in config_path."
  type        = string
  default     = null
  nullable    = true
}

variable "allowed_user_id" {
  description = "Authorized user object-ID override. Defaults to obo.allowedUserId in config_path."
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

variable "genie_space_id" {
  description = "Databricks Genie space ID. This value is not stored in config_path and must be supplied."
  type        = string

  validation {
    condition     = length(trimspace(var.genie_space_id)) > 0
    error_message = "genie_space_id must not be empty."
  }
}

variable "broker_url" {
  description = "Token-broker endpoint override. Defaults to obo.brokerUrl when present, otherwise derives from obo.functionName."
  type        = string
  default     = null
  nullable    = true
}

variable "insights_name" {
  description = "Existing Application Insights component-name override. Defaults to observability.applicationInsightsName in config_path."
  type        = string
  default     = null
  nullable    = true
}

variable "obo_scope" {
  description = "Delegated OAuth scope override. Defaults to obo.scope in config_path."
  type        = string
  default     = null
  nullable    = true
}

variable "obo_rate_limit_calls" {
  description = "Per-user OBO rate-limit override. Defaults to apim.rateLimits.oboCalls in config_path."
  type        = number
  default     = null
  nullable    = true

  validation {
    condition     = var.obo_rate_limit_calls == null ? true : var.obo_rate_limit_calls >= 1 && floor(var.obo_rate_limit_calls) == var.obo_rate_limit_calls
    error_message = "obo_rate_limit_calls must be a positive integer."
  }
}

variable "obo_rate_limit_renewal_period_seconds" {
  description = "Per-user rate-limit renewal-period override. Defaults to apim.rateLimits.renewalPeriodSeconds in config_path."
  type        = number
  default     = null
  nullable    = true

  validation {
    condition     = var.obo_rate_limit_renewal_period_seconds == null ? true : var.obo_rate_limit_renewal_period_seconds >= 1 && floor(var.obo_rate_limit_renewal_period_seconds) == var.obo_rate_limit_renewal_period_seconds
    error_message = "obo_rate_limit_renewal_period_seconds must be a positive integer."
  }
}

variable "obo_broker_timeout_seconds" {
  description = "Token-broker timeout override. Defaults to apim.timeouts.oboBrokerSeconds in config_path."
  type        = number
  default     = null
  nullable    = true

  validation {
    condition     = var.obo_broker_timeout_seconds == null ? true : var.obo_broker_timeout_seconds >= 1 && floor(var.obo_broker_timeout_seconds) == var.obo_broker_timeout_seconds
    error_message = "obo_broker_timeout_seconds must be a positive integer."
  }
}

variable "api_display_name" {
  description = "Delegated Genie API display-name override. Defaults to obo.apiDisplayName in config_path."
  type        = string
  default     = null
  nullable    = true
}

variable "api_description" {
  description = "Delegated Genie API description. This value is not stored in config_path and must be supplied."
  type        = string
}

variable "diagnostic_sampling_percentage" {
  description = "Application Insights sampling percentage override. Defaults to observability.samplingPercentage in config_path."
  type        = number
  default     = null
  nullable    = true

  validation {
    condition     = var.diagnostic_sampling_percentage == null ? true : var.diagnostic_sampling_percentage >= 0 && var.diagnostic_sampling_percentage <= 100 && floor(var.diagnostic_sampling_percentage) == var.diagnostic_sampling_percentage
    error_message = "diagnostic_sampling_percentage must be an integer from 0 through 100."
  }
}