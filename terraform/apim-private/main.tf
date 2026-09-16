locals {
  config = jsondecode(file(var.config_path))

  subscription_id = coalesce(var.subscription_id, try(local.config.azure.subscriptionId, null))
  tenant_id       = coalesce(var.tenant_id, try(local.config.azure.tenantId, null))
  resource_group_name = coalesce(
    var.resource_group_name,
    try(local.config.azure.resourceGroup, null)
  )
  location = coalesce(var.location, try(local.config.network.apimLocation, null))

  apim_service_name    = coalesce(var.apim_service_name, try(local.config.apim.serviceName, null))
  databricks_vnet_name = coalesce(var.databricks_vnet_name, try(local.config.network.databricksVnetName, null))
  databricks_location  = try(local.config.network.databricksLocation, null)
  apim_vnet_name       = coalesce(var.apim_vnet_name, try(local.config.network.apimVnetName, null), "${local.apim_service_name}-vnet")
  apim_vnet_cidr       = coalesce(var.apim_vnet_cidr, try(local.config.network.apimVnetCidr, null))
  integration_subnet_name = coalesce(
    var.integration_subnet_name,
    try(local.config.network.apimIntegrationSubnetName, null)
  )
  integration_subnet_cidr = coalesce(
    var.integration_subnet_cidr,
    try(local.config.network.apimIntegrationSubnetCidr, null)
  )
  private_endpoint_subnet_name = coalesce(
    var.private_endpoint_subnet_name,
    try(local.config.network.privateEndpointSubnetName, null)
  )
  private_endpoint_subnet_cidr = coalesce(
    var.private_endpoint_subnet_cidr,
    try(local.config.network.privateEndpointSubnetCidr, null)
  )
  apim_to_databricks_peering_name = coalesce(
    var.apim_to_databricks_peering_name,
    "apim-to-databricks-${local.databricks_location}"
  )
  databricks_to_apim_peering_name = coalesce(
    var.databricks_to_apim_peering_name,
    "databricks-${local.databricks_location}-to-apim"
  )
  tags = coalesce(var.tags, try(tomap(local.config.tags), null), {})

  apim_private_dns_zone_name       = "privatelink.azure-api.net"
  databricks_private_dns_zone_name = "privatelink.azuredatabricks.net"
}

data "azurerm_resource_group" "this" {
  name = local.resource_group_name
}

data "azurerm_virtual_network" "databricks" {
  name                = local.databricks_vnet_name
  resource_group_name = data.azurerm_resource_group.this.name
}

data "azurerm_private_dns_zone" "databricks" {
  name                = local.databricks_private_dns_zone_name
  resource_group_name = data.azurerm_resource_group.this.name
}

resource "azurerm_private_dns_zone" "apim" {
  name                = local.apim_private_dns_zone_name
  resource_group_name = data.azurerm_resource_group.this.name
  tags                = local.tags
}

resource "azurerm_network_security_group" "integration" {
  name                = "${local.apim_service_name}-integration-nsg"
  location            = local.location
  resource_group_name = data.azurerm_resource_group.this.name
  tags                = local.tags
}

resource "azurerm_network_security_group" "private_endpoints" {
  name                = "${local.apim_service_name}-private-endpoints-nsg"
  location            = local.location
  resource_group_name = data.azurerm_resource_group.this.name
  tags                = local.tags
}

resource "azurerm_virtual_network" "apim" {
  name                = local.apim_vnet_name
  location            = local.location
  resource_group_name = data.azurerm_resource_group.this.name
  address_space       = [local.apim_vnet_cidr]
  tags                = local.tags
}

resource "azurerm_subnet" "integration" {
  name                 = local.integration_subnet_name
  resource_group_name  = data.azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.apim.name
  address_prefixes     = [local.integration_subnet_cidr]

  delegation {
    name = "apim-standard-v2-integration"

    service_delegation {
      name = "Microsoft.Web/serverFarms"
    }
  }
}

resource "azurerm_subnet_network_security_group_association" "integration" {
  subnet_id                 = azurerm_subnet.integration.id
  network_security_group_id = azurerm_network_security_group.integration.id
}

resource "azurerm_subnet" "private_endpoints" {
  name                              = local.private_endpoint_subnet_name
  resource_group_name               = data.azurerm_resource_group.this.name
  virtual_network_name              = azurerm_virtual_network.apim.name
  address_prefixes                  = [local.private_endpoint_subnet_cidr]
  private_endpoint_network_policies = "Disabled"

  depends_on = [azurerm_subnet_network_security_group_association.integration]
}

resource "azurerm_subnet_network_security_group_association" "private_endpoints" {
  subnet_id                 = azurerm_subnet.private_endpoints.id
  network_security_group_id = azurerm_network_security_group.private_endpoints.id
}

resource "azurerm_virtual_network_peering" "apim_to_databricks" {
  name                         = local.apim_to_databricks_peering_name
  resource_group_name          = data.azurerm_resource_group.this.name
  virtual_network_name         = azurerm_virtual_network.apim.name
  remote_virtual_network_id    = data.azurerm_virtual_network.databricks.id
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  allow_virtual_network_access = true
  use_remote_gateways          = false

  depends_on = [azurerm_subnet_network_security_group_association.private_endpoints]
}

resource "azurerm_virtual_network_peering" "databricks_to_apim" {
  name                         = local.databricks_to_apim_peering_name
  resource_group_name          = data.azurerm_resource_group.this.name
  virtual_network_name         = data.azurerm_virtual_network.databricks.name
  remote_virtual_network_id    = azurerm_virtual_network.apim.id
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  allow_virtual_network_access = true
  use_remote_gateways          = false

  depends_on = [azurerm_subnet_network_security_group_association.private_endpoints]
}

resource "azurerm_private_dns_zone_virtual_network_link" "databricks_to_apim" {
  name                  = "${local.apim_service_name}-databricks-dns-link"
  resource_group_name   = data.azurerm_resource_group.this.name
  private_dns_zone_name = data.azurerm_private_dns_zone.databricks.name
  virtual_network_id    = azurerm_virtual_network.apim.id
  registration_enabled  = false
  tags                  = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "apim_to_apim" {
  name                  = "${local.apim_service_name}-gateway-dns-link"
  resource_group_name   = data.azurerm_resource_group.this.name
  private_dns_zone_name = azurerm_private_dns_zone.apim.name
  virtual_network_id    = azurerm_virtual_network.apim.id
  registration_enabled  = false
  tags                  = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "apim_to_databricks" {
  name                  = "${local.databricks_vnet_name}-apim-dns-link"
  resource_group_name   = data.azurerm_resource_group.this.name
  private_dns_zone_name = azurerm_private_dns_zone.apim.name
  virtual_network_id    = data.azurerm_virtual_network.databricks.id
  registration_enabled  = false
  tags                  = local.tags
}

resource "azurerm_api_management" "this" {
  name                          = local.apim_service_name
  location                      = local.location
  resource_group_name           = data.azurerm_resource_group.this.name
  publisher_name                = var.publisher_name
  publisher_email               = var.publisher_email
  sku_name                      = "${var.apim_sku_name}_${var.apim_capacity}"
  public_network_access_enabled = var.public_network_access == "Enabled"
  virtual_network_type          = "External"
  tags                          = local.tags

  identity {
    type = "SystemAssigned"
  }

  virtual_network_configuration {
    subnet_id = azurerm_subnet.integration.id
  }

  depends_on = [azurerm_subnet_network_security_group_association.integration]
}

resource "azurerm_private_endpoint" "apim_gateway" {
  name                = "${local.apim_service_name}-gateway-pe"
  location            = local.location
  resource_group_name = data.azurerm_resource_group.this.name
  subnet_id           = azurerm_subnet.private_endpoints.id
  tags                = local.tags

  private_service_connection {
    name                           = "${local.apim_service_name}-gateway-connection"
    private_connection_resource_id = azurerm_api_management.this.id
    subresource_names              = ["Gateway"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.apim.id]
  }

  depends_on = [azurerm_subnet_network_security_group_association.private_endpoints]
}