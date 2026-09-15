using './main.bicep'

param apimServiceName = 'caldova-apim-westus'
param location = 'westus'
param publisherName = 'Caldova AI Gateway'
param publisherEmail = 'admin@Caldova37587778.onmicrosoft.com'
param databricksVnetName = 'caldova-dbx-vnet-westus2'
param apimToDatabricksPeeringName = 'apim-to-databricks-westus2'
param databricksToApimPeeringName = 'databricks-westus2-to-apim'
param apimVnetCidr = '10.191.0.0/16'
param integrationSubnetName = 'apim-outbound-integration'
param integrationSubnetCidr = '10.191.0.0/24'
param privateEndpointSubnetName = 'private-endpoints'
param privateEndpointSubnetCidr = '10.191.1.0/24'
param apimSkuName = 'StandardV2'
param apimCapacity = 1
param publicNetworkAccess = 'Enabled'
param tags = {
	project: 'caldova-databricks-apim-private'
	environment: 'caldova'
	managed_by: 'bicep'
}
