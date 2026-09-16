variable "config_path" {
  description = "Path to the shared deployment configuration JSON file."
  type        = string
  default     = "../../config/deployment.json"
}

variable "storage_account_name" {
  description = "Globally unique storage account name. For parity with an existing Bicep deployment, use the name produced by its uniqueString expression."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.storage_account_name))
    error_message = "storage_account_name must contain 3-24 lowercase letters or digits."
  }
}

variable "showcase_principal_id" {
  description = "Object ID of the service principal granted Log Analytics Reader on the existing workspace."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F-]{36}$", var.showcase_principal_id))
    error_message = "showcase_principal_id must be a UUID."
  }
}

variable "deployment_container_name" {
  description = "Blob container used by the existing broker deployment process."
  type        = string
  default     = "deployments"
}

variable "storage_sku_name" {
  description = "Storage account SKU in Bicep form, such as Standard_LRS."
  type        = string
  default     = "Standard_LRS"

  validation {
    condition     = contains(["Standard_LRS", "Standard_GRS", "Standard_RAGRS", "Standard_ZRS", "Premium_LRS", "Premium_ZRS"], var.storage_sku_name)
    error_message = "storage_sku_name must be a supported StorageV2 SKU."
  }
}

variable "blob_delete_retention_days" {
  description = "Blob soft-delete retention in days."
  type        = number
  default     = 7

  validation {
    condition     = var.blob_delete_retention_days >= 1 && var.blob_delete_retention_days <= 365
    error_message = "blob_delete_retention_days must be between 1 and 365."
  }
}

variable "functions_extension_version" {
  description = "Azure Functions extension version app setting."
  type        = string
  default     = "~4"
}

variable "node_version" {
  description = "Node.js version app setting."
  type        = string
  default     = "~22"
}

variable "net_framework_version" {
  description = ".NET Framework version used by the Functions host."
  type        = string
  default     = "v8.0"
}