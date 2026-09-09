# ---------------------------------------------------------------------------
# Azure Databricks workspace (Premium) deployed with VNet injection and
# Secure Cluster Connectivity (no public IP). Lowest-cost private footprint:
# you only pay for DBUs consumed by serverless compute (auto-stopped).
# ---------------------------------------------------------------------------
resource "azurerm_databricks_workspace" "this" {
  name                        = var.workspace_name
  resource_group_name         = data.azurerm_resource_group.this.name
  location                    = var.location
  sku                         = var.sku
  managed_resource_group_name = "${var.workspace_name}-managed-rg"

  # Secure Cluster Connectivity keeps the front-end URL reachable for
  # management/data-load while all compute has no public IP.
  public_network_access_enabled         = var.public_network_access_enabled
  network_security_group_rules_required = "AllRules"

  custom_parameters {
    no_public_ip                                         = true
    virtual_network_id                                   = azurerm_virtual_network.this.id
    public_subnet_name                                   = azurerm_subnet.host.name
    private_subnet_name                                  = azurerm_subnet.container.name
    public_subnet_network_security_group_association_id  = azurerm_subnet_network_security_group_association.host.id
    private_subnet_network_security_group_association_id = azurerm_subnet_network_security_group_association.container.id
  }

  tags = var.tags

  depends_on = [
    azurerm_subnet_network_security_group_association.host,
    azurerm_subnet_network_security_group_association.container,
  ]
}
