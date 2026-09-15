@description('Azure region shared by the Foundry account and agent subnet.')
param location string

@description('Name of the new private Microsoft Foundry account.')
param foundryAccountName string

@description('Inbound public network access for the Foundry portal and data-plane APIs.')
@allowed([
  'Enabled'
  'Disabled'
])
param publicNetworkAccess string

@description('Name of the Foundry project to create.')
param projectName string

@description('Name of the basic Agents capability host.')
param projectCapabilityHostName string

@description('Name of the model deployment used by the migrated agent.')
param modelDeploymentName string

@description('Publisher model name used by the deployment.')
param modelName string

@description('Publisher model version used by the deployment.')
param modelVersion string

@description('Model deployment SKU.')
param modelSkuName string

@description('Model deployment capacity in thousands of tokens per minute.')
param modelCapacity int

@description('Name of the existing virtual network that contains the private APIM endpoint.')
param vnetName string

@description('Name of the peered virtual network that contains the private validation client.')
param clientVnetName string

@description('Name of the existing subnet that hosts private endpoints.')
param privateEndpointSubnetName string

@description('Name of the dedicated subnet used by Foundry Agent Service.')
param agentSubnetName string

@description('Address prefix for the dedicated Foundry Agent Service subnet.')
param agentSubnetPrefix string

param tags object = {
  project: 'caldova-databricks-apim-private'
  environment: 'caldova'
  managed_by: 'bicep'
  component: 'foundry-private'
}

var foundryPrivateDnsZoneNames = [
  'privatelink.cognitiveservices.azure.com'
  'privatelink.openai.azure.com'
  'privatelink.services.ai.azure.com'
]

resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' existing = {
  name: vnetName
}

resource clientVnet 'Microsoft.Network/virtualNetworks@2024-05-01' existing = {
  name: clientVnetName
}

resource privateEndpointSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' existing = {
  parent: vnet
  name: privateEndpointSubnetName
}

resource agentNsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: '${foundryAccountName}-agent-nsg'
  location: location
  tags: tags
  properties: {
    securityRules: []
  }
}

resource agentSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' = {
  parent: vnet
  name: agentSubnetName
  properties: {
    addressPrefix: agentSubnetPrefix
    delegations: [
      {
        name: 'foundry-agent-service'
        properties: {
          serviceName: 'Microsoft.App/environments'
        }
      }
    ]
    networkSecurityGroup: {
      id: agentNsg.id
    }
    privateEndpointNetworkPolicies: 'Disabled'
  }
}

resource foundryAccount 'Microsoft.CognitiveServices/accounts@2026-05-01' = {
  name: foundryAccountName
  location: location
  kind: 'AIServices'
  sku: {
    name: 'S0'
  }
  identity: {
    type: 'SystemAssigned'
  }
  tags: tags
  properties: {
    allowProjectManagement: true
    customSubDomainName: foundryAccountName
    disableLocalAuth: true
    publicNetworkAccess: publicNetworkAccess
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: publicNetworkAccess == 'Enabled' ? 'Allow' : 'Deny'
      ipRules: []
      virtualNetworkRules: []
    }
    networkInjections: [
      {
        scenario: 'agent'
        subnetArmId: agentSubnet.id
        useMicrosoftManagedNetwork: false
      }
    ]
  }
}

resource foundryProject 'Microsoft.CognitiveServices/accounts/projects@2025-06-01' = {
  parent: foundryAccount
  name: projectName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    description: 'Private Foundry project for the Databricks MCP agent'
    displayName: projectName
  }
}

resource modelDeployment 'Microsoft.CognitiveServices/accounts/deployments@2025-06-01' = {
  parent: foundryAccount
  name: modelDeploymentName
  sku: {
    name: modelSkuName
    capacity: modelCapacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: modelName
      version: modelVersion
    }
    versionUpgradeOption: 'OnceNewDefaultVersionAvailable'
  }
}

resource foundryPrivateDnsZones 'Microsoft.Network/privateDnsZones@2024-06-01' = [for zoneName in foundryPrivateDnsZoneNames: {
  name: zoneName
  location: 'global'
  tags: tags
}]

resource foundryPrivateDnsLinks 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = [for (zoneName, index) in foundryPrivateDnsZoneNames: {
  parent: foundryPrivateDnsZones[index]
  name: '${vnetName}-link'
  location: 'global'
  tags: tags
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnet.id
    }
  }
}]

resource foundryClientPrivateDnsLinks 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = [for (zoneName, index) in foundryPrivateDnsZoneNames: {
  parent: foundryPrivateDnsZones[index]
  name: '${clientVnetName}-link'
  location: 'global'
  tags: tags
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: clientVnet.id
    }
  }
}]

resource foundryPrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: '${foundryAccountName}-pe'
  location: location
  tags: tags
  properties: {
    privateLinkServiceConnections: [
      {
        name: '${foundryAccountName}-connection'
        properties: {
          groupIds: [
            'account'
          ]
          privateLinkServiceId: foundryAccount.id
        }
      }
    ]
    subnet: {
      id: privateEndpointSubnet.id
    }
  }
}

resource foundryPrivateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: foundryPrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [for (zoneName, index) in foundryPrivateDnsZoneNames: {
      name: replace(zoneName, '.', '-')
      properties: {
        privateDnsZoneId: foundryPrivateDnsZones[index].id
      }
    }]
  }
}

resource projectCapabilityHost 'Microsoft.CognitiveServices/accounts/projects/capabilityHosts@2025-04-01-preview' = {
  parent: foundryProject
  name: projectCapabilityHostName
  properties: {
    #disable-next-line BCP037
    capabilityHostKind: 'Agents'
  }
  dependsOn: [
    foundryPrivateDnsZoneGroup
    foundryClientPrivateDnsLinks
  ]
}

output foundryAccountId string = foundryAccount.id
output foundryAccountPrincipalId string = foundryAccount.identity.principalId
output foundryProjectId string = foundryProject.id
output foundryProjectPrincipalId string = foundryProject.identity.principalId
output foundryProjectEndpoint string = 'https://${foundryAccountName}.services.ai.azure.com/api/projects/${projectName}'
output agentSubnetId string = agentSubnet.id
output privateEndpointId string = foundryPrivateEndpoint.id
output projectCapabilityHostId string = projectCapabilityHost.id
output modelDeploymentName string = modelDeployment.name
