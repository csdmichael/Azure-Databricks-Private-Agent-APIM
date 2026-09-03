@description('Name of the existing private API Management service whose VNet acts as the hub.')
param apimServiceName string = 'ai-gateway-apim-poc-my2'

@description('Name of the existing API Management private DNS zone.')
param apimPrivateDnsZoneName string = 'privatelink.azure-api.net'

@description('Name of the Power Platform virtual network in East US.')
param eastVnetName string = 'power-platform-vnet-eastus'

@description('Name of the Power Platform virtual network in West US.')
param westVnetName string = 'power-platform-vnet-westus'

@description('Name of the dedicated Power Platform subnet in each regional virtual network.')
param powerPlatformSubnetName string = 'power-platform-subnet'

@description('Name of the U.S. Power Platform network-injection enterprise policy.')
param enterprisePolicyName string = 'power-platform-network-injection-us'

param tags object = {
  environment: 'poc'
  managed_by: 'bicep'
  workload: 'power-platform-private-apim'
}

var apimVnetName = '${apimServiceName}-vnet'

resource apimVnet 'Microsoft.Network/virtualNetworks@2024-05-01' existing = {
  name: apimVnetName
}

resource apimPrivateDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' existing = {
  name: apimPrivateDnsZoneName
}

resource eastPowerPlatformVnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: eastVnetName
  location: 'eastus'
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.182.0.0/16'
      ]
    }
  }
}

resource eastPowerPlatformSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' = {
  parent: eastPowerPlatformVnet
  name: powerPlatformSubnetName
  properties: {
    addressPrefix: '10.182.0.0/24'
    delegations: [
      {
        name: 'power-platform-enterprise-policies'
        properties: {
          serviceName: 'Microsoft.PowerPlatform/enterprisePolicies'
        }
      }
    ]
  }
}

resource westPowerPlatformVnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: westVnetName
  location: 'westus'
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.183.0.0/16'
      ]
    }
  }
}

resource westPowerPlatformSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' = {
  parent: westPowerPlatformVnet
  name: powerPlatformSubnetName
  properties: {
    addressPrefix: '10.183.0.0/24'
    delegations: [
      {
        name: 'power-platform-enterprise-policies'
        properties: {
          serviceName: 'Microsoft.PowerPlatform/enterprisePolicies'
        }
      }
    ]
  }
}

resource apimToPowerPlatformEastPeering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-05-01' = {
  parent: apimVnet
  name: 'apim-to-power-platform-eastus'
  properties: {
    allowForwardedTraffic: true
    allowGatewayTransit: false
    allowVirtualNetworkAccess: true
    remoteVirtualNetwork: {
      id: eastPowerPlatformVnet.id
    }
    useRemoteGateways: false
  }
  dependsOn: [
    eastPowerPlatformSubnet
  ]
}

resource powerPlatformEastToApimPeering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-05-01' = {
  parent: eastPowerPlatformVnet
  name: 'power-platform-eastus-to-apim'
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
    eastPowerPlatformSubnet
  ]
}

resource apimToPowerPlatformWestPeering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-05-01' = {
  parent: apimVnet
  name: 'apim-to-power-platform-westus'
  properties: {
    allowForwardedTraffic: true
    allowGatewayTransit: false
    allowVirtualNetworkAccess: true
    remoteVirtualNetwork: {
      id: westPowerPlatformVnet.id
    }
    useRemoteGateways: false
  }
  dependsOn: [
    westPowerPlatformSubnet
  ]
}

resource powerPlatformWestToApimPeering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-05-01' = {
  parent: westPowerPlatformVnet
  name: 'power-platform-westus-to-apim'
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
    westPowerPlatformSubnet
  ]
}

resource apimDnsLinkToPowerPlatformEast 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: apimPrivateDnsZone
  name: 'power-platform-eastus-apim-dns-link'
  location: 'global'
  tags: tags
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: eastPowerPlatformVnet.id
    }
  }
}

resource apimDnsLinkToPowerPlatformWest 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: apimPrivateDnsZone
  name: 'power-platform-westus-apim-dns-link'
  location: 'global'
  tags: tags
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: westPowerPlatformVnet.id
    }
  }
}

resource networkInjectionPolicy 'Microsoft.PowerPlatform/enterprisePolicies@2020-10-30-preview' = {
  name: enterprisePolicyName
  location: 'unitedstates'
  kind: 'NetworkInjection'
  tags: tags
  properties: {
    networkInjection: {
      virtualNetworks: [
        {
          id: eastPowerPlatformVnet.id
          subnet: {
            name: eastPowerPlatformSubnet.name
          }
        }
        {
          id: westPowerPlatformVnet.id
          subnet: {
            name: westPowerPlatformSubnet.name
          }
        }
      ]
    }
  }
}

output apimVnetResourceId string = apimVnet.id
output apimPrivateDnsZoneResourceId string = apimPrivateDnsZone.id
output eastVnetResourceId string = eastPowerPlatformVnet.id
output eastSubnetResourceId string = eastPowerPlatformSubnet.id
output westVnetResourceId string = westPowerPlatformVnet.id
output westSubnetResourceId string = westPowerPlatformSubnet.id
output apimToEastPeeringResourceId string = apimToPowerPlatformEastPeering.id
output eastToApimPeeringResourceId string = powerPlatformEastToApimPeering.id
output apimToWestPeeringResourceId string = apimToPowerPlatformWestPeering.id
output westToApimPeeringResourceId string = powerPlatformWestToApimPeering.id
output eastDnsLinkResourceId string = apimDnsLinkToPowerPlatformEast.id
output westDnsLinkResourceId string = apimDnsLinkToPowerPlatformWest.id
output enterprisePolicyResourceId string = networkInjectionPolicy.id
