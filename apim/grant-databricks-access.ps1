<#
.SYNOPSIS
  Grants the APIM system-assigned managed identity access to the Databricks
  workspace so APIM can query it on behalf of agents:
    1. Adds the MI as a workspace service principal (SCIM).
    2. Grants CAN_USE on the SQL warehouse.
    3. Grants USE CATALOG / USE SCHEMA / SELECT on the selected schema.

  Run as a Databricks workspace admin (the identity that created the workspace).

.EXAMPLE
  ./apim/grant-databricks-access.ps1 -WorkspaceUrl "https://adb-123.11.azuredatabricks.net" -WarehouseId "abc123"
#>
[CmdletBinding()]
param(
  [string] $ConfigPath = (Join-Path $PSScriptRoot '../config/deployment.json'),
  [string] $SubscriptionId,
  [string] $TenantId,
  [string] $WorkspaceUrl,
  [string] $WarehouseId,
  [string] $ResourceGroup,
  [string] $ApimName,
  [string] $Catalog,
  [string] $Schema,
  [Nullable[int]] $SqlWaitTimeoutSeconds,
  [int] $SqlPollIntervalSeconds = 2
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot '../scripts/config.ps1')

$config = Get-DeploymentConfig -Path $ConfigPath
$SubscriptionId = Get-ConfigValue -Config $config -Path 'azure.subscriptionId' -Override $SubscriptionId
$TenantId = Get-ConfigValue -Config $config -Path 'azure.tenantId' -Override $TenantId
$WorkspaceUrl = (Get-ConfigValue -Config $config -Path 'databricks.workspaceUrl' -Override $WorkspaceUrl).TrimEnd('/')
$WarehouseId = Get-ConfigValue -Config $config -Path 'databricks.warehouseId' -Override $WarehouseId
$ResourceGroup = Get-ConfigValue -Config $config -Path 'azure.resourceGroup' -Override $ResourceGroup
$ApimName = Get-ConfigValue -Config $config -Path 'apim.serviceName' -Override $ApimName
$Catalog = Get-ConfigValue -Config $config -Path 'databricks.catalog' -Override $Catalog
$Schema = Get-ConfigValue -Config $config -Path 'databricks.schema' -Override $Schema
$SqlWaitTimeoutSeconds = [int](Get-ConfigValue -Config $config -Path 'databricks.sqlWaitTimeoutSeconds' -Override $SqlWaitTimeoutSeconds)

# Databricks is a fixed Microsoft audience ID, not a deployment resource ID.
$DatabricksResourceId = "2ff814a6-3304-4ab8-85cb-cd0e6f879c1d"

Write-Host "Resolving APIM managed identity..." -ForegroundColor Cyan
$context = az account show -o json | ConvertFrom-Json
if ($LASTEXITCODE -ne 0 -or $context.id -ne $SubscriptionId -or $context.tenantId -ne $TenantId) { throw 'Select the configured Azure subscription and tenant first.' }
$principalId = az apim show -g $ResourceGroup -n $ApimName --subscription $SubscriptionId --query identity.principalId -o tsv
if (-not $principalId) { throw "APIM $ApimName has no system-assigned managed identity. Enable it first: az apim update -g $ResourceGroup -n $ApimName --set identity.type=SystemAssigned" }
$appId = az ad sp show --id $principalId --query appId -o tsv
Write-Host "  MI principalId=$principalId appId=$appId" -ForegroundColor Green

$token = az account get-access-token --resource $DatabricksResourceId --query accessToken -o tsv
$headers = @{ Authorization = "Bearer $token"; "Content-Type" = "application/json" }

# 1) Add service principal to the workspace (idempotent)
Write-Host "Adding MI as workspace service principal..." -ForegroundColor Cyan
$spBody = @{
  schemas       = @("urn:ietf:params:scim:schemas:core:2.0:ServicePrincipal")
  applicationId = $appId
  displayName   = $ApimName
  entitlements  = @(@{ value = "workspace-access" }, @{ value = "databricks-sql-access" })
} | ConvertTo-Json -Depth 6
try {
  Invoke-RestMethod -Method POST -Uri "$WorkspaceUrl/api/2.0/preview/scim/v2/ServicePrincipals" -Headers $headers -Body $spBody | Out-Null
  Write-Host "  Added." -ForegroundColor Green
}
catch {
  if ($_.Exception.Response.StatusCode.value__ -eq 409) { Write-Host "  Already present." -ForegroundColor DarkGray }
  else { throw }
}

# 2) Grant CAN_USE on the warehouse (PATCH = add, keep existing ACL)
Write-Host "Granting CAN_USE on warehouse $WarehouseId..." -ForegroundColor Cyan
$permBody = @{ access_control_list = @(@{ service_principal_name = $appId; permission_level = "CAN_USE" }) } | ConvertTo-Json -Depth 6
Invoke-RestMethod -Method PATCH -Uri "$WorkspaceUrl/api/2.0/permissions/warehouses/$WarehouseId" -Headers $headers -Body $permBody | Out-Null
Write-Host "  Granted." -ForegroundColor Green

# 3) Grant Unity Catalog privileges via SQL
Write-Host "Granting catalog/schema/select privileges..." -ForegroundColor Cyan
$grants = @(
  "GRANT USE CATALOG ON CATALOG $Catalog TO ``$appId``",
  "GRANT USE SCHEMA ON SCHEMA $Catalog.$Schema TO ``$appId``",
  "GRANT SELECT ON SCHEMA $Catalog.$Schema TO ``$appId``"
)
foreach ($g in $grants) {
  $body = @{ warehouse_id = $WarehouseId; statement = $g; wait_timeout = "${SqlWaitTimeoutSeconds}s"; on_wait_timeout = "CONTINUE" } | ConvertTo-Json
  $r = Invoke-RestMethod -Method POST -Uri "$WorkspaceUrl/api/2.0/sql/statements" -Headers $headers -Body $body
  $id = $r.statement_id
  while ($r.status.state -in @("PENDING", "RUNNING")) { Start-Sleep -Seconds $SqlPollIntervalSeconds; $r = Invoke-RestMethod -Method GET -Uri "$WorkspaceUrl/api/2.0/sql/statements/$id" -Headers $headers }
  if ($r.status.state -ne "SUCCEEDED") { throw "Grant failed: $($r.status.error.message)" }
  Write-Host "  OK: $g" -ForegroundColor Green
}

Write-Host "`nAPIM managed identity ($appId) can now query Databricks." -ForegroundColor Green
