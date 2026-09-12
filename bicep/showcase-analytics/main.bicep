param location string = 'westus2'
param webAppName string = 'caldova-databricks-showcase'
param webPrincipalId string
param authClientId string
param tenantId string = tenant().tenantId
param cosmosName string = 'caldova-showcase-${uniqueString(resourceGroup().id)}'
param vnetName string = 'caldova-dbx-vnet-westus2'

resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' existing = { name: vnetName }
resource privateSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' existing = {
  parent: vnet
  name: 'private-endpoints'
}
resource integrationSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' = {
  parent: vnet
  name: 'genie-obo-integration'
  properties: {
    addressPrefix: '10.190.5.0/24'
    delegations: [{ name: 'web', properties: { serviceName: 'Microsoft.Web/serverFarms' } }]
  }
}
resource cosmos 'Microsoft.DocumentDB/databaseAccounts@2024-05-15' = {
  name: cosmosName
  location: location
  kind: 'GlobalDocumentDB'
  properties: {
    databaseAccountOfferType: 'Standard'
    capabilities: [{ name: 'EnableServerless' }]
    locations: [{ locationName: location, failoverPriority: 0, isZoneRedundant: false }]
    consistencyPolicy: { defaultConsistencyLevel: 'Session' }
    publicNetworkAccess: 'Disabled'
    disableLocalAuth: true
    minimalTlsVersion: 'Tls12'
    backupPolicy: {
      type: 'Periodic'
      periodicModeProperties: { backupIntervalInMinutes: 480, backupRetentionIntervalInHours: 24, backupStorageRedundancy: 'Local' }
    }
  }
}
resource database 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2024-05-15' = {
  parent: cosmos
  name: 'showcase-analytics'
  properties: { resource: { id: 'showcase-analytics' } }
}
resource visits 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2024-05-15' = {
  parent: database
  name: 'visits'
  properties: {
    resource: {
      id: 'visits'
      partitionKey: { paths: ['/day'], kind: 'Hash', version: 2 }
      defaultTtl: 7776000
      indexingPolicy: { automatic: true, indexingMode: 'consistent', includedPaths: [{ path: '/day/?' }], excludedPaths: [{ path: '/*' }] }
    }
  }
}
resource dataRole 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2024-05-15' = {
  parent: cosmos
  name: guid(cosmos.id, webPrincipalId, 'showcase-data')
  properties: {
    principalId: webPrincipalId
    roleDefinitionId: '${cosmos.id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002'
    scope: '${cosmos.id}/dbs/showcase-analytics'
  }
  dependsOn: [database]
}
resource zone 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: 'privatelink.documents.azure.com'
  location: 'global'
}
resource dnsLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: zone
  name: 'showcase-analytics'
  location: 'global'
  properties: { registrationEnabled: false, virtualNetwork: { id: vnet.id } }
}
resource endpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: 'showcase-analytics-cosmos-pe'
  location: location
  properties: {
    subnet: { id: privateSubnet.id }
    privateLinkServiceConnections: [{ name: 'cosmos', properties: { privateLinkServiceId: cosmos.id, groupIds: ['Sql'] } }]
  }
}
resource dnsGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: endpoint
  name: 'default'
  properties: { privateDnsZoneConfigs: [{ name: 'cosmos', properties: { privateDnsZoneId: zone.id } }] }
}
resource site 'Microsoft.Web/sites@2023-12-01' existing = { name: webAppName }
resource auth 'Microsoft.Web/sites/config@2023-12-01' = {
  parent: site
  name: 'authsettingsV2'
  properties: {
    platform: { enabled: true, runtimeVersion: '~1' }
    globalValidation: { requireAuthentication: false, unauthenticatedClientAction: 'AllowAnonymous' }
    identityProviders: {
      azureActiveDirectory: {
        enabled: true
        registration: {
          clientId: authClientId
          clientSecretSettingName: 'SHOWCASE_AUTH_CLIENT_SECRET'
          openIdIssuer: 'https://login.microsoftonline.com/${tenantId}/v2.0'
        }
        validation: { allowedAudiences: [authClientId, 'api://${authClientId}'] }
      }
    }
    login: { tokenStore: { enabled: true } }
    httpSettings: { requireHttps: true }
  }
}
output cosmosEndpoint string = cosmos.properties.documentEndpoint
output cosmosAccountName string = cosmos.name
output subnetId string = integrationSubnet.id
