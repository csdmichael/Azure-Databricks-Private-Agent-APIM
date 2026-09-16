locals {
  config = jsondecode(file(var.config_path))

  subscription_id = coalesce(var.subscription_id, try(local.config.azure.subscriptionId, null))
  tenant_id       = coalesce(var.tenant_id, try(local.config.azure.tenantId, null))
  resource_group_name = coalesce(
    var.resource_group_name,
    try(local.config.azure.resourceGroup, null)
  )

  apim_service_name = coalesce(var.apim_service_name, try(local.config.apim.serviceName, null))
  apim_vnet_name = coalesce(
    var.apim_vnet_name,
    try(local.config.network.apimVnetName, null),
    "${local.apim_service_name}-vnet"
  )
  primary_region             = coalesce(var.primary_region, try(local.config.network.powerPlatformPrimaryRegion, null))
  secondary_region           = coalesce(var.secondary_region, try(local.config.network.powerPlatformSecondaryRegion, null))
  primary_vnet_name          = coalesce(var.primary_vnet_name, try(local.config.network.powerPlatformPrimaryVnetName, null))
  secondary_vnet_name        = coalesce(var.secondary_vnet_name, try(local.config.network.powerPlatformSecondaryVnetName, null))
  power_platform_subnet_name = coalesce(var.power_platform_subnet_name, try(local.config.network.powerPlatformSubnetName, null))
  primary_vnet_cidr          = coalesce(var.primary_vnet_cidr, try(local.config.network.powerPlatformPrimaryVnetCidr, null))
  primary_subnet_cidr        = coalesce(var.primary_subnet_cidr, try(local.config.network.powerPlatformPrimarySubnetCidr, null))
  secondary_vnet_cidr        = coalesce(var.secondary_vnet_cidr, try(local.config.network.powerPlatformSecondaryVnetCidr, null))
  secondary_subnet_cidr      = coalesce(var.secondary_subnet_cidr, try(local.config.network.powerPlatformSecondarySubnetCidr, null))
  enterprise_policy_name     = coalesce(var.enterprise_policy_name, try(local.config.powerPlatform.enterprisePolicyName, null))
  tags                       = coalesce(var.tags, try(tomap(local.config.tags), null), {})
  apim_private_dns_zone_name = "privatelink.azure-api.net"
  power_platform_delegation  = "Microsoft.PowerPlatform/enterprisePolicies"

  policy_geographies = {
    canadacentral  = "canada"
    canadaeast     = "canada"
    centralus      = "unitedstates"
    eastus         = "unitedstates"
    eastus2        = "unitedstates"
    northcentralus = "unitedstates"
    southcentralus = "unitedstates"
    westcentralus  = "unitedstates"
    westus         = "unitedstates"
    westus2        = "unitedstates"
    westus3        = "unitedstates"
  }
  policy_location = try(
    coalesce(var.policy_location, lookup(local.policy_geographies, local.primary_region, null)),
    null
  )

  peering_names = {
    apim_to_primary   = "apim-to-power-platform-${local.primary_region}"
    primary_to_apim   = "power-platform-${local.primary_region}-to-apim"
    apim_to_secondary = "apim-to-power-platform-${local.secondary_region}"
    secondary_to_apim = "power-platform-${local.secondary_region}-to-apim"
  }
}

check "matching_power_platform_subnet_sizes" {
  assert {
    condition = try(
      split("/", local.primary_subnet_cidr)[1] == split("/", local.secondary_subnet_cidr)[1],
      false
    )
    error_message = "The primary and secondary Power Platform subnets must expose the same usable address count."
  }
}

data "azurerm_resource_group" "this" {
  name = local.resource_group_name
}

data "azurerm_virtual_network" "apim" {
  name                = local.apim_vnet_name
  resource_group_name = data.azurerm_resource_group.this.name
}

data "azurerm_private_dns_zone" "apim" {
  name                = local.apim_private_dns_zone_name
  resource_group_name = data.azurerm_resource_group.this.name
}

data "azurecaf_name" "peering" {
  for_each = local.peering_names

  name          = each.value
  resource_type = "azurerm_virtual_network_peering"
  passthrough   = true
}

resource "azurerm_virtual_network" "primary" {
  name                = local.primary_vnet_name
  location            = local.primary_region
  resource_group_name = data.azurerm_resource_group.this.name
  address_space       = [local.primary_vnet_cidr]
  tags                = local.tags
}

resource "azurerm_subnet" "primary" {
  name                 = local.power_platform_subnet_name
  resource_group_name  = data.azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.primary.name
  address_prefixes     = [local.primary_subnet_cidr]

  delegation {
    name = "power-platform-enterprise-policies"

    service_delegation {
      name = local.power_platform_delegation
    }
  }
}

resource "azurerm_virtual_network" "secondary" {
  name                = local.secondary_vnet_name
  location            = local.secondary_region
  resource_group_name = data.azurerm_resource_group.this.name
  address_space       = [local.secondary_vnet_cidr]
  tags                = local.tags
}

resource "azurerm_subnet" "secondary" {
  name                 = local.power_platform_subnet_name
  resource_group_name  = data.azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.secondary.name
  address_prefixes     = [local.secondary_subnet_cidr]

  delegation {
    name = "power-platform-enterprise-policies"

    service_delegation {
      name = local.power_platform_delegation
    }
  }
}

resource "azurerm_virtual_network_peering" "apim_to_primary" {
  name                         = data.azurecaf_name.peering["apim_to_primary"].result
  resource_group_name          = data.azurerm_resource_group.this.name
  virtual_network_name         = data.azurerm_virtual_network.apim.name
  remote_virtual_network_id    = azurerm_virtual_network.primary.id
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  allow_virtual_network_access = true
  use_remote_gateways          = false

  depends_on = [azurerm_subnet.primary]
}

resource "azurerm_virtual_network_peering" "primary_to_apim" {
  name                         = data.azurecaf_name.peering["primary_to_apim"].result
  resource_group_name          = data.azurerm_resource_group.this.name
  virtual_network_name         = azurerm_virtual_network.primary.name
  remote_virtual_network_id    = data.azurerm_virtual_network.apim.id
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  allow_virtual_network_access = true
  use_remote_gateways          = false

  depends_on = [azurerm_subnet.primary]
}

resource "azurerm_virtual_network_peering" "apim_to_secondary" {
  name                         = data.azurecaf_name.peering["apim_to_secondary"].result
  resource_group_name          = data.azurerm_resource_group.this.name
  virtual_network_name         = data.azurerm_virtual_network.apim.name
  remote_virtual_network_id    = azurerm_virtual_network.secondary.id
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  allow_virtual_network_access = true
  use_remote_gateways          = false

  depends_on = [
    azurerm_subnet.secondary,
    azurerm_virtual_network_peering.apim_to_primary,
  ]
}

resource "azurerm_virtual_network_peering" "secondary_to_apim" {
  name                         = data.azurecaf_name.peering["secondary_to_apim"].result
  resource_group_name          = data.azurerm_resource_group.this.name
  virtual_network_name         = azurerm_virtual_network.secondary.name
  remote_virtual_network_id    = data.azurerm_virtual_network.apim.id
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  allow_virtual_network_access = true
  use_remote_gateways          = false

  depends_on = [azurerm_subnet.secondary]
}

resource "azurerm_private_dns_zone_virtual_network_link" "apim_to_primary" {
  name                  = "power-platform-${local.primary_region}-apim-dns-link"
  resource_group_name   = data.azurerm_resource_group.this.name
  private_dns_zone_name = data.azurerm_private_dns_zone.apim.name
  virtual_network_id    = azurerm_virtual_network.primary.id
  registration_enabled  = false
  tags                  = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "apim_to_secondary" {
  name                  = "power-platform-${local.secondary_region}-apim-dns-link"
  resource_group_name   = data.azurerm_resource_group.this.name
  private_dns_zone_name = data.azurerm_private_dns_zone.apim.name
  virtual_network_id    = azurerm_virtual_network.secondary.id
  registration_enabled  = false
  tags                  = local.tags
}

resource "azapi_resource" "network_injection_policy" {
  type      = "Microsoft.PowerPlatform/enterprisePolicies@2020-10-30-preview"
  name      = local.enterprise_policy_name
  parent_id = data.azurerm_resource_group.this.id
  location  = local.policy_location
  tags      = local.tags

  body = {
    kind = "NetworkInjection"
    properties = {
      networkInjection = {
        virtualNetworks = [
          {
            id = azurerm_virtual_network.primary.id
            subnet = {
              name = azurerm_subnet.primary.name
            }
          },
          {
            id = azurerm_virtual_network.secondary.id
            subnet = {
              name = azurerm_subnet.secondary.name
            }
          },
        ]
      }
    }
  }

  schema_validation_enabled = false

  lifecycle {
    precondition {
      condition     = local.policy_location != null
      error_message = "policy_location must be set when primary_region is not in the built-in Canada or United States mapping."
    }
  }
}