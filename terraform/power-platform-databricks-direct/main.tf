locals {
  config = jsondecode(file(var.config_path))

  subscription_id = coalesce(var.subscription_id, try(local.config.azure.subscriptionId, null))
  tenant_id       = coalesce(var.tenant_id, try(local.config.azure.tenantId, null))
  resource_group_name = coalesce(
    var.resource_group_name,
    try(local.config.azure.resourceGroup, null)
  )

  databricks_vnet_name         = coalesce(var.databricks_vnet_name, try(local.config.network.databricksVnetName, null))
  primary_region               = coalesce(var.primary_region, try(local.config.network.powerPlatformPrimaryRegion, null))
  secondary_region             = coalesce(var.secondary_region, try(local.config.network.powerPlatformSecondaryRegion, null))
  primary_vnet_name            = coalesce(var.primary_vnet_name, try(local.config.network.powerPlatformPrimaryVnetName, null))
  secondary_vnet_name          = coalesce(var.secondary_vnet_name, try(local.config.network.powerPlatformSecondaryVnetName, null))
  tags                         = coalesce(var.tags, try(tomap(local.config.tags), null), {})
  databricks_private_zone_name = "privatelink.azuredatabricks.net"

  peering_names = {
    primary_to_databricks   = "power-platform-${local.primary_region}-to-databricks"
    databricks_to_primary   = "databricks-to-power-platform-${local.primary_region}"
    secondary_to_databricks = "power-platform-${local.secondary_region}-to-databricks"
    databricks_to_secondary = "databricks-to-power-platform-${local.secondary_region}"
  }
}

data "azurerm_resource_group" "this" {
  name = local.resource_group_name
}

data "azurerm_virtual_network" "databricks" {
  name                = local.databricks_vnet_name
  resource_group_name = data.azurerm_resource_group.this.name
}

data "azurerm_virtual_network" "primary" {
  name                = local.primary_vnet_name
  resource_group_name = data.azurerm_resource_group.this.name
}

data "azurerm_virtual_network" "secondary" {
  name                = local.secondary_vnet_name
  resource_group_name = data.azurerm_resource_group.this.name
}

data "azurerm_private_dns_zone" "databricks" {
  name                = local.databricks_private_zone_name
  resource_group_name = data.azurerm_resource_group.this.name
}

data "azurecaf_name" "peering" {
  for_each = local.peering_names

  name          = each.value
  resource_type = "azurerm_virtual_network_peering"
  passthrough   = true
}

resource "azurerm_virtual_network_peering" "primary_to_databricks" {
  name                         = data.azurecaf_name.peering["primary_to_databricks"].result
  resource_group_name          = data.azurerm_resource_group.this.name
  virtual_network_name         = data.azurerm_virtual_network.primary.name
  remote_virtual_network_id    = data.azurerm_virtual_network.databricks.id
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  allow_virtual_network_access = true
  use_remote_gateways          = false
}

resource "azurerm_virtual_network_peering" "databricks_to_primary" {
  name                         = data.azurecaf_name.peering["databricks_to_primary"].result
  resource_group_name          = data.azurerm_resource_group.this.name
  virtual_network_name         = data.azurerm_virtual_network.databricks.name
  remote_virtual_network_id    = data.azurerm_virtual_network.primary.id
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  allow_virtual_network_access = true
  use_remote_gateways          = false
}

resource "azurerm_virtual_network_peering" "secondary_to_databricks" {
  name                         = data.azurecaf_name.peering["secondary_to_databricks"].result
  resource_group_name          = data.azurerm_resource_group.this.name
  virtual_network_name         = data.azurerm_virtual_network.secondary.name
  remote_virtual_network_id    = data.azurerm_virtual_network.databricks.id
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  allow_virtual_network_access = true
  use_remote_gateways          = false
}

resource "azurerm_virtual_network_peering" "databricks_to_secondary" {
  name                         = data.azurecaf_name.peering["databricks_to_secondary"].result
  resource_group_name          = data.azurerm_resource_group.this.name
  virtual_network_name         = data.azurerm_virtual_network.databricks.name
  remote_virtual_network_id    = data.azurerm_virtual_network.secondary.id
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  allow_virtual_network_access = true
  use_remote_gateways          = false

  depends_on = [azurerm_virtual_network_peering.databricks_to_primary]
}

resource "azurerm_private_dns_zone_virtual_network_link" "databricks_to_primary" {
  name                  = "power-platform-${local.primary_region}-databricks-dns-link"
  resource_group_name   = data.azurerm_resource_group.this.name
  private_dns_zone_name = data.azurerm_private_dns_zone.databricks.name
  virtual_network_id    = data.azurerm_virtual_network.primary.id
  registration_enabled  = false
  tags                  = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "databricks_to_secondary" {
  name                  = "power-platform-${local.secondary_region}-databricks-dns-link"
  resource_group_name   = data.azurerm_resource_group.this.name
  private_dns_zone_name = data.azurerm_private_dns_zone.databricks.name
  virtual_network_id    = data.azurerm_virtual_network.secondary.id
  registration_enabled  = false
  tags                  = local.tags
}