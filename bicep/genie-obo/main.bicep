param location string = 'westus2'
param functionName string = 'caldova-genie-obo-fn'
param planName string = 'caldova-showcase-plan'
param storageName string = 'genieobo${uniqueString(resourceGroup().id)}'
param vnetName string = 'caldova-dbx-vnet-westus2'
param apimVnetName string = 'caldova-apim-westus-vnet'
param apimName string = 'caldova-apim-westus'
param insightsName string = 'caldova-genie-obo-insights'
param tenantId string = tenant().tenantId
param apiClientId string
param connectorClientId string
param workspaceUrl string = 'https://adb-7405616934814750.10.azuredatabricks.net'

resource plan 'Microsoft.Web/serverfarms@2023-12-01' existing = { name: planName }
resource apim 'Microsoft.ApiManagement/service@2023-09-01-preview' existing = { name: apimName }
resource insights 'Microsoft.Insights/components@2020-02-02' existing = { name: insightsName }
resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' existing = { name: vnetName }
resource apimVnet 'Microsoft.Network/virtualNetworks@2024-05-01' existing = { name: apimVnetName }
resource integration 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' existing = {
  parent: vnet
  name: 'genie-obo-integration'
}
resource privateSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' existing = {
  parent: vnet
  name: 'private-endpoints'
}
resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageName
  location: location
  kind: 'StorageV2'
  sku: { name: 'Standard_LRS' }
  properties: {
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
    defaultToOAuthAuthentication: true
    publicNetworkAccess: 'Disabled'
    networkAcls: { defaultAction: 'Deny', bypass: 'None' }
  }
}
resource blobs 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storage
  name: 'default'
  properties: { deleteRetentionPolicy: { enabled: true, days: 7 } }
}
resource packages 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobs
  name: 'deployments'
  properties: { publicAccess: 'None' }
}
resource blobZone 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: 'privatelink.blob.${environment().suffixes.storage}'
  location: 'global'
}
resource blobLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: blobZone
  name: 'genie-obo-databricks'
  location: 'global'
  properties: { registrationEnabled: false, virtualNetwork: { id: vnet.id } }
}
resource blobEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: '${functionName}-blob-pe'
  location: location
  properties: {
    subnet: { id: privateSubnet.id }
    privateLinkServiceConnections: [{ name: 'blob', properties: { privateLinkServiceId: storage.id, groupIds: ['blob'] } }]
  }
}
resource blobDns 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: blobEndpoint
  name: 'default'
  properties: { privateDnsZoneConfigs: [{ name: 'blob', properties: { privateDnsZoneId: blobZone.id } }] }
}
resource site 'Microsoft.Web/sites@2023-12-01' = {
  name: functionName
  location: location
  kind: 'functionapp'
  identity: { type: 'SystemAssigned' }
  properties: {
    serverFarmId: plan.id
    httpsOnly: true
    publicNetworkAccess: 'Disabled'
    virtualNetworkSubnetId: integration.id
    siteConfig: {
      alwaysOn: true
      use32BitWorkerProcess: false
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      scmMinTlsVersion: '1.2'
      netFrameworkVersion: 'v8.0'
      appSettings: [
        { name: 'FUNCTIONS_EXTENSION_VERSION', value: '~4' }
        { name: 'FUNCTIONS_WORKER_RUNTIME', value: 'node' }
        { name: 'WEBSITE_NODE_DEFAULT_VERSION', value: '~22' }
        { name: 'WEBSITE_RUN_FROM_PACKAGE', value: '1' }
        { name: 'AzureWebJobsStorage__accountName', value: storage.name }
        { name: 'AzureWebJobsStorage__credential', value: 'managedidentity' }
        { name: 'ENTRA_TENANT_ID', value: tenantId }
        { name: 'ENTRA_API_CLIENT_ID', value: apiClientId }
        { name: 'BROKER_AUDIENCE', value: apiClientId }
        { name: 'APIM_PRINCIPAL_ID', value: apim.identity.principalId }
        { name: 'ALLOWED_CLIENT_IDS', value: connectorClientId }
        { name: 'DATABRICKS_WORKSPACE_URL', value: workspaceUrl }
        { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: insights.properties.ConnectionString }
      ]
    }
  }
}
resource blobOwner 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storage
  name: guid(storage.id, site.id, 'host-blob-owner')
  properties: {
    principalId: site.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b')
  }
}
resource scmPublishing 'Microsoft.Web/sites/basicPublishingCredentialsPolicies@2023-12-01' = {
  parent: site
  name: 'scm'
  properties: { allow: false }
}
resource ftpPublishing 'Microsoft.Web/sites/basicPublishingCredentialsPolicies@2023-12-01' = {
  parent: site
  name: 'ftp'
  properties: { allow: false }
}
resource webZone 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: 'privatelink.azurewebsites.net'
  location: 'global'
}
resource webLinks 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = [for network in [{ name: vnet.name, id: vnet.id }, { name: apimVnet.name, id: apimVnet.id }]: {
  parent: webZone
  name: 'genie-obo-${network.name}'
  location: 'global'
  properties: { registrationEnabled: false, virtualNetwork: { id: network.id } }
}]
resource siteEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: '${functionName}-pe'
  location: location
  properties: {
    subnet: { id: privateSubnet.id }
    privateLinkServiceConnections: [{ name: 'sites', properties: { privateLinkServiceId: site.id, groupIds: ['sites'] } }]
  }
}
resource siteDns 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: siteEndpoint
  name: 'default'
  properties: { privateDnsZoneConfigs: [{ name: 'sites', properties: { privateDnsZoneId: webZone.id } }] }
}
output brokerUrl string = 'https://${site.properties.defaultHostName}/api/exchange'
output functionResourceId string = site.id
output functionPrincipalId string = site.identity.principalId
output storageAccountName string = storage.name
output deploymentContainerId string = packages.id
