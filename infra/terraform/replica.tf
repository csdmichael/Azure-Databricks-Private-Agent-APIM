locals {
  replica_tags = merge(var.tags, {
    replica_of = var.workspace_name
  })
}

# The replica uses a separate regional VNet because injected Databricks
# subnets must be in the same region as the workspace.
resource "azurerm_virtual_network" "replica" {
  name                = var.replica_vnet_name
  location            = var.replica_location
  resource_group_name = data.azurerm_resource_group.this.name
  address_space       = [var.replica_vnet_cidr]
  tags                = local.replica_tags
}

resource "azurerm_network_security_group" "replica_databricks" {
  name                = "${var.replica_workspace_name}-nsg"
  location            = var.replica_location
  resource_group_name = data.azurerm_resource_group.this.name
  tags                = local.replica_tags
}

resource "azurerm_network_security_group" "replica_private_endpoints" {
  name                = "${var.replica_vnet_name}-private-endpoints-nsg-${var.replica_location}"
  location            = var.replica_location
  resource_group_name = data.azurerm_resource_group.this.name
  tags                = local.replica_tags
}

resource "azurerm_subnet" "replica_host" {
  name                            = "databricks-host"
  resource_group_name             = data.azurerm_resource_group.this.name
  virtual_network_name            = azurerm_virtual_network.replica.name
  address_prefixes                = [var.replica_host_subnet_cidr]
  default_outbound_access_enabled = false

  delegation {
    name = "databricks-host-delegation"
    service_delegation {
      name = "Microsoft.Databricks/workspaces"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action",
        "Microsoft.Network/virtualNetworks/subnets/prepareNetworkPolicies/action",
        "Microsoft.Network/virtualNetworks/subnets/unprepareNetworkPolicies/action",
      ]
    }
  }
}

resource "azurerm_subnet" "replica_container" {
  name                            = "databricks-container"
  resource_group_name             = data.azurerm_resource_group.this.name
  virtual_network_name            = azurerm_virtual_network.replica.name
  address_prefixes                = [var.replica_container_subnet_cidr]
  default_outbound_access_enabled = false

  delegation {
    name = "databricks-container-delegation"
    service_delegation {
      name = "Microsoft.Databricks/workspaces"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action",
        "Microsoft.Network/virtualNetworks/subnets/prepareNetworkPolicies/action",
        "Microsoft.Network/virtualNetworks/subnets/unprepareNetworkPolicies/action",
      ]
    }
  }
}

resource "azurerm_subnet" "replica_private_endpoints" {
  name                              = "private-endpoints"
  resource_group_name               = data.azurerm_resource_group.this.name
  virtual_network_name              = azurerm_virtual_network.replica.name
  address_prefixes                  = [var.replica_private_endpoint_subnet_cidr]
  default_outbound_access_enabled   = false
  private_endpoint_network_policies = "Disabled"
}

resource "azurerm_subnet_network_security_group_association" "replica_host" {
  subnet_id                 = azurerm_subnet.replica_host.id
  network_security_group_id = azurerm_network_security_group.replica_databricks.id
}

resource "azurerm_subnet_network_security_group_association" "replica_container" {
  subnet_id                 = azurerm_subnet.replica_container.id
  network_security_group_id = azurerm_network_security_group.replica_databricks.id
}

resource "azurerm_subnet_network_security_group_association" "replica_private_endpoints" {
  subnet_id                 = azurerm_subnet.replica_private_endpoints.id
  network_security_group_id = azurerm_network_security_group.replica_private_endpoints.id
}

resource "azurerm_databricks_workspace" "replica" {
  name                        = var.replica_workspace_name
  resource_group_name         = data.azurerm_resource_group.this.name
  location                    = var.replica_location
  sku                         = var.sku
  managed_resource_group_name = "${var.replica_workspace_name}-managed-rg"

  public_network_access_enabled         = var.public_network_access_enabled
  network_security_group_rules_required = "AllRules"

  custom_parameters {
    no_public_ip                                         = true
    virtual_network_id                                   = azurerm_virtual_network.replica.id
    public_subnet_name                                   = azurerm_subnet.replica_host.name
    private_subnet_name                                  = azurerm_subnet.replica_container.name
    public_subnet_network_security_group_association_id  = azurerm_subnet_network_security_group_association.replica_host.id
    private_subnet_network_security_group_association_id = azurerm_subnet_network_security_group_association.replica_container.id
  }

  tags = local.replica_tags

  depends_on = [
    azurerm_subnet_network_security_group_association.replica_host,
    azurerm_subnet_network_security_group_association.replica_container,
  ]
}

# Both private endpoints publish distinct records in the same Databricks zone.
resource "azurerm_private_dns_zone_virtual_network_link" "replica_databricks" {
  count                 = var.enable_private_link ? 1 : 0
  name                  = "${var.replica_workspace_name}-dns-link"
  resource_group_name   = data.azurerm_resource_group.this.name
  private_dns_zone_name = azurerm_private_dns_zone.databricks[0].name
  virtual_network_id    = azurerm_virtual_network.replica.id
  registration_enabled  = false
  tags                  = local.replica_tags
}

resource "azurerm_private_endpoint" "replica_ui_api" {
  count               = var.enable_private_link ? 1 : 0
  name                = "${var.replica_workspace_name}-pe-uiapi"
  location            = var.replica_location
  resource_group_name = data.azurerm_resource_group.this.name
  subnet_id           = azurerm_subnet.replica_private_endpoints.id
  tags                = local.replica_tags

  private_service_connection {
    name                           = "${var.replica_workspace_name}-psc-uiapi"
    private_connection_resource_id = azurerm_databricks_workspace.replica.id
    is_manual_connection           = false
    subresource_names              = ["databricks_ui_api"]
  }

  private_dns_zone_group {
    name                 = "databricks-dns-zone-group"
    private_dns_zone_ids = [azurerm_private_dns_zone.databricks[0].id]
  }
}