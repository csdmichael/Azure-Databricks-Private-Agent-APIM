locals {
  deployment_config = jsondecode(file(var.config_path))

  subscription_id              = local.deployment_config.azure.subscriptionId
  tenant_id                    = local.deployment_config.azure.tenantId
  resource_group_name          = local.deployment_config.azure.resourceGroup
  location                     = local.deployment_config.network.databricksLocation
  vnet_name                    = local.deployment_config.network.databricksVnetName
  private_endpoint_subnet_name = local.deployment_config.network.privateEndpointSubnetName
  integration_subnet_name      = local.deployment_config.network.genieOboIntegrationSubnetName
  integration_subnet_cidr      = local.deployment_config.network.showcaseIntegrationSubnetCidr
  web_app_name                 = local.deployment_config.showcase.appName
  cosmos_name_prefix           = local.deployment_config.showcase.cosmosNamePrefix
  cosmos_database_name         = local.deployment_config.showcase.cosmosDatabase
  cosmos_container_name        = local.deployment_config.showcase.cosmosContainer
  analytics_ttl_seconds        = local.deployment_config.showcase.analyticsTtlSeconds
  cosmos_consistency_level     = local.deployment_config.showcase.cosmosConsistencyLevel
  cosmos_zone_redundant        = local.deployment_config.showcase.cosmosZoneRedundant
  backup_interval_minutes      = local.deployment_config.showcase.backupIntervalInMinutes
  backup_retention_hours       = local.deployment_config.showcase.backupRetentionInHours
  backup_storage_redundancy    = local.deployment_config.showcase.backupStorageRedundancy

  cosmos_account_name = "${local.cosmos_name_prefix}-${provider::azapi::unique_string([data.azurerm_resource_group.current.id])}"
  cosmos_role_assignment_name = uuidv5(
    "11fb06fb-712d-4ddd-98c7-e71bbd588830",
    join("-", [azurerm_cosmosdb_account.analytics.id, var.web_principal_id, "showcase-data"])
  )
}

provider "azurerm" {
  subscription_id = local.subscription_id
  tenant_id       = local.tenant_id

  features {}
}

provider "azapi" {
  subscription_id = local.subscription_id
  tenant_id       = local.tenant_id
}

data "azurerm_resource_group" "current" {
  name = local.resource_group_name
}

data "azurerm_virtual_network" "existing" {
  name                = local.vnet_name
  resource_group_name = data.azurerm_resource_group.current.name
}

data "azurerm_subnet" "private_endpoint" {
  name                 = local.private_endpoint_subnet_name
  resource_group_name  = data.azurerm_resource_group.current.name
  virtual_network_name = data.azurerm_virtual_network.existing.name
}

data "azapi_resource" "web_app" {
  type      = "Microsoft.Web/sites@2023-12-01"
  name      = local.web_app_name
  parent_id = data.azurerm_resource_group.current.id
}

resource "azurerm_subnet" "integration" {
  name                 = local.integration_subnet_name
  resource_group_name  = data.azurerm_resource_group.current.name
  virtual_network_name = data.azurerm_virtual_network.existing.name
  address_prefixes     = [local.integration_subnet_cidr]

  delegation {
    name = "web"

    service_delegation {
      name = "Microsoft.Web/serverFarms"
    }
  }
}

resource "azurerm_cosmosdb_account" "analytics" {
  name                = local.cosmos_account_name
  location            = local.location
  resource_group_name = data.azurerm_resource_group.current.name
  offer_type          = "Standard"
  kind                = "GlobalDocumentDB"

  public_network_access_enabled = false
  local_authentication_enabled  = false
  minimal_tls_version           = "Tls12"

  capabilities {
    name = "EnableServerless"
  }

  geo_location {
    location          = local.location
    failover_priority = 0
    zone_redundant    = local.cosmos_zone_redundant
  }

  consistency_policy {
    consistency_level = local.cosmos_consistency_level
  }

  backup {
    type                = "Periodic"
    interval_in_minutes = local.backup_interval_minutes
    retention_in_hours  = local.backup_retention_hours
    storage_redundancy  = local.backup_storage_redundancy
  }

  lifecycle {
    precondition {
      condition     = length(local.cosmos_name_prefix) >= 3 && length(local.cosmos_name_prefix) <= 30
      error_message = "showcase.cosmosNamePrefix must contain between 3 and 30 characters."
    }

    precondition {
      condition     = local.backup_interval_minutes >= 1
      error_message = "showcase.backupIntervalInMinutes must be at least 1."
    }

    precondition {
      condition     = local.backup_retention_hours >= 1
      error_message = "showcase.backupRetentionInHours must be at least 1."
    }
  }
}

resource "azurerm_cosmosdb_sql_database" "analytics" {
  name                = local.cosmos_database_name
  resource_group_name = data.azurerm_resource_group.current.name
  account_name        = azurerm_cosmosdb_account.analytics.name
}

resource "azurerm_cosmosdb_sql_container" "visits" {
  name                = local.cosmos_container_name
  resource_group_name = data.azurerm_resource_group.current.name
  account_name        = azurerm_cosmosdb_account.analytics.name
  database_name       = azurerm_cosmosdb_sql_database.analytics.name

  partition_key_paths   = ["/day"]
  partition_key_kind    = "Hash"
  partition_key_version = 2
  default_ttl           = local.analytics_ttl_seconds

  indexing_policy {
    indexing_mode = "consistent"

    included_path {
      path = "/day/?"
    }

    excluded_path {
      path = "/*"
    }
  }

  lifecycle {
    precondition {
      condition     = local.analytics_ttl_seconds >= -1
      error_message = "showcase.analyticsTtlSeconds must be at least -1."
    }
  }
}

resource "azurerm_cosmosdb_sql_role_assignment" "showcase_data" {
  name                = local.cosmos_role_assignment_name
  resource_group_name = data.azurerm_resource_group.current.name
  account_name        = azurerm_cosmosdb_account.analytics.name
  principal_id        = var.web_principal_id
  role_definition_id  = "${azurerm_cosmosdb_account.analytics.id}/sqlRoleDefinitions/${var.cosmos_data_contributor_role_definition_guid}"
  scope               = "${azurerm_cosmosdb_account.analytics.id}/dbs/${azurerm_cosmosdb_sql_database.analytics.name}"
}

resource "azurerm_private_dns_zone" "cosmos" {
  name                = "privatelink.documents.azure.com"
  resource_group_name = data.azurerm_resource_group.current.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "cosmos" {
  name                  = local.cosmos_database_name
  resource_group_name   = data.azurerm_resource_group.current.name
  private_dns_zone_name = azurerm_private_dns_zone.cosmos.name
  virtual_network_id    = data.azurerm_virtual_network.existing.id
  registration_enabled  = false
}

resource "azurerm_private_endpoint" "cosmos" {
  name                = "${local.cosmos_database_name}-cosmos-pe"
  location            = local.location
  resource_group_name = data.azurerm_resource_group.current.name
  subnet_id           = data.azurerm_subnet.private_endpoint.id

  private_service_connection {
    name                           = "cosmos"
    is_manual_connection           = false
    private_connection_resource_id = azurerm_cosmosdb_account.analytics.id
    subresource_names              = ["Sql"]
  }
}

resource "azapi_resource" "cosmos_private_dns_zone_group" {
  type      = "Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01"
  name      = "default"
  parent_id = azurerm_private_endpoint.cosmos.id

  body = {
    properties = {
      privateDnsZoneConfigs = [
        {
          name = "cosmos"
          properties = {
            privateDnsZoneId = azurerm_private_dns_zone.cosmos.id
          }
        }
      ]
    }
  }
}

resource "azapi_resource" "auth_settings_v2" {
  type      = "Microsoft.Web/sites/config@2023-12-01"
  name      = "authsettingsV2"
  parent_id = data.azapi_resource.web_app.id

  body = {
    properties = {
      platform = {
        enabled        = true
        runtimeVersion = "~1"
      }
      globalValidation = {
        requireAuthentication       = false
        unauthenticatedClientAction = "AllowAnonymous"
      }
      identityProviders = {
        azureActiveDirectory = {
          enabled = true
          registration = {
            clientId                = var.auth_client_id
            clientSecretSettingName = "SHOWCASE_AUTH_CLIENT_SECRET"
            openIdIssuer            = "${var.authentication_login_endpoint}${local.tenant_id}/v2.0"
          }
          validation = {
            allowedAudiences = [
              var.auth_client_id,
              "api://${var.auth_client_id}"
            ]
          }
        }
      }
      login = {
        tokenStore = {
          enabled = true
        }
      }
      httpSettings = {
        requireHttps = true
      }
    }
  }
}