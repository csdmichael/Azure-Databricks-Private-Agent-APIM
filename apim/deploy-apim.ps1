<#
.SYNOPSIS
  Deploys the Databricks + Genie APIs (and product) into the existing APIM
  instance via apim/main.bicep.

.EXAMPLE
  ./apim/deploy-apim.ps1 -WorkspaceUrl "https://adb-123.11.azuredatabricks.net" -WarehouseId "abc123" -GenieSpaceId "01ef..."
#>
[CmdletBinding()]
param(
  [string] $ResourceGroup = "ai-myaacoub",
  [string] $ApimName = "ai-gateway-apim-poc-my",
  [Parameter(Mandatory = $true)] [string] $WorkspaceUrl,
  [Parameter(Mandatory = $true)] [string] $WarehouseId,
  [string] $GenieSpaceId = ""
)

$ErrorActionPreference = "Stop"
$bicep = Join-Path $PSScriptRoot "main.bicep"

Write-Host "Deploying APIM APIs to $ApimName ..." -ForegroundColor Cyan
az deployment group create `
  --resource-group $ResourceGroup `
  --name "databricks-apim-$(Get-Date -Format yyyyMMddHHmmss)" `
  --template-file $bicep `
  --parameters apimServiceName=$ApimName `
  databricksWorkspaceUrl=$WorkspaceUrl `
  databricksWarehouseId=$WarehouseId `
  genieSpaceId=$GenieSpaceId `
  --query "properties.outputs" -o json

Write-Host "`nDone. Grant the APIM managed identity access in Databricks (see docs/api-calls.md)." -ForegroundColor Green
