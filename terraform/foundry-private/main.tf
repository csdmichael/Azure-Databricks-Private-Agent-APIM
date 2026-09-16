locals {
  config = jsondecode(file(var.config_path))

  subscription_id = coalesce(var.subscription_id, try(local.config.azure.subscriptionId, null))
  tenant_id       = coalesce(var.tenant_id, try(local.config.azure.tenantId, null))
  resource_group_name = coalesce(
    var.resource_group_name,
    try(local.config.azure.resourceGroup, null)
  )
  location = coalesce(var.location, try(local.config.network.foundryLocation, null))

  foundry_account_name = coalesce(
    var.foundry_account_name,
    try(local.config.foundry.private.accountName, null)
  )
  foundry_sku_name = coalesce(
    var.foundry_sku_name,
    try(local.config.foundry.private.skuName, null),
    "S0"
  )
  public_network_access = coalesce(
    var.public_network_access,
    try(local.config.foundry.private.publicNetworkAccess, null)
  )
  project_name = coalesce(
    var.project_name,
    try(local.config.foundry.private.projectName, null)
  )
  project_display_name = coalesce(
    var.project_display_name,
    try(local.config.foundry.private.projectDisplayName, null),
    local.project_name
  )
  project_description = coalesce(
    var.project_description,
    try(local.config.foundry.private.projectDescription, null),
    "Private Foundry project for the Databricks MCP agent"
  )
  project_capability_host_name = coalesce(
    var.project_capability_host_name,
    try(local.config.foundry.private.capabilityHostName, null)
  )

  model_deployment_name = coalesce(
    var.model_deployment_name,
    try(local.config.foundry.private.modelDeploymentName, null)
  )
  model_name = coalesce(
    var.model_name,
    try(local.config.foundry.private.modelName, null)
  )
  model_version = coalesce(
    var.model_version,
    try(local.config.foundry.private.modelVersion, null)
  )
  model_sku_name = coalesce(
    var.model_sku_name,
    try(local.config.foundry.private.modelSkuName, null)
  )
  model_capacity = coalesce(
    var.model_capacity,
    try(local.config.foundry.private.modelCapacity, null)
  )
  model_version_upgrade_option = coalesce(
    var.model_version_upgrade_option,
    try(local.config.foundry.private.modelVersionUpgradeOption, null),
    "OnceNewDefaultVersionAvailable"
  )

  vnet_name = coalesce(
    var.vnet_name,
    try(local.config.network.apimVnetName, null)
  )
  client_vnet_name = coalesce(
    var.client_vnet_name,
    try(local.config.network.databricksVnetName, null)
  )
  private_endpoint_subnet_name = coalesce(
    var.private_endpoint_subnet_name,
    try(local.config.network.privateEndpointSubnetName, null)
  )
  agent_subnet_name = coalesce(
    var.agent_subnet_name,
    try(local.config.network.foundryAgentSubnetName, null)
  )
  agent_subnet_prefix = coalesce(
    var.agent_subnet_prefix,
    try(local.config.network.foundryAgentSubnetCidr, null)
  )

  tags = var.tags != null ? var.tags : merge(
    try(local.config.tags, {}),
    { component = "foundry-private" }
  )

  foundry_private_dns_zone_names = [
    "privatelink.cognitiveservices.azure.com",
    "privatelink.openai.azure.com",
    "privatelink.services.ai.azure.com"
  ]
}

data "azurecaf_name" "agent_nsg" {
  name          = local.foundry_account_name
  resource_type = "azurerm_network_security_group"
  suffixes      = ["agent", "nsg"]
  use_slug      = false
}

data "azurecaf_name" "foundry_private_endpoint" {
  name          = local.foundry_account_name
  resource_type = "azurerm_private_endpoint"
  suffixes      = ["pe"]
  use_slug      = false
}

data "azurecaf_name" "foundry_private_service_connection" {
  name          = local.foundry_account_name
  resource_type = "azurerm_private_service_connection"
  suffixes      = ["connection"]
  use_slug      = false
}

data "azurecaf_name" "vnet_dns_link" {
  name          = local.vnet_name
  resource_type = "azurerm_private_dns_zone_virtual_network_link"
  suffixes      = ["link"]
  use_slug      = false
}

data "azurecaf_name" "client_vnet_dns_link" {
  name          = local.client_vnet_name
  resource_type = "azurerm_private_dns_zone_virtual_network_link"
  suffixes      = ["link"]
  use_slug      = false
}

data "azurerm_resource_group" "this" {
  name = local.resource_group_name
}

data "azurerm_virtual_network" "foundry" {
  name                = local.vnet_name
  resource_group_name = data.azurerm_resource_group.this.name
}

data "azurerm_virtual_network" "client" {
  name                = local.client_vnet_name
  resource_group_name = data.azurerm_resource_group.this.name
}

data "azurerm_subnet" "private_endpoints" {
  name                 = local.private_endpoint_subnet_name
  virtual_network_name = data.azurerm_virtual_network.foundry.name
  resource_group_name  = data.azurerm_resource_group.this.name
}

resource "azurerm_network_security_group" "agent" {
  name                = data.azurecaf_name.agent_nsg.result
  location            = local.location
  resource_group_name = data.azurerm_resource_group.this.name
  tags                = local.tags
}

resource "azurerm_subnet" "agent" {
  name                              = local.agent_subnet_name
  resource_group_name               = data.azurerm_resource_group.this.name
  virtual_network_name              = data.azurerm_virtual_network.foundry.name
  address_prefixes                  = [local.agent_subnet_prefix]
  private_endpoint_network_policies = "Disabled"

  delegation {
    name = "foundry-agent-service"

    service_delegation {
      name = "Microsoft.App/environments"
    }
  }
}

resource "azurerm_subnet_network_security_group_association" "agent" {
  subnet_id                 = azurerm_subnet.agent.id
  network_security_group_id = azurerm_network_security_group.agent.id
}

resource "azapi_resource" "foundry_account" {
  type      = "Microsoft.CognitiveServices/accounts@2026-05-01"
  name      = local.foundry_account_name
  parent_id = data.azurerm_resource_group.this.id
  location  = local.location
  tags      = local.tags

  identity {
    type = "SystemAssigned"
  }

  body = {
    kind = "AIServices"
    sku = {
      name = local.foundry_sku_name
    }
    properties = {
      allowProjectManagement = true
      customSubDomainName    = local.foundry_account_name
      disableLocalAuth       = true
      publicNetworkAccess    = local.public_network_access
      networkAcls = {
        bypass              = "AzureServices"
        defaultAction       = local.public_network_access == "Enabled" ? "Allow" : "Deny"
        ipRules             = []
        virtualNetworkRules = []
      }
      networkInjections = [
        {
          scenario                   = "agent"
          subnetArmId                = azurerm_subnet.agent.id
          useMicrosoftManagedNetwork = false
        }
      ]
    }
  }

  depends_on = [azurerm_subnet_network_security_group_association.agent]
}

resource "azapi_resource" "foundry_project" {
  type      = "Microsoft.CognitiveServices/accounts/projects@2025-06-01"
  name      = local.project_name
  parent_id = azapi_resource.foundry_account.id
  location  = local.location

  identity {
    type = "SystemAssigned"
  }

  body = {
    properties = {
      description = local.project_description
      displayName = local.project_display_name
    }
  }
}

resource "azapi_resource" "model_deployment" {
  type      = "Microsoft.CognitiveServices/accounts/deployments@2025-06-01"
  name      = local.model_deployment_name
  parent_id = azapi_resource.foundry_account.id

  body = {
    sku = {
      name     = local.model_sku_name
      capacity = local.model_capacity
    }
    properties = {
      model = {
        format  = "OpenAI"
        name    = local.model_name
        version = local.model_version
      }
      versionUpgradeOption = local.model_version_upgrade_option
    }
  }
}

resource "azurerm_private_dns_zone" "foundry" {
  for_each = toset(local.foundry_private_dns_zone_names)

  name                = each.value
  resource_group_name = data.azurerm_resource_group.this.name
  tags                = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "foundry" {
  for_each = azurerm_private_dns_zone.foundry

  name                  = data.azurecaf_name.vnet_dns_link.result
  resource_group_name   = data.azurerm_resource_group.this.name
  private_dns_zone_name = each.value.name
  virtual_network_id    = data.azurerm_virtual_network.foundry.id
  registration_enabled  = false
  tags                  = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "client" {
  for_each = azurerm_private_dns_zone.foundry

  name                  = data.azurecaf_name.client_vnet_dns_link.result
  resource_group_name   = data.azurerm_resource_group.this.name
  private_dns_zone_name = each.value.name
  virtual_network_id    = data.azurerm_virtual_network.client.id
  registration_enabled  = false
  tags                  = local.tags
}

resource "azurerm_private_endpoint" "foundry" {
  name                = data.azurecaf_name.foundry_private_endpoint.result
  location            = local.location
  resource_group_name = data.azurerm_resource_group.this.name
  subnet_id           = data.azurerm_subnet.private_endpoints.id
  tags                = local.tags

  private_service_connection {
    name                           = data.azurecaf_name.foundry_private_service_connection.result
    private_connection_resource_id = azapi_resource.foundry_account.id
    subresource_names              = ["account"]
    is_manual_connection           = false
  }
}

resource "azapi_resource" "foundry_private_dns_zone_group" {
  type      = "Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01"
  name      = "default"
  parent_id = azurerm_private_endpoint.foundry.id

  body = {
    properties = {
      privateDnsZoneConfigs = [
        for zone_name in local.foundry_private_dns_zone_names : {
          name = replace(zone_name, ".", "-")
          properties = {
            privateDnsZoneId = azurerm_private_dns_zone.foundry[zone_name].id
          }
        }
      ]
    }
  }
}

resource "azapi_resource" "project_capability_host" {
  type      = "Microsoft.CognitiveServices/accounts/projects/capabilityHosts@2025-04-01-preview"
  name      = local.project_capability_host_name
  parent_id = azapi_resource.foundry_project.id

  body = {
    properties = {
      capabilityHostKind = "Agents"
    }
  }

  schema_validation_enabled = false

  depends_on = [
    azapi_resource.foundry_private_dns_zone_group,
    azurerm_private_dns_zone_virtual_network_link.client
  ]
}