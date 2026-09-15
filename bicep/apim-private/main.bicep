@description('Globally unique API Management service name.')
param apimServiceName string

@description('Azure region for the API Management service and its dedicated virtual network.')
param location string

@description('API Management publisher display name.')
param publisherName string

@description('API Management publisher email address.')
param publisherEmail string

@description('Existing Databricks virtual network created by the Terraform layer.')
param databricksVnetName string

@description('Name of the peering from the API Management virtual network to the Databricks virtual network.')
param apimToDatabricksPeeringName string

@description('Name of the peering from the Databricks virtual network to the API Management virtual network.')
param databricksToApimPeeringName string

@description('Address space for the API Management virtual network.')
param apimVnetCidr string

@description('Subnet name for API Management v2 outbound virtual network integration.')
param integrationSubnetName string

@description('Subnet delegated to Microsoft.Web/serverFarms for API Management v2 outbound VNet integration.')
param integrationSubnetCidr string

@description('Subnet name for the API Management gateway private endpoint.')
param privateEndpointSubnetName string

@description('Subnet that hosts the API Management gateway private endpoint.')
param privateEndpointSubnetCidr string

@description('API Management service SKU name.')
param apimSkuName string

@description('API Management service capacity.')
@minValue(1)
param apimCapacity int

@description('Public ingress state. Deploy with Enabled, then redeploy with Disabled after the private endpoint is validated.')
@allowed([
  'Enabled'
  'Disabled'
])
param publicNetworkAccess string

@description('Resource tags applied to resources created by this deployment.')
param tags object

var apimVnetName = '${apimServiceName}-vnet'
var databricksPrivateDnsZoneName = 'privatelink.azuredatabricks.net'
var apimPrivateDnsZoneName = 'privatelink.azure-api.net'

resource databricksVnet 'Microsoft.Network/virtualNetworks@2024-05-01' existing = {
  name: databricksVnetName
}

resource databricksPrivateDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' existing = {
  name: databricksPrivateDnsZoneName
}

resource apimPrivateDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: apimPrivateDnsZoneName
  location: 'global'
  tags: tags
}

resource integrationNsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: '${apimServiceName}-integration-nsg'
  location: location
  tags: tags
  properties: {
    securityRules: []
  }
}

resource privateEndpointNsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: '${apimServiceName}-private-endpoints-nsg'
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
        apimVnetCidr
      ]
    }
  }
}

resource integrationSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' = {
  parent: apimVnet
  name: integrationSubnetName
  properties: {
    addressPrefix: integrationSubnetCidr
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
    addressPrefix: privateEndpointSubnetCidr
    networkSecurityGroup: {
      id: privateEndpointNsg.id
    }
    privateEndpointNetworkPolicies: 'Disabled'
  }
  dependsOn: [
    integrationSubnet
  ]
}

// Global peering between the API Management and Databricks virtual networks.
resource apimToDatabricksPeering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-05-01' = {
  parent: apimVnet
  name: apimToDatabricksPeeringName
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
    privateEndpointSubnet
  ]
}

resource databricksToApimPeering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-05-01' = {
  parent: databricksVnet
  name: databricksToApimPeeringName
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
    privateEndpointSubnet
  ]
}

// APIM resolves the Databricks private endpoint privately.
resource databricksDnsLinkToApimVnet 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
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

resource apimDnsLinkToApimVnet 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
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

resource apimDnsLinkToDatabricksVnet 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
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
    name: apimSkuName
    capacity: apimCapacity
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

output apimServiceName string = apim.name
output apimResourceId string = apim.id
output apimPrincipalId string = apim.identity.principalId
output apimVnetName string = apimVnet.name
output apimVnetResourceId string = apimVnet.id
output apimPrivateDnsZoneName string = apimPrivateDnsZone.name
output gatewayUrl string = 'https://${apimServiceName}.azure-api.net'
output privateEndpointResourceId string = apimPrivateEndpoint.id
output publicNetworkAccessState string = publicNetworkAccess
