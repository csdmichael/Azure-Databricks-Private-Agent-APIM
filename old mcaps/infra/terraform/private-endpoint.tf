# ---------------------------------------------------------------------------
# Back-end Private Link: private endpoint for the databricks_ui_api
# sub-resource so cluster <-> control-plane traffic stays on the VNet.
# Toggle with var.enable_private_link.
# ---------------------------------------------------------------------------
resource "azurerm_private_dns_zone" "databricks" {
  count               = var.enable_private_link ? 1 : 0
  name                = "privatelink.azuredatabricks.net"
  resource_group_name = data.azurerm_resource_group.this.name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "databricks" {
  count                 = var.enable_private_link ? 1 : 0
  name                  = "${var.workspace_name}-dns-link"
  resource_group_name   = data.azurerm_resource_group.this.name
  private_dns_zone_name = azurerm_private_dns_zone.databricks[0].name
  virtual_network_id    = azurerm_virtual_network.this.id
  registration_enabled  = false
  tags                  = var.tags
}

resource "azurerm_private_endpoint" "ui_api" {
  count               = var.enable_private_link ? 1 : 0
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
    private_dns_zone_ids = [azurerm_private_dns_zone.databricks[0].id]
  }
}
