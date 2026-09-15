@description('Existing Databricks virtual network created by the Terraform layer.')
param databricksVnetName string

@description('Primary Power Platform region, matching the environment geo.')
param primaryRegion string

@description('Secondary Power Platform region of the same region pair.')
param secondaryRegion string

@description('Power Platform virtual network name in the primary region.')
param primaryVnetName string

@description('Power Platform virtual network name in the secondary region.')
param secondaryVnetName string

@description('Resource tags applied to DNS links created by this deployment.')
param tags object

var databricksPrivateDnsZoneName = 'privatelink.azuredatabricks.net'

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
