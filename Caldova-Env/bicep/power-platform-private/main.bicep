@description('Existing private API Management service whose virtual network acts as the hub.')
param apimServiceName string = 'caldova-apim-westus'

@description('Existing API Management virtual network name.')
param apimVnetName string = '${apimServiceName}-vnet'

@description('Existing private DNS zone for the API Management gateway private endpoint.')
param apimPrivateDnsZoneName string = 'privatelink.azure-api.net'

@description('Primary Azure region of the Power Platform region pair, for example eastus or canadacentral.')
param primaryRegion string

@description('Secondary Azure region of the Power Platform region pair, for example westus or canadaeast.')
param secondaryRegion string

@description('Power Platform virtual network name in the primary region.')
param primaryVnetName string = 'caldova-pp-vnet-${primaryRegion}'

@description('Power Platform virtual network name in the secondary region.')
param secondaryVnetName string = 'caldova-pp-vnet-${secondaryRegion}'

@description('Dedicated Power Platform subnet name in each regional virtual network.')
param powerPlatformSubnetName string = 'power-platform-subnet'

@description('Address space for the primary Power Platform virtual network.')
param primaryVnetCidr string

@description('Delegated subnet in the primary region. Must have the same usable address count as the secondary subnet.')
param primarySubnetCidr string

@description('Address space for the secondary Power Platform virtual network.')
param secondaryVnetCidr string

@description('Delegated subnet in the secondary region. Must have the same usable address count as the primary subnet.')
param secondarySubnetCidr string

@description('Power Platform geo of the enterprise policy. Must match the geo of the target environment.')
@allowed([
  'unitedstates'
  'canada'
  'europe'
  'unitedkingdom'
  'asia'
  'australia'
  'japan'
  'india'
  'southamerica'
  'france'
  'germany'
  'switzerland'
  'unitedarabemirates'
  'korea'
  'norway'
  'singapore'
  'southafrica'
  'sweden'
])
param policyLocation string

@description('Network-injection enterprise policy name.')
param enterprisePolicyName string

param tags object = {
  project: 'caldova-databricks-apim-private'
  environment: 'caldova'
  managed_by: 'bicep'
}

resource apimVnet 'Microsoft.Network/virtualNetworks@2024-05-01' existing = {
  name: apimVnetName
}

resource apimPrivateDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' existing = {
  name: apimPrivateDnsZoneName
}

resource primaryVnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: primaryVnetName
  location: primaryRegion
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        primaryVnetCidr
      ]
    }
  }
}

resource primarySubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' = {
  parent: primaryVnet
  name: powerPlatformSubnetName
  properties: {
    addressPrefix: primarySubnetCidr
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

resource secondaryVnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: secondaryVnetName
  location: secondaryRegion
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        secondaryVnetCidr
      ]
    }
  }
}

resource secondarySubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' = {
  parent: secondaryVnet
  name: powerPlatformSubnetName
  properties: {
    addressPrefix: secondarySubnetCidr
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

// Peering is not transitive, so each Power Platform VNet peers directly with APIM.
resource apimToPrimaryPeering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-05-01' = {
  parent: apimVnet
  name: 'apim-to-power-platform-${primaryRegion}'
  properties: {
    allowForwardedTraffic: true
    allowGatewayTransit: false
    allowVirtualNetworkAccess: true
    remoteVirtualNetwork: {
      id: primaryVnet.id
    }
    useRemoteGateways: false
  }
  dependsOn: [
    primarySubnet
  ]
}

resource primaryToApimPeering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-05-01' = {
  parent: primaryVnet
  name: 'power-platform-${primaryRegion}-to-apim'
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
    primarySubnet
  ]
}

resource apimToSecondaryPeering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-05-01' = {
  parent: apimVnet
  name: 'apim-to-power-platform-${secondaryRegion}'
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
    secondarySubnet
    apimToPrimaryPeering
  ]
}

resource secondaryToApimPeering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-05-01' = {
  parent: secondaryVnet
  name: 'power-platform-${secondaryRegion}-to-apim'
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
    secondarySubnet
  ]
}

resource apimDnsLinkToPrimary 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: apimPrivateDnsZone
  name: 'power-platform-${primaryRegion}-apim-dns-link'
  location: 'global'
  tags: tags
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: primaryVnet.id
    }
  }
}

resource apimDnsLinkToSecondary 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: apimPrivateDnsZone
  name: 'power-platform-${secondaryRegion}-apim-dns-link'
  location: 'global'
  tags: tags
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: secondaryVnet.id
    }
  }
}

resource networkInjectionPolicy 'Microsoft.PowerPlatform/enterprisePolicies@2020-10-30-preview' = {
  name: enterprisePolicyName
  location: policyLocation
  kind: 'NetworkInjection'
  tags: tags
  properties: {
    networkInjection: {
      virtualNetworks: [
        {
          id: primaryVnet.id
          subnet: {
            name: primarySubnet.name
          }
        }
        {
          id: secondaryVnet.id
          subnet: {
            name: secondarySubnet.name
          }
        }
      ]
    }
  }
}

output primaryVnetResourceId string = primaryVnet.id
output primarySubnetResourceId string = primarySubnet.id
output secondaryVnetResourceId string = secondaryVnet.id
output secondarySubnetResourceId string = secondarySubnet.id
output enterprisePolicyName string = networkInjectionPolicy.name
output enterprisePolicyResourceId string = networkInjectionPolicy.id
