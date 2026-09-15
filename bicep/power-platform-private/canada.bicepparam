using './main.bicep'

param apimServiceName = 'caldova-apim-westus'
param primaryRegion = 'canadacentral'
param secondaryRegion = 'canadaeast'
param primaryVnetName = 'caldova-pp-vnet-canadacentral'
param secondaryVnetName = 'caldova-pp-vnet-canadaeast'
param powerPlatformSubnetName = 'power-platform-subnet'
param primaryVnetCidr = '10.194.0.0/16'
param primarySubnetCidr = '10.194.0.0/24'
param secondaryVnetCidr = '10.195.0.0/16'
param secondarySubnetCidr = '10.195.0.0/24'
param policyLocation = 'canada'
param enterprisePolicyName = 'caldova-pp-network-injection-canada'
param tags = {
	project: 'caldova-databricks-apim-private'
	environment: 'caldova'
	managed_by: 'bicep'
}
