@description('Azure region for the analytics data resources.')
param location string

@description('Existing showcase web app name.')
param webAppName string

@description('Managed identity principal ID of the showcase web app.')
param webPrincipalId string

@description('Microsoft Entra application client ID used by App Service authentication.')
param authClientId string

@description('Microsoft Entra tenant ID used by App Service authentication.')
param tenantId string

@description('Prefix for the generated Cosmos DB account name. The resource group hash is appended.')
@minLength(3)
@maxLength(30)
param cosmosNamePrefix string

@description('Existing virtual network used by the showcase web app.')
param vnetName string

@description('Existing private endpoint subnet name.')
param privateEndpointSubnetName string

@description('Web app virtual network integration subnet name.')
param integrationSubnetName string

@description('Address prefix for the web app integration subnet.')
param integrationSubnetCidr string

@description('Cosmos DB SQL database name.')
param cosmosDatabaseName string

@description('Cosmos DB SQL container name.')
param cosmosContainerName string

@description('Default item time-to-live in seconds for analytics records.')
@minValue(-1)
param analyticsTtlSeconds int

@description('Cosmos DB default consistency level.')
param cosmosConsistencyLevel string

@description('Whether the Cosmos DB write region is zone redundant.')
param cosmosZoneRedundant bool

@description('Periodic backup interval in minutes.')
@minValue(1)
param backupIntervalInMinutes int

@description('Periodic backup retention in hours.')
@minValue(1)
param backupRetentionInHours int

@description('Backup storage redundancy mode.')
param backupStorageRedundancy string

var cosmosName = '${cosmosNamePrefix}-${uniqueString(resourceGroup().id)}'

resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' existing = { name: vnetName }
resource privateSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' existing = {
  parent: vnet
  name: privateEndpointSubnetName
}
resource integrationSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' = {
  parent: vnet
  name: integrationSubnetName
  properties: {
    addressPrefix: integrationSubnetCidr
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
    locations: [{ locationName: location, failoverPriority: 0, isZoneRedundant: cosmosZoneRedundant }]
    consistencyPolicy: { defaultConsistencyLevel: cosmosConsistencyLevel }
    publicNetworkAccess: 'Disabled'
    disableLocalAuth: true
    minimalTlsVersion: 'Tls12'
    backupPolicy: {
      type: 'Periodic'
      periodicModeProperties: {
        backupIntervalInMinutes: backupIntervalInMinutes
        backupRetentionIntervalInHours: backupRetentionInHours
        backupStorageRedundancy: backupStorageRedundancy
      }
    }
  }
}
resource database 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2024-05-15' = {
  parent: cosmos
  name: cosmosDatabaseName
  properties: { resource: { id: cosmosDatabaseName } }
}
resource visits 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2024-05-15' = {
  parent: database
  name: cosmosContainerName
  properties: {
    resource: {
      id: cosmosContainerName
      partitionKey: { paths: ['/day'], kind: 'Hash', version: 2 }
      defaultTtl: analyticsTtlSeconds
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
    scope: '${cosmos.id}/dbs/${database.name}'
  }
}
resource zone 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: 'privatelink.documents.azure.com'
  location: 'global'
}
resource dnsLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: zone
  name: cosmosDatabaseName
  location: 'global'
  properties: { registrationEnabled: false, virtualNetwork: { id: vnet.id } }
}
resource endpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: '${cosmosDatabaseName}-cosmos-pe'
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
          openIdIssuer: '${environment().authentication.loginEndpoint}${tenantId}/v2.0'
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
