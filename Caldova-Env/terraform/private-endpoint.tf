# Simplified Private Link deployment: the workspace VNet is also the transit
# VNet, so one databricks_ui_api endpoint serves both front-end and back-end.
resource "azurerm_private_dns_zone" "databricks" {
  name                = "privatelink.azuredatabricks.net"
  resource_group_name = data.azurerm_resource_group.this.name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "databricks" {
  name                  = "${var.workspace_name}-dns-link"
  resource_group_name   = data.azurerm_resource_group.this.name
  private_dns_zone_name = azurerm_private_dns_zone.databricks.name
  virtual_network_id    = azurerm_virtual_network.this.id
  registration_enabled  = false
  tags                  = var.tags
}

resource "azurerm_private_endpoint" "ui_api" {
  name                = "${var.workspace_name}-pe-uiapi"
  location            = var.location
  resource_group_name = data.azurerm_resource_group.this.name
  subnet_id           = azurerm_subnet.private_endpoints.id
  tags                = var.tags

  private_service_connection {
    name                           = "${var.workspace_name}-psc-uiapi"
    private_connection_resource_id = azurerm_databricks_workspace.this.id
    is_manual_connection           = false
    subresource_names              = ["databricks_ui_api"]
  }

  private_dns_zone_group {
    name                 = "databricks-dns-zone-group"
    private_dns_zone_ids = [azurerm_private_dns_zone.databricks.id]
  }

  # Each endpoint mutates the workspace; creating them in parallel returns
  # ConcurrentUpdateError, so they must be serialized.
  depends_on = [azurerm_private_endpoint.browser_auth]
}

# Carries Entra ID SSO callbacks for browser logins over the private path.
# Only one may exist per region per private DNS zone.
resource "azurerm_private_endpoint" "browser_auth" {
  name                = "${var.workspace_name}-pe-browserauth"
  location            = var.location
  resource_group_name = data.azurerm_resource_group.this.name
  subnet_id           = azurerm_subnet.private_endpoints.id
  tags                = var.tags

  private_service_connection {
    name                           = "${var.workspace_name}-psc-browserauth"
    private_connection_resource_id = azurerm_databricks_workspace.this.id
    is_manual_connection           = false
    subresource_names              = ["browser_authentication"]
  }

  private_dns_zone_group {
    name                 = "databricks-dns-zone-group"
    private_dns_zone_ids = [azurerm_private_dns_zone.databricks.id]
  }
}
