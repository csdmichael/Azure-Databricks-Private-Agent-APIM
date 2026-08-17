<#
.SYNOPSIS
  Grants the APIM system-assigned managed identity access to the Databricks
  workspace so APIM can query it on behalf of agents:
    1. Adds the MI as a workspace service principal (SCIM).
    2. Grants CAN_USE on the SQL warehouse.
    3. Grants USE CATALOG / USE SCHEMA / SELECT on the sample data.

  Run as a Databricks workspace admin (the identity that created the workspace).

.EXAMPLE
  ./apim/grant-databricks-access.ps1 -WorkspaceUrl "https://adb-123.11.azuredatabricks.net" -WarehouseId "abc123"
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)] [string] $WorkspaceUrl,
  [Parameter(Mandatory = $true)] [string] $WarehouseId,
  [string] $ResourceGroup = "ai-myaacoub",
  [string] $ApimName = "ai-gateway-apim-poc-my",
  [string] $Catalog = "arrow_semiconductor",
  [string] $Schema = "manufacturing"
)

$ErrorActionPreference = "Stop"
$DatabricksResourceId = "2ff814a6-3304-4ab8-85cb-cd0e6f879c1d"
$WorkspaceUrl = $WorkspaceUrl.TrimEnd("/")

Write-Host "Resolving APIM managed identity..." -ForegroundColor Cyan
$principalId = az apim show -g $ResourceGroup -n $ApimName --query identity.principalId -o tsv
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
  $body = @{ warehouse_id = $WarehouseId; statement = $g; wait_timeout = "30s"; on_wait_timeout = "CONTINUE" } | ConvertTo-Json
  $r = Invoke-RestMethod -Method POST -Uri "$WorkspaceUrl/api/2.0/sql/statements" -Headers $headers -Body $body
  $id = $r.statement_id
  while ($r.status.state -in @("PENDING", "RUNNING")) { Start-Sleep 2; $r = Invoke-RestMethod -Method GET -Uri "$WorkspaceUrl/api/2.0/sql/statements/$id" -Headers $headers }
  if ($r.status.state -ne "SUCCEEDED") { throw "Grant failed: $($r.status.error.message)" }
  Write-Host "  OK: $g" -ForegroundColor Green
}

Write-Host "`nAPIM managed identity ($appId) can now query Databricks." -ForegroundColor Green
