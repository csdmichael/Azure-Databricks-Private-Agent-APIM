variable "config_path" {
  description = "Path to the shared deployment configuration JSON file."
  type        = string
  default     = "../../config/deployment.json"
}

variable "web_principal_id" {
  description = "Managed identity principal ID of the existing showcase web app."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$", var.web_principal_id))
    error_message = "web_principal_id must be a GUID."
  }
}

variable "auth_client_id" {
  description = "Microsoft Entra application client ID used by App Service authentication."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$", var.auth_client_id))
    error_message = "auth_client_id must be a GUID."
  }
}

variable "cosmos_data_contributor_role_definition_guid" {
  description = "Definition GUID for the Cosmos DB Built-in Data Contributor data-plane role."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$", var.cosmos_data_contributor_role_definition_guid))
    error_message = "cosmos_data_contributor_role_definition_guid must be a GUID."
  }
}

variable "authentication_login_endpoint" {
  description = "Microsoft Entra authentication authority endpoint, including the trailing slash."
  type        = string
  default     = "https://login.microsoftonline.com/"

  validation {
    condition     = can(regex("^https://[^/]+(?:/[^/]*)*/$", var.authentication_login_endpoint))
    error_message = "authentication_login_endpoint must be an HTTPS URL ending with a slash."
  }
}