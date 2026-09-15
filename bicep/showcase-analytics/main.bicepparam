using './main.bicep'

param location = 'westus2'
param webAppName = 'caldova-databricks-showcase'
param webPrincipalId = 'f10124fb-9db1-4a6c-b80a-6164254a4cb6'
param authClientId = '396bfb97-534e-4a67-86d5-494d69a8a2f3'
param tenantId = '12a4b86b-e64c-43f9-af05-d9130a72dfd2'
param cosmosNamePrefix = 'caldova-showcase'
param vnetName = 'caldova-dbx-vnet-westus2'
param privateEndpointSubnetName = 'private-endpoints'
param integrationSubnetName = 'genie-obo-integration'
param integrationSubnetCidr = '10.190.5.0/24'
param cosmosDatabaseName = 'showcase-analytics'
param cosmosContainerName = 'visits'
param analyticsTtlSeconds = 7776000
param cosmosConsistencyLevel = 'Session'
param cosmosZoneRedundant = false
param backupIntervalInMinutes = 480
param backupRetentionInHours = 24
param backupStorageRedundancy = 'Local'
