using './main.bicep'

param databricksVnetName = 'caldova-dbx-vnet-westus2'
param primaryRegion = 'canadacentral'
param secondaryRegion = 'canadaeast'
param primaryVnetName = 'caldova-pp-vnet-canadacentral'
param secondaryVnetName = 'caldova-pp-vnet-canadaeast'
param tags = {
  project: 'caldova-databricks-apim-private'
  environment: 'caldova'
  managed_by: 'bicep'
}
