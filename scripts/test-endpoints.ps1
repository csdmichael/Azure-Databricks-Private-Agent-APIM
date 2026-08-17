<#
.SYNOPSIS
  Smoke-tests the POC endpoints:
    1. Databricks workspace reachability (control plane).
    2. A SQL query against the sample data (SQL Statement Execution API).
    3. The APIM-exposed Databricks endpoint (if -ApimBaseUrl / -ApimKey given).

.EXAMPLE
  ./scripts/test-endpoints.ps1 -WorkspaceUrl "https://adb-123.11.azuredatabricks.net" -WarehouseId "abc123" -UseAzureCli
  ./scripts/test-endpoints.ps1 -WorkspaceUrl "..." -WarehouseId "..." -UseAzureCli `
      -ApimBaseUrl "https://ai-gateway-apim-poc-my.azure-api.net/databricks" -ApimKey "<subscription-key>"
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)] [string] $WorkspaceUrl,
  [Parameter(Mandatory = $true)] [string] $WarehouseId,
  [string] $Token,
  [switch] $UseAzureCli,
  [string] $ApimBaseUrl,
  [string] $ApimKey
)

$ErrorActionPreference = "Stop"
$DatabricksResourceId = "2ff814a6-3304-4ab8-85cb-cd0e6f879c1d"
$WorkspaceUrl = $WorkspaceUrl.TrimEnd("/")

function Get-DbxToken {
  if ($Token) { return $Token }
  if ($UseAzureCli) { return (az account get-access-token --resource $DatabricksResourceId --query accessToken -o tsv) }
  throw "Provide -Token or -UseAzureCli."
}
$authToken = Get-DbxToken
$headers = @{ Authorization = "Bearer $authToken"; "Content-Type" = "application/json" }

Write-Host "1) Workspace reachability..." -ForegroundColor Cyan
$me = Invoke-RestMethod -Method GET -Uri "$WorkspaceUrl/api/2.0/preview/scim/v2/Me" -Headers $headers
Write-Host "   OK - authenticated as $($me.userName)" -ForegroundColor Green

Write-Host "2) Sample query via SQL Statement Execution API..." -ForegroundColor Cyan
$q = @{
  warehouse_id    = $WarehouseId
  statement       = "SELECT region, ROUND(SUM(revenue_usd)/1e6,2) AS revenue_musd FROM databricks_ws_ai_poc.arrow_semiconductor.product_sales GROUP BY region ORDER BY revenue_musd DESC"
  wait_timeout    = "50s"
  on_wait_timeout = "CONTINUE"
  format          = "JSON_ARRAY"
  disposition     = "INLINE"
} | ConvertTo-Json -Depth 6
$r = Invoke-RestMethod -Method POST -Uri "$WorkspaceUrl/api/2.0/sql/statements" -Headers $headers -Body $q
$id = $r.statement_id
while ($r.status.state -in @("PENDING", "RUNNING")) { Start-Sleep 3; $r = Invoke-RestMethod -Method GET -Uri "$WorkspaceUrl/api/2.0/sql/statements/$id" -Headers $headers }
if ($r.status.state -ne "SUCCEEDED") { throw "Query failed: $($r.status.error.message)" }
Write-Host "   Revenue by region (USD millions):" -ForegroundColor Green
$r.result.data_array | ForEach-Object { Write-Host ("     {0,-16} {1,8}" -f $_[0], $_[1]) }

if ($ApimBaseUrl -and $ApimKey) {
  Write-Host "3) APIM-exposed Databricks endpoint..." -ForegroundColor Cyan
  $apimHeaders = @{ "Ocp-Apim-Subscription-Key" = $ApimKey; "Content-Type" = "application/json" }
  $body = @{ statement = "SELECT product_family, ROUND(SUM(revenue_usd)/1e6,2) AS revenue_musd FROM databricks_ws_ai_poc.arrow_semiconductor.product_sales GROUP BY product_family ORDER BY revenue_musd DESC LIMIT 5" } | ConvertTo-Json
  $ar = Invoke-RestMethod -Method POST -Uri "$($ApimBaseUrl.TrimEnd('/'))/query" -Headers $apimHeaders -Body $body
  Write-Host "   APIM query OK. Rows returned: $(( $ar.result.data_array | Measure-Object).Count)" -ForegroundColor Green
}
else {
  Write-Host "3) APIM test skipped (pass -ApimBaseUrl and -ApimKey to run)." -ForegroundColor DarkGray
}

Write-Host "`nAll requested endpoint tests passed." -ForegroundColor Green
