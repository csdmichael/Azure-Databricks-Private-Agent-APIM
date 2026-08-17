terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    databricks = {
      source  = "databricks/databricks"
      version = "~> 1.55"
    }
  }

  # For production, enable a remote state backend (recommended). Example:
  # backend "azurerm" {
  #   resource_group_name  = "ai-myaacoub"
  #   storage_account_name = "stdbxtfstatexxxxx"
  #   container_name       = "tfstate"
  #   key                  = "databricks-ws-ai-poc.tfstate"
  # }
}

provider "azurerm" {
  subscription_id = var.subscription_id
  features {}
}

# Workspace-scoped provider. Authenticates with the same Azure CLI / OIDC
# identity used by azurerm. Only used for optional Databricks-native resources.
provider "databricks" {
  host                        = azurerm_databricks_workspace.this.workspace_url
  azure_workspace_resource_id = azurerm_databricks_workspace.this.id
}
