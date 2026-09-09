variable "subscription_id" {
  description = "Azure subscription ID to deploy into."
  type        = string
  default     = "86b37969-9445-49cf-b03f-d8866235171c"
}

variable "resource_group_name" {
  description = "Existing resource group that will contain the workspace and network."
  type        = string
  default     = "ai-myaacoub"
}

variable "location" {
  description = "Azure region (US West)."
  type        = string
  default     = "westus"
}

variable "workspace_name" {
  description = "Azure Databricks workspace name."
  type        = string
  default     = "databricks-ws-ai-poc"
}

variable "sku" {
  description = "Databricks pricing tier. Premium is required for Unity Catalog, Genie (AI/BI) and Private Link."
  type        = string
  default     = "premium"
}

variable "vnet_name" {
  description = "Virtual network name for VNet injection."
  type        = string
  default     = "databricks-vnet-ai-poc"
}

variable "vnet_cidr" {
  description = "Address space for the injected VNet."
  type        = string
  default     = "10.179.0.0/16"
}

variable "host_subnet_cidr" {
  description = "Databricks host (public) delegated subnet."
  type        = string
  default     = "10.179.1.0/24"
}

variable "container_subnet_cidr" {
  description = "Databricks container (private) delegated subnet."
  type        = string
  default     = "10.179.2.0/24"
}

variable "private_endpoint_subnet_cidr" {
  description = "Subnet that hosts Private Link private endpoints."
  type        = string
  default     = "10.179.3.0/24"
}

variable "enable_private_link" {
  description = "Create a back-end (databricks_ui_api) Private Link private endpoint + private DNS zone."
  type        = bool
  default     = true
}

variable "public_network_access_enabled" {
  description = "Keep the workspace control-plane URL reachable for management/data-loading. Set false for a fully locked-down front-end (requires a runner inside the VNet)."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Resource tags."
  type        = map(string)
  default = {
    project     = "databricks-private-agent-apim-poc"
    environment = "poc"
    owner       = "Michael Yaacoub"
    costcenter  = "poc-lowest-cost"
    managedby   = "terraform"
  }
}
