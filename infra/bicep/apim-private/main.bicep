@description('Globally unique API Management service name.')
param apimServiceName string = 'ai-gateway-apim-poc-my2'

@description('Azure region for the API Management service and its dedicated virtual network.')
param location string = 'westus'

@description('API Management publisher display name.')
param publisherName string = 'Azure AI Gateway'

@description('API Management publisher email address.')
param publisherEmail string

@description('Existing West US 2 Databricks virtual network to peer with the APIM virtual network.')
param databricksVnetName string = 'databricks-vnet-ai-poc2'

@description('Existing private DNS zone used by Azure Databricks private endpoints.')
param databricksPrivateDnsZoneName string = 'privatelink.azuredatabricks.net'

@description('Existing private DNS zone used by API Management private endpoints.')
param apimPrivateDnsZoneName string = 'privatelink.azure-api.net'

@description('Public ingress state. Use Enabled for initial creation, then Disabled only after validating the private endpoint.')
@allowed([
  'Enabled'
  'Disabled'
])
param publicNetworkAccess string

param tags object = {
  environment: 'poc'
  managed_by: 'bicep'
  workload: 'databricks-ai-gateway'
}

var apimVnetName = '${apimServiceName}-vnet'
var integrationSubnetName = 'apim-outbound-integration'
var privateEndpointSubnetName = 'private-endpoints'
var integrationNsgName = '${apimServiceName}-integration-nsg'
var privateEndpointNsgName = '${apimServiceName}-private-endpoints-nsg'

resource databricksVnet 'Microsoft.Network/virtualNetworks@2024-05-01' existing = {
  name: databricksVnetName
}

resource databricksPrivateDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' existing = {
  name: databricksPrivateDnsZoneName
}

resource apimPrivateDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' existing = {
  name: apimPrivateDnsZoneName
}

resource integrationNsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: integrationNsgName
  location: location
  tags: tags
  properties: {
    securityRules: []
  }
}

resource privateEndpointNsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: privateEndpointNsgName
  location: location
  tags: tags
  properties: {
    securityRules: []
  }
}

resource apimVnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: apimVnetName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.181.0.0/16'
      ]
    }
  }
}

resource integrationSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' = {
  parent: apimVnet
  name: integrationSubnetName
  properties: {
    addressPrefix: '10.181.0.0/24'
    delegations: [
      {
        name: 'apim-standard-v2-integration'
        properties: {
          serviceName: 'Microsoft.Web/serverFarms'
        }
      }
    ]
    networkSecurityGroup: {
      id: integrationNsg.id
    }
  }
}

resource privateEndpointSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' = {
  parent: apimVnet
  name: privateEndpointSubnetName
  properties: {
    addressPrefix: '10.181.1.0/24'
    networkSecurityGroup: {
      id: privateEndpointNsg.id
    }
    privateEndpointNetworkPolicies: 'Disabled'
  }
}

resource apimToDatabricksPeering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-05-01' = {
  parent: apimVnet
  name: 'apim-to-databricks-poc2'
  properties: {
    allowForwardedTraffic: true
    allowGatewayTransit: false
    allowVirtualNetworkAccess: true
    remoteVirtualNetwork: {
      id: databricksVnet.id
    }
    useRemoteGateways: false
  }
  dependsOn: [
    integrationSubnet
    privateEndpointSubnet
  ]
}

resource databricksToApimPeering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-05-01' = {
  parent: databricksVnet
  name: 'databricks-poc2-to-apim'
  properties: {
    allowForwardedTraffic: true
    allowGatewayTransit: false
    allowVirtualNetworkAccess: true
    remoteVirtualNetwork: {
      id: apimVnet.id
    }
    useRemoteGateways: false
  }
  dependsOn: [
    integrationSubnet
    privateEndpointSubnet
  ]
}

resource databricksDnsLinkToApim 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: databricksPrivateDnsZone
  name: '${apimServiceName}-databricks-dns-link'
  location: 'global'
  tags: tags
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: apimVnet.id
    }
  }
}

resource apimDnsLinkToApim 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: apimPrivateDnsZone
  name: '${apimServiceName}-gateway-dns-link'
  location: 'global'
  tags: tags
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: apimVnet.id
    }
  }
}

resource apimDnsLinkToDatabricks 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: apimPrivateDnsZone
  name: '${databricksVnetName}-apim-dns-link'
  location: 'global'
  tags: tags
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: databricksVnet.id
    }
  }
}

resource apim 'Microsoft.ApiManagement/service@2024-05-01' = {
  name: apimServiceName
  location: location
  tags: tags
  sku: {
    name: 'StandardV2'
    capacity: 1
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    publisherEmail: publisherEmail
    publisherName: publisherName
    publicNetworkAccess: publicNetworkAccess
    virtualNetworkType: 'External'
    virtualNetworkConfiguration: {
      subnetResourceId: integrationSubnet.id
    }
  }
}

resource apimPrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: '${apimServiceName}-gateway-pe'
  location: location
  tags: tags
  properties: {
    privateLinkServiceConnections: [
      {
        name: '${apimServiceName}-gateway-connection'
        properties: {
          groupIds: [
            'Gateway'
          ]
          privateLinkServiceId: apim.id
        }
      }
    ]
    subnet: {
      id: privateEndpointSubnet.id
    }
  }
}

resource apimPrivateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: apimPrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'apim-gateway'
        properties: {
          privateDnsZoneId: apimPrivateDnsZone.id
        }
      }
    ]
  }
}

output apimResourceId string = apim.id
output apimPrincipalId string = apim.identity.principalId
output gatewayUrl string = 'https://${apimServiceName}.azure-api.net'
output databricksMcpUrl string = 'https://${apimServiceName}.azure-api.net/databricks-mcp/mcp'
output genieMcpUrl string = 'https://${apimServiceName}.azure-api.net/databricks-genie-mcp/mcp'
output privateEndpointResourceId string = apimPrivateEndpoint.id
output publicNetworkAccessState string = publicNetworkAccess
