# Uses the existing resource group provided for the POC.
data "azurerm_resource_group" "this" {
  name = var.resource_group_name
}

# ---------------------------------------------------------------------------
# Virtual network for Databricks VNet injection (workspace deployed INTO the VNet)
# ---------------------------------------------------------------------------
resource "azurerm_virtual_network" "this" {
  name                = var.vnet_name
  location            = var.location
  resource_group_name = data.azurerm_resource_group.this.name
  address_space       = [var.vnet_cidr]
  tags                = var.tags
}

# Network security group shared by the two delegated Databricks subnets.
# Databricks automatically injects the required inbound/outbound rules.
resource "azurerm_network_security_group" "databricks" {
  name                = "${var.workspace_name}-nsg"
  location            = var.location
  resource_group_name = data.azurerm_resource_group.this.name
  tags                = var.tags
}

# Host (a.k.a. public) delegated subnet.
resource "azurerm_subnet" "host" {
  name                            = "databricks-host"
  resource_group_name             = data.azurerm_resource_group.this.name
  virtual_network_name            = azurerm_virtual_network.this.name
  address_prefixes                = [var.host_subnet_cidr]
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

# Container (a.k.a. private) delegated subnet.
resource "azurerm_subnet" "container" {
  name                            = "databricks-container"
  resource_group_name             = data.azurerm_resource_group.this.name
  virtual_network_name            = azurerm_virtual_network.this.name
  address_prefixes                = [var.container_subnet_cidr]
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

# Dedicated subnet for Private Link private endpoints (no delegation).
resource "azurerm_subnet" "private_endpoints" {
  name                              = "private-endpoints"
  resource_group_name               = data.azurerm_resource_group.this.name
  virtual_network_name              = azurerm_virtual_network.this.name
  address_prefixes                  = [var.private_endpoint_subnet_cidr]
  default_outbound_access_enabled   = false
  private_endpoint_network_policies = "Disabled"
}

resource "azurerm_subnet_network_security_group_association" "host" {
  subnet_id                 = azurerm_subnet.host.id
  network_security_group_id = azurerm_network_security_group.databricks.id
}

resource "azurerm_subnet_network_security_group_association" "container" {
  subnet_id                 = azurerm_subnet.container.id
  network_security_group_id = azurerm_network_security_group.databricks.id
}
