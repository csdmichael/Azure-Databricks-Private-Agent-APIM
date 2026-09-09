@description('Databricks virtual network in West US 2 created by the Terraform layer.')
param databricksVnetName string = 'caldova-dbx-vnet-westus2'

@description('Private DNS zone that resolves the Databricks private endpoints.')
param databricksPrivateDnsZoneName string = 'privatelink.azuredatabricks.net'

@description('Primary Power Platform region, matching the environment geo.')
param primaryRegion string = 'canadacentral'

@description('Secondary Power Platform region of the same region pair.')
param secondaryRegion string = 'canadaeast'

@description('Power Platform virtual network name in the primary region.')
param primaryVnetName string = 'caldova-pp-vnet-${primaryRegion}'

@description('Power Platform virtual network name in the secondary region.')
param secondaryVnetName string = 'caldova-pp-vnet-${secondaryRegion}'

param tags object = {
  project: 'caldova-databricks-apim-private'
  environment: 'caldova'
  managed_by: 'bicep'
}

resource databricksVnet 'Microsoft.Network/virtualNetworks@2024-05-01' existing = {
  name: databricksVnetName
}

resource databricksPrivateDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' existing = {
  name: databricksPrivateDnsZoneName
}

resource primaryVnet 'Microsoft.Network/virtualNetworks@2024-05-01' existing = {
  name: primaryVnetName
}

resource secondaryVnet 'Microsoft.Network/virtualNetworks@2024-05-01' existing = {
  name: secondaryVnetName
}

// Peering is not transitive: reaching Databricks without traversing APIM needs
// a direct peering from each Power Platform VNet to the Databricks VNet.
resource primaryToDatabricks 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-05-01' = {
  parent: primaryVnet
  name: 'power-platform-${primaryRegion}-to-databricks'
  properties: {
    allowForwardedTraffic: true
    allowGatewayTransit: false
    allowVirtualNetworkAccess: true
    remoteVirtualNetwork: {
      id: databricksVnet.id
    }
    useRemoteGateways: false
  }
}

resource databricksToPrimary 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-05-01' = {
  parent: databricksVnet
  name: 'databricks-to-power-platform-${primaryRegion}'
  properties: {
    allowForwardedTraffic: true
    allowGatewayTransit: false
    allowVirtualNetworkAccess: true
    remoteVirtualNetwork: {
      id: primaryVnet.id
    }
    useRemoteGateways: false
  }
}

resource secondaryToDatabricks 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-05-01' = {
  parent: secondaryVnet
  name: 'power-platform-${secondaryRegion}-to-databricks'
  properties: {
    allowForwardedTraffic: true
    allowGatewayTransit: false
    allowVirtualNetworkAccess: true
    remoteVirtualNetwork: {
      id: databricksVnet.id
    }
    useRemoteGateways: false
  }
}

// Serialized behind the first peering because both write to the Databricks VNet.
resource databricksToSecondary 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-05-01' = {
  parent: databricksVnet
  name: 'databricks-to-power-platform-${secondaryRegion}'
  properties: {
    allowForwardedTraffic: true
    allowGatewayTransit: false
    allowVirtualNetworkAccess: true
    remoteVirtualNetwork: {
      id: secondaryVnet.id
    }
    useRemoteGateways: false
  }
  dependsOn: [
    databricksToPrimary
  ]
}

// Without these links the delegated subnets resolve the workspace to its public
// address and the request is rejected by the private-only workspace.
resource databricksDnsLinkToPrimary 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: databricksPrivateDnsZone
  name: 'power-platform-${primaryRegion}-databricks-dns-link'
  location: 'global'
  tags: tags
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: primaryVnet.id
    }
  }
}

resource databricksDnsLinkToSecondary 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: databricksPrivateDnsZone
  name: 'power-platform-${secondaryRegion}-databricks-dns-link'
  location: 'global'
  tags: tags
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: secondaryVnet.id
    }
  }
}

output primaryPeeringId string = primaryToDatabricks.id
output secondaryPeeringId string = secondaryToDatabricks.id
output primaryDnsLinkId string = databricksDnsLinkToPrimary.id
output secondaryDnsLinkId string = databricksDnsLinkToSecondary.id
