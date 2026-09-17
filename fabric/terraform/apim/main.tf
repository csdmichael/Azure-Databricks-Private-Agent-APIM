locals {
  config = jsondecode(file(var.config_path))

  apim_tenant_id           = trimspace(local.config.apim.tenantId)
  apim_subscription_id     = trimspace(local.config.apim.subscriptionId)
  apim_resource_group_name = trimspace(local.config.apim.resourceGroup)
  apim_location            = trimspace(local.config.apim.location)
  create_apim_service      = local.config.apim.createService
  apim_service_name        = trimspace(local.config.apim.serviceName)
  apim_sku_name            = trimspace(local.config.apim.skuName)
  apim_publisher_email     = trimspace(local.config.apim.publisherEmail)
  apim_publisher_name      = trimspace(local.config.apim.publisherName)
  apim_gateway_url         = trimsuffix(trimspace(local.config.apim.gatewayUrl), "/")
  apim_vnet_resource_id    = trimspace(local.config.network.apimVnetResourceId)
  apim_vnet_parts          = split("/", local.apim_vnet_resource_id)
  apim_vnet_name           = local.apim_vnet_parts[8]
  apim_subnet_name         = trimspace(local.config.network.apimSubnetName)
  apim_subnet_prefix       = trimspace(local.config.network.apimSubnetPrefix)
  broker_app_name          = trimspace(local.config.broker.appName)
  broker_private_url       = trimsuffix(trimspace(var.broker_private_url), "/")
  expected_broker_url      = "https://${local.broker_app_name}.azurewebsites.net"

  resource_tenant_id = lower(trimspace(local.config.identity.resourceTenantId))
  caller_tenant_id   = lower(trimspace(local.config.identity.callerTenantId))
  delegated_scope    = trimspace(local.config.identity.delegatedScope)
  broker_role        = trimspace(local.config.identity.brokerApplicationRole)

  connector_client_ids                     = [for value in var.connector_client_ids : lower(trimspace(value))]
  allowed_user_object_ids                  = [for value in var.allowed_user_object_ids : lower(trimspace(value))]
  application_insights_name                = trimspace(coalesce(var.application_insights_name, ""))
  diagnostics_enabled                      = local.application_insights_name != ""
  application_insights_resource_group_name = trimspace(coalesce(var.application_insights_resource_group_name, "")) != "" ? trimspace(var.application_insights_resource_group_name) : local.apim_resource_group_name

  named_values = {
    fabric-obo-resource-tenant-id         = local.resource_tenant_id
    fabric-obo-caller-tenant-id           = local.caller_tenant_id
    fabric-obo-resource-api-client-id     = lower(trimspace(var.resource_api_client_id))
    fabric-obo-delegated-scope            = local.delegated_scope
    fabric-obo-connector-client-ids       = join(",", local.connector_client_ids)
    fabric-obo-allowed-user-oids          = join(",", local.allowed_user_object_ids)
    fabric-obo-broker-audience            = lower(trimspace(var.broker_audience))
    fabric-obo-broker-role                = local.broker_role
    fabric-obo-broker-private-url         = local.broker_private_url
    fabric-obo-rate-limit-calls           = tostring(local.config.apim.rateLimitCalls)
    fabric-obo-rate-limit-renewal-seconds = tostring(local.config.apim.rateLimitRenewalSeconds)
    fabric-obo-request-timeout-seconds    = tostring(local.config.apim.requestTimeoutSeconds)
  }

  apis = {
    lakehouse = {
      name         = local.config.apim.lakehouseApiId
      display_name = "Fabric Lakehouse OAuth"
      description  = "Read-only Fabric Lakehouse operations using delegated OAuth through the private broker."
      path         = local.config.apim.lakehouseApiPath
      openapi_file = "${path.module}/../../apim/openapi/lakehouse.json"
    }
    data-agent = {
      name         = local.config.apim.dataAgentApiId
      display_name = "Fabric Data Agent OAuth"
      description  = "Fabric Data Agent queries using delegated OAuth through the private broker."
      path         = local.config.apim.dataAgentApiPath
      openapi_file = "${path.module}/../../apim/openapi/data-agent.json"
    }
  }

  operations = {
    lakehouse-query = {
      api_key      = "lakehouse"
      operation_id = "query"
      policy_file  = "lakehouse-query-operation-policy.xml"
    }
    lakehouse-tables = {
      api_key      = "lakehouse"
      operation_id = "tables"
      policy_file  = "lakehouse-tables-operation-policy.xml"
    }
    data-agent-query = {
      api_key      = "data-agent"
      operation_id = "query"
      policy_file  = "data-agent-query-operation-policy.xml"
    }
  }

  mcp_servers = {
    lakehouse = {
      name           = "${local.config.apim.lakehouseApiId}-mcp"
      display_name   = local.config.apim.lakehouseMcpDisplayName
      description    = "MCP tools for the Fabric Lakehouse OAuth API."
      path           = local.config.apim.lakehouseMcpPath
      operation_keys = ["lakehouse-query", "lakehouse-tables"]
    }
    data-agent = {
      name           = "${local.config.apim.dataAgentApiId}-mcp"
      display_name   = local.config.apim.dataAgentMcpDisplayName
      description    = "MCP tool for the Fabric Data Agent OAuth API."
      path           = local.config.apim.dataAgentMcpPath
      operation_keys = ["data-agent-query"]
    }
  }

  required_config_values = [
    local.apim_tenant_id,
    local.apim_subscription_id,
    local.apim_resource_group_name,
    local.apim_location,
    local.apim_service_name,
    local.apim_sku_name,
    local.apim_publisher_email,
    local.apim_publisher_name,
    local.apim_gateway_url,
    local.apim_vnet_resource_id,
    local.broker_app_name,
    local.resource_tenant_id,
    local.caller_tenant_id,
    local.delegated_scope,
    local.broker_role,
    local.config.apim.lakehouseApiId,
    local.config.apim.lakehouseApiPath,
    local.config.apim.lakehouseMcpDisplayName,
    local.config.apim.lakehouseMcpPath,
    local.config.apim.dataAgentApiId,
    local.config.apim.dataAgentApiPath,
    local.config.apim.dataAgentMcpDisplayName,
    local.config.apim.dataAgentMcpPath,
    local.config.apim.productId,
  ]

  apim_nsg_rules = {
    internet-client = { priority = 100, direction = "Inbound", source = "Internet", destination = "VirtualNetwork", ports = ["80", "443"] }
    control-plane   = { priority = 110, direction = "Inbound", source = "ApiManagement", destination = "VirtualNetwork", ports = ["3443"] }
    load-balancer   = { priority = 120, direction = "Inbound", source = "AzureLoadBalancer", destination = "VirtualNetwork", ports = ["6390"] }
    traffic-manager = { priority = 130, direction = "Inbound", source = "AzureTrafficManager", destination = "VirtualNetwork", ports = ["443"] }
    certificates    = { priority = 200, direction = "Outbound", source = "VirtualNetwork", destination = "Internet", ports = ["80"] }
    storage         = { priority = 210, direction = "Outbound", source = "VirtualNetwork", destination = "Storage", ports = ["443"] }
    sql             = { priority = 220, direction = "Outbound", source = "VirtualNetwork", destination = "Sql", ports = ["1433"] }
    key-vault       = { priority = 230, direction = "Outbound", source = "VirtualNetwork", destination = "AzureKeyVault", ports = ["443"] }
    monitor         = { priority = 240, direction = "Outbound", source = "VirtualNetwork", destination = "AzureMonitor", ports = ["1886", "443"] }
    entra           = { priority = 250, direction = "Outbound", source = "VirtualNetwork", destination = "AzureActiveDirectory", ports = ["443"] }
  }
}

resource "terraform_data" "guardrails" {
  input = {
    apim_service_name = local.apim_service_name
    broker_url        = local.broker_private_url
  }

  lifecycle {
    precondition {
      condition     = alltrue([for value in local.required_config_values : length(trimspace(tostring(value))) > 0])
      error_message = "The APIM, identity, broker, API, MCP, and VNet values required from config_path must not be empty."
    }
    precondition {
      condition     = length(trimspace(var.resource_api_client_id)) > 0 && length(trimspace(var.broker_audience)) > 0
      error_message = "The generated resource API client ID and broker audience must not be empty."
    }
    precondition {
      condition     = length(local.connector_client_ids) > 0 && length(local.allowed_user_object_ids) > 0 && alltrue([for value in concat(local.connector_client_ids, local.allowed_user_object_ids) : length(value) > 0])
      error_message = "Connector and Fabric user allowlists must contain nonempty IDs."
    }
    precondition {
      condition     = local.broker_private_url == local.expected_broker_url
      error_message = "broker_private_url must be the fixed origin https://<config.broker.appName>.azurewebsites.net."
    }
    precondition {
      condition     = local.config.apim.rateLimitCalls > 0 && local.config.apim.rateLimitRenewalSeconds > 0 && local.config.apim.requestTimeoutSeconds > 0
      error_message = "APIM rate-limit and timeout values in config_path must be positive."
    }
  }
}

data "azurerm_resource_group" "apim" {
  name = local.apim_resource_group_name
}

data "azurerm_virtual_network" "apim" {
  name                = local.apim_vnet_name
  resource_group_name = local.apim_resource_group_name
}

resource "azurerm_network_security_group" "apim" {
  count = local.create_apim_service ? 1 : 0

  name                = "nsg-${local.apim_service_name}"
  location            = local.apim_location
  resource_group_name = local.apim_resource_group_name
  tags                = tomap(local.config.tags)
}

resource "azurerm_network_security_rule" "apim" {
  for_each = local.create_apim_service ? local.apim_nsg_rules : {}

  name                        = "Allow-${each.key}"
  priority                    = each.value.priority
  direction                   = each.value.direction
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_ranges     = each.value.ports
  source_address_prefix       = each.value.source
  destination_address_prefix  = each.value.destination
  resource_group_name         = local.apim_resource_group_name
  network_security_group_name = azurerm_network_security_group.apim[0].name
}

resource "azurerm_subnet" "apim" {
  count = local.create_apim_service ? 1 : 0

  name                 = local.apim_subnet_name
  resource_group_name  = local.apim_resource_group_name
  virtual_network_name = data.azurerm_virtual_network.apim.name
  address_prefixes     = [local.apim_subnet_prefix]
  service_endpoints    = ["Microsoft.Storage", "Microsoft.Sql", "Microsoft.KeyVault", "Microsoft.EventHub"]
}

resource "azurerm_subnet_network_security_group_association" "apim" {
  count = local.create_apim_service ? 1 : 0

  subnet_id                 = azurerm_subnet.apim[0].id
  network_security_group_id = azurerm_network_security_group.apim[0].id
}

resource "azurerm_api_management" "this" {
  count = local.create_apim_service ? 1 : 0

  name                          = local.apim_service_name
  location                      = local.apim_location
  resource_group_name           = local.apim_resource_group_name
  publisher_name                = local.apim_publisher_name
  publisher_email               = local.apim_publisher_email
  sku_name                      = "${local.apim_sku_name}_1"
  public_network_access_enabled = true
  virtual_network_type          = "External"
  tags                          = tomap(local.config.tags)

  identity {
    type = "SystemAssigned"
  }

  virtual_network_configuration {
    subnet_id = azurerm_subnet.apim[0].id
  }

  security {
    enable_backend_ssl30  = false
    enable_backend_tls10  = false
    enable_backend_tls11  = false
    enable_frontend_ssl30 = false
    enable_frontend_tls10 = false
    enable_frontend_tls11 = false
  }

  depends_on = [
    azurerm_network_security_rule.apim,
    azurerm_subnet_network_security_group_association.apim,
  ]
}

data "azurerm_api_management" "this" {
  count = local.create_apim_service ? 0 : 1

  name                = local.apim_service_name
  resource_group_name = local.apim_resource_group_name

  depends_on = [terraform_data.guardrails]
}

locals {
  apim_id           = local.create_apim_service ? azurerm_api_management.this[0].id : data.azurerm_api_management.this[0].id
  apim_principal_id = local.create_apim_service ? azurerm_api_management.this[0].identity[0].principal_id : data.azurerm_api_management.this[0].identity[0].principal_id
}

resource "azapi_resource" "named_value" {
  for_each = local.named_values

  type      = "Microsoft.ApiManagement/service/namedValues@2024-06-01-preview"
  name      = each.key
  parent_id = local.apim_id

  body = {
    properties = {
      displayName = each.key
      value       = each.value
      secret      = false
    }
  }
}

resource "azapi_resource" "api" {
  for_each = local.apis

  type      = "Microsoft.ApiManagement/service/apis@2024-06-01-preview"
  name      = each.value.name
  parent_id = local.apim_id

  body = {
    properties = {
      displayName          = each.value.display_name
      description          = each.value.description
      path                 = each.value.path
      protocols            = ["https"]
      subscriptionRequired = false
      format               = "openapi+json"
      value                = file(each.value.openapi_file)
    }
  }
}

resource "azapi_resource" "api_policy" {
  for_each = azapi_resource.api

  type      = "Microsoft.ApiManagement/service/apis/policies@2024-06-01-preview"
  name      = "policy"
  parent_id = each.value.id

  body = {
    properties = {
      format = "rawxml"
      value  = file("${path.module}/../../apim/policies/fabric-obo-api-policy.xml")
    }
  }

  depends_on = [azapi_resource.named_value]
}

resource "azapi_resource" "operation_policy" {
  for_each = local.operations

  type      = "Microsoft.ApiManagement/service/apis/operations/policies@2024-06-01-preview"
  name      = "policy"
  parent_id = "${azapi_resource.api[each.value.api_key].id}/operations/${each.value.operation_id}"

  body = {
    properties = {
      format = "rawxml"
      value  = file("${path.module}/../../apim/policies/${each.value.policy_file}")
    }
  }
}

resource "azapi_resource" "mcp_server" {
  for_each = local.mcp_servers

  type      = "Microsoft.ApiManagement/service/apis@2024-06-01-preview"
  name      = each.value.name
  parent_id = local.apim_id

  body = {
    properties = {
      type                 = "mcp"
      displayName          = each.value.display_name
      description          = each.value.description
      path                 = each.value.path
      protocols            = ["https"]
      subscriptionRequired = false
      mcpTools = [
        for operation_key in each.value.operation_keys : {
          name        = local.operations[operation_key].operation_id
          operationId = "${azapi_resource.api[local.operations[operation_key].api_key].id}/operations/${local.operations[operation_key].operation_id}"
        }
      ]
    }
  }

  schema_validation_enabled = false
  depends_on                = [azapi_resource.operation_policy]
}

resource "azapi_resource" "product" {
  type      = "Microsoft.ApiManagement/service/products@2024-06-01-preview"
  name      = local.config.apim.productId
  parent_id = local.apim_id

  body = {
    properties = {
      displayName          = "Fabric Agents"
      description          = "Delegated Fabric REST APIs and MCP servers."
      subscriptionRequired = false
      approvalRequired     = false
      state                = "published"
    }
  }
}

resource "azapi_resource" "product_api_link" {
  for_each = merge(
    {
      for key, api in azapi_resource.api : "rest-${key}" => {
        name   = local.apis[key].name
        api_id = api.id
      }
    },
    {
      for key, api in azapi_resource.mcp_server : "mcp-${key}" => {
        name   = local.mcp_servers[key].name
        api_id = api.id
      }
    }
  )

  type      = "Microsoft.ApiManagement/service/products/apiLinks@2024-06-01-preview"
  name      = "link-${each.value.name}"
  parent_id = azapi_resource.product.id

  body = {
    properties = {
      apiId = each.value.api_id
    }
  }
}

data "azurerm_application_insights" "this" {
  count = local.diagnostics_enabled ? 1 : 0

  name                = local.application_insights_name
  resource_group_name = local.application_insights_resource_group_name
}

resource "azapi_resource" "logger" {
  count = local.diagnostics_enabled ? 1 : 0

  type      = "Microsoft.ApiManagement/service/loggers@2024-06-01-preview"
  name      = "fabric-obo-insights"
  parent_id = local.apim_id

  body = {
    properties = {
      loggerType = "applicationInsights"
      credentials = {
        instrumentationKey = data.azurerm_application_insights.this[0].instrumentation_key
      }
      resourceId = data.azurerm_application_insights.this[0].id
      isBuffered = true
    }
  }
}

locals {
  diagnostic_targets = merge(
    {
      for key, api in azapi_resource.api : "rest-${key}" => api.id
    },
    {
      for key, api in azapi_resource.mcp_server : "mcp-${key}" => api.id
    }
  )
}

resource "azapi_resource" "diagnostic" {
  for_each = local.diagnostics_enabled ? local.diagnostic_targets : {}

  type      = "Microsoft.ApiManagement/service/apis/diagnostics@2024-06-01-preview"
  name      = "applicationinsights"
  parent_id = each.value

  body = {
    properties = {
      loggerId  = azapi_resource.logger[0].id
      alwaysLog = "allErrors"
      sampling = {
        samplingType = "fixed"
        percentage   = 100
      }
      verbosity               = "information"
      logClientIp             = false
      httpCorrelationProtocol = "W3C"
      frontend = {
        request  = { headers = [], body = { bytes = 0 } }
        response = { headers = [], body = { bytes = 0 } }
      }
      backend = {
        request  = { headers = [], body = { bytes = 0 } }
        response = { headers = [], body = { bytes = 0 } }
      }
    }
  }
}

