variable "subscription_id" {
  description = "Caldova subscription that receives every resource."
  type        = string
  default     = "cf824570-a8ba-497a-a184-0a52f1830aa9"
}

variable "resource_group_name" {
  description = "Existing resource group that receives every resource."
  type        = string
  default     = "m365-myaacoub"
}

variable "location" {
  description = "Azure region for the Databricks workspace and its injected VNet."
  type        = string
  default     = "westus2"
}

variable "workspace_name" {
  description = "Azure Databricks workspace name."
  type        = string
  default     = "caldova-dbx-westus2"
}

variable "sku" {
  description = "Databricks pricing tier. Premium is required for Unity Catalog, Genie and Private Link."
  type        = string
  default     = "premium"
}

variable "vnet_name" {
  description = "Virtual network that the workspace is injected into."
  type        = string
  default     = "caldova-dbx-vnet-westus2"
}

variable "vnet_cidr" {
  description = "Address space for the injected VNet."
  type        = string
  default     = "10.190.0.0/16"
}

variable "host_subnet_cidr" {
  description = "Databricks host (public) delegated subnet."
  type        = string
  default     = "10.190.1.0/24"
}

variable "container_subnet_cidr" {
  description = "Databricks container (private) delegated subnet."
  type        = string
  default     = "10.190.2.0/24"
}

variable "private_endpoint_subnet_cidr" {
  description = "Subnet that hosts the Private Link private endpoints."
  type        = string
  default     = "10.190.3.0/24"
}

# Stage 1 (false) keeps the control-plane URL reachable so the catalog and data
# can be loaded from outside the VNet. Stage 2 (true) is the final private state.
variable "lockdown" {
  description = "Disable public network access and drop the Azure Databricks NSG rules."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Resource tags."
  type        = map(string)
  default = {
    project     = "caldova-databricks-apim-private"
    environment = "caldova"
    owner       = "Michael Yaacoub"
    managedby   = "terraform"
  }
}
