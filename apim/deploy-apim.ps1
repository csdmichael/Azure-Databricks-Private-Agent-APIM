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
  [string] $Catalog,
  [string] $Schema,
  [Nullable[int]] $DatabricksRateLimitCalls,
  [Nullable[int]] $GenieRateLimitCalls,
  [Nullable[int]] $RateLimitRenewalPeriodSeconds,
  [string] $SqlWaitTimeout,
  [string] $DatabricksApiDisplayName,
  [string] $DatabricksApiDescription,
  [string] $GenieApiDisplayName,
  [string] $GenieApiDescription,
  [string] $ProductDisplayName,
  [string] $ProductDescription,
  [string] $SubscriptionDisplayName,
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
$Catalog = Get-ConfigValue -Config $config -Path 'databricks.catalog' -Override $Catalog
$Schema = Get-ConfigValue -Config $config -Path 'databricks.schema' -Override $Schema
$DatabricksRateLimitCalls = [int](Get-ConfigValue -Config $config -Path 'apim.rateLimits.databricksCalls' -Override $DatabricksRateLimitCalls)
$GenieRateLimitCalls = [int](Get-ConfigValue -Config $config -Path 'apim.rateLimits.genieCalls' -Override $GenieRateLimitCalls)
$RateLimitRenewalPeriodSeconds = [int](Get-ConfigValue -Config $config -Path 'apim.rateLimits.renewalPeriodSeconds' -Override $RateLimitRenewalPeriodSeconds)
$SqlWaitTimeout = Get-ConfigValue -Config $config -Path 'apim.timeouts.sqlWait' -Override $SqlWaitTimeout
$DatabricksApiDisplayName = Get-ConfigValue -Config $config -Path 'apim.databricksApiDisplayName' -Override $DatabricksApiDisplayName
$DatabricksApiDescription = Get-ConfigValue -Config $config -Path 'apim.databricksApiDescription' -Override $DatabricksApiDescription
$GenieApiDisplayName = Get-ConfigValue -Config $config -Path 'apim.genieApiDisplayName' -Override $GenieApiDisplayName
$GenieApiDescription = Get-ConfigValue -Config $config -Path 'apim.genieApiDescription' -Override $GenieApiDescription
$ProductDisplayName = Get-ConfigValue -Config $config -Path 'apim.productDisplayName' -Override $ProductDisplayName
$ProductDescription = Get-ConfigValue -Config $config -Path 'apim.productDescription' -Override $ProductDescription
$SubscriptionDisplayName = Get-ConfigValue -Config $config -Path 'apim.subscriptionDisplayName' -Override $SubscriptionDisplayName
if ([string]::IsNullOrWhiteSpace($GenieSpaceId)) { $GenieSpaceId = $env:DATABRICKS_GENIE_SPACE_ID }
if ([string]::IsNullOrWhiteSpace($GenieSpaceId)) {
  throw 'Pass -GenieSpaceId or set DATABRICKS_GENIE_SPACE_ID.'
}
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
  databricksCatalog=$Catalog `
  databricksSchema=$Schema `
  genieSpaceId=$GenieSpaceId `
  databricksRateLimitCalls=$DatabricksRateLimitCalls `
  genieRateLimitCalls=$GenieRateLimitCalls `
  rateLimitRenewalPeriodSeconds=$RateLimitRenewalPeriodSeconds `
  sqlWaitTimeout=$SqlWaitTimeout `
  databricksApiDisplayName=$DatabricksApiDisplayName `
  databricksApiDescription=$DatabricksApiDescription `
  genieApiDisplayName=$GenieApiDisplayName `
  genieApiDescription=$GenieApiDescription `
  productDisplayName=$ProductDisplayName `
  productDescription=$ProductDescription `
  subscriptionDisplayName=$SubscriptionDisplayName `
  --query "properties.outputs" -o json

Write-Host "`nDone. Grant the APIM managed identity access in Databricks (see docs/api-calls.md)." -ForegroundColor Green
