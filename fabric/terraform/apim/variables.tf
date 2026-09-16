variable "config_path" {
  description = "Path to the Fabric deployment configuration file."
  type        = string
  default     = "../../config/deployment.json"
}

variable "resource_api_client_id" {
  description = "Generated client ID of the Fabric resource API application registration."
  type        = string

  validation {
    condition     = can(regex("^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[1-5][0-9A-Fa-f]{3}-[89ABab][0-9A-Fa-f]{3}-[0-9A-Fa-f]{12}$", trimspace(var.resource_api_client_id)))
    error_message = "resource_api_client_id must be a nonempty GUID."
  }
}

variable "connector_client_ids" {
  description = "Generated connector application client IDs allowed to call the APIs."
  type        = list(string)

  validation {
    condition = length(var.connector_client_ids) > 0 && alltrue([
      for value in var.connector_client_ids : can(regex("^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[1-5][0-9A-Fa-f]{3}-[89ABab][0-9A-Fa-f]{3}-[0-9A-Fa-f]{12}$", trimspace(value)))
    ])
    error_message = "connector_client_ids must contain at least one nonempty GUID."
  }
}

variable "allowed_fabric_guest_object_ids" {
  description = "Fabric-tenant guest object IDs allowed to call the APIs."
  type        = list(string)

  validation {
    condition = length(var.allowed_fabric_guest_object_ids) > 0 && alltrue([
      for value in var.allowed_fabric_guest_object_ids : can(regex("^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[1-5][0-9A-Fa-f]{3}-[89ABab][0-9A-Fa-f]{3}-[0-9A-Fa-f]{12}$", trimspace(value)))
    ])
    error_message = "allowed_fabric_guest_object_ids must contain at least one nonempty GUID."
  }
}

variable "broker_audience" {
  description = "Generated application client ID used as the private broker audience."
  type        = string

  validation {
    condition     = can(regex("^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[1-5][0-9A-Fa-f]{3}-[89ABab][0-9A-Fa-f]{3}-[0-9A-Fa-f]{12}$", trimspace(var.broker_audience)))
    error_message = "broker_audience must be a nonempty GUID."
  }
}

variable "broker_private_url" {
  description = "Fixed private broker origin, without an /api path."
  type        = string

  validation {
    condition     = can(regex("^https://[A-Za-z0-9-]+\\.azurewebsites\\.net/?$", trimspace(var.broker_private_url)))
    error_message = "broker_private_url must be a nonempty HTTPS azurewebsites.net origin."
  }
}

variable "broker_private_endpoint_ip" {
  description = "IPv4 address assigned to the broker private endpoint."
  type        = string

  validation {
    condition     = can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}$", trimspace(var.broker_private_endpoint_ip))) && can(cidrhost("${trimspace(var.broker_private_endpoint_ip)}/32", 0))
    error_message = "broker_private_endpoint_ip must be a nonempty IPv4 address."
  }
}

variable "application_insights_name" {
  description = "Optional existing Application Insights component name. Diagnostics are omitted when null or empty."
  type        = string
  default     = null
  nullable    = true
}

variable "application_insights_resource_group_name" {
  description = "Optional resource group of the existing Application Insights component. Defaults to config.apim.resourceGroup."
  type        = string
  default     = null
  nullable    = true
}

variable "create_private_dns_zone" {
  description = "Create the Caldova-side privatelink.azurewebsites.net zone. Set false to reuse an existing zone."
  type        = bool
  default     = true
}

variable "private_dns_zone_resource_group_name" {
  description = "Optional resource group containing the private DNS zone. Defaults to config.apim.resourceGroup."
  type        = string
  default     = null
  nullable    = true
}