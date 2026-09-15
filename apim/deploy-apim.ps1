<#
.SYNOPSIS
  Deploys the Databricks + Genie APIs (and product) into the existing APIM
  instance via apim/main.bicep.

.EXAMPLE
  ./apim/deploy-apim.ps1 -WorkspaceUrl "https://adb-123.11.azuredatabricks.net" -WarehouseId "abc123" -GenieSpaceId "01ef..."
#>
[CmdletBinding()]
param(
  [string] $ConfigPath = (Join-Path $PSScriptRoot '../config/deployment.json'),
  [string] $SubscriptionId,
  [string] $ResourceGroup,
  [string] $ApimName,
  [string] $WorkspaceUrl,
  [string] $WarehouseId,
  [string] $GenieSpaceId,
  [string] $DeploymentName
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot '../scripts/config.ps1')

$config = Get-DeploymentConfig -Path $ConfigPath
$SubscriptionId = Get-ConfigValue -Config $config -Path 'azure.subscriptionId' -Override $SubscriptionId
$ResourceGroup = Get-ConfigValue -Config $config -Path 'azure.resourceGroup' -Override $ResourceGroup
$ApimName = Get-ConfigValue -Config $config -Path 'apim.serviceName' -Override $ApimName
$WorkspaceUrl = Get-ConfigValue -Config $config -Path 'databricks.workspaceUrl' -Override $WorkspaceUrl
$WarehouseId = Get-ConfigValue -Config $config -Path 'databricks.warehouseId' -Override $WarehouseId
if ([string]::IsNullOrWhiteSpace($DeploymentName)) {
  $DeploymentName = "$ApimName-apis-$(Get-Date -Format yyyyMMddHHmmss)"
}

$bicep = Join-Path $PSScriptRoot "main.bicep"

Write-Host "Deploying APIM APIs to $ApimName ..." -ForegroundColor Cyan
az deployment group create `
  --subscription $SubscriptionId `
  --resource-group $ResourceGroup `
  --name $DeploymentName `
  --template-file $bicep `
  --parameters apimServiceName=$ApimName `
  databricksWorkspaceUrl=$WorkspaceUrl `
  databricksWarehouseId=$WarehouseId `
  genieSpaceId=$GenieSpaceId `
  --query "properties.outputs" -o json

Write-Host "`nDone. Grant the APIM managed identity access in Databricks (see docs/api-calls.md)." -ForegroundColor Green
