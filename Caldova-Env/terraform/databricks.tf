# VNet-injected workspace with Secure Cluster Connectivity (no public IP).
# var.lockdown drives the stage 1 -> stage 2 transition to a fully private front end.
resource "azurerm_databricks_workspace" "this" {
  name                        = var.workspace_name
  resource_group_name         = data.azurerm_resource_group.this.name
  location                    = var.location
  sku                         = var.sku
  managed_resource_group_name = "${var.workspace_name}-managed-rg"

  public_network_access_enabled = !var.lockdown

  # NoAzureDatabricksRules is only valid once the back-end private endpoint exists.
  network_security_group_rules_required = var.lockdown ? "NoAzureDatabricksRules" : "AllRules"

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
