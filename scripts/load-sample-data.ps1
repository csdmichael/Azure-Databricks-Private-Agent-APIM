<#
.SYNOPSIS
  Loads the semiconductor sample dataset into Azure Databricks (Unity Catalog)
  using the SQL Statement Execution API. Creates a low-cost serverless SQL
  warehouse with configurable sizing if one does not already exist.

.DESCRIPTION
  Auth options:
    -UseAzureCli            Get an Entra token for the Databricks login app via `az`.
    -Token <pat-or-aad>     Use a provided Databricks PAT or AAD token.

.EXAMPLE
  ./scripts/load-sample-data.ps1 -WorkspaceUrl "https://adb-123.11.azuredatabricks.net" -UseAzureCli
#>
[CmdletBinding()]
param(
  [string] $ConfigPath = (Join-Path $PSScriptRoot '../config/deployment.json'),
  [string] $WorkspaceUrl,
  [string] $Token,
  [switch] $UseAzureCli,
  [string] $WarehouseName,
  [string] $Catalog,
  [string] $Schema,
  [string] $SourceCatalogToken,
  [string] $SourceSchemaToken,
  [string] $SqlFile = "$PSScriptRoot/../databricks/sql/01_create_and_load.sql",
  [string] $WarehouseClusterSize = '2X-Small',
  [int] $WarehouseAutoStopMinutes = 5,
  [int] $WarehouseMinClusters = 1,
  [int] $WarehouseMaxClusters = 1,
  [Nullable[int]] $SqlWaitTimeoutSeconds,
  [int] $SqlPollIntervalSeconds = 3
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot 'config.ps1')

$config = Get-DeploymentConfig -Path $ConfigPath
$WorkspaceUrl = (Get-ConfigValue -Config $config -Path 'databricks.workspaceUrl' -Override $WorkspaceUrl).TrimEnd('/')
$WarehouseName = Get-ConfigValue -Config $config -Path 'databricks.sampleWarehouseName' -Override $WarehouseName
$Catalog = Get-ConfigValue -Config $config -Path 'databricks.catalog' -Override $Catalog
$Schema = Get-ConfigValue -Config $config -Path 'databricks.schema' -Override $Schema
$SourceCatalogToken = Get-ConfigValue -Config $config -Path 'databricks.sourceCatalogToken' -Override $SourceCatalogToken
$SourceSchemaToken = Get-ConfigValue -Config $config -Path 'databricks.sourceSchemaToken' -Override $SourceSchemaToken
$SqlWaitTimeoutSeconds = [int](Get-ConfigValue -Config $config -Path 'databricks.sqlWaitTimeoutSeconds' -Override $SqlWaitTimeoutSeconds)

# Azure Databricks is a fixed Microsoft audience ID.
$DatabricksResourceId = "2ff814a6-3304-4ab8-85cb-cd0e6f879c1d"

function Get-DbxToken {
  if ($Token) { return $Token }
  if ($UseAzureCli) {
    Write-Host "Requesting Entra token for Databricks via az CLI..." -ForegroundColor Cyan
    $t = az account get-access-token --resource $DatabricksResourceId --query accessToken -o tsv
    if (-not $t) { throw "Failed to acquire AAD token via az CLI." }
    return $t
  }
  throw "Provide -Token or -UseAzureCli."
}

$authToken = Get-DbxToken
$headers = @{ Authorization = "Bearer $authToken"; "Content-Type" = "application/json" }

function Invoke-Dbx {
  param([string]$Method, [string]$Path, [object]$Body)
  $uri = "$WorkspaceUrl$Path"
  $json = if ($Body) { $Body | ConvertTo-Json -Depth 12 } else { $null }
  return Invoke-RestMethod -Method $Method -Uri $uri -Headers $headers -Body $json
}

# --- Ensure a serverless SQL warehouse exists -----------------------------
function Get-OrCreate-Warehouse {
  Write-Host "Looking for SQL warehouse '$WarehouseName'..." -ForegroundColor Cyan
  $list = Invoke-Dbx GET "/api/2.0/sql/warehouses"
  $wh = $null
  if ($list.warehouses) { $wh = $list.warehouses | Where-Object { $_.name -eq $WarehouseName } | Select-Object -First 1 }
  if ($wh) { Write-Host "  Found existing warehouse id=$($wh.id)"; return $wh.id }

  Write-Host "  Creating serverless $WarehouseClusterSize warehouse (auto-stop $WarehouseAutoStopMinutes min)..." -ForegroundColor Yellow
  $body = @{
    name                      = $WarehouseName
    cluster_size              = $WarehouseClusterSize
    min_num_clusters          = $WarehouseMinClusters
    max_num_clusters          = $WarehouseMaxClusters
    auto_stop_mins            = $WarehouseAutoStopMinutes
    enable_serverless_compute = $true
    warehouse_type            = "PRO"
    spot_instance_policy      = "COST_OPTIMIZED"
  }
  try {
    $created = Invoke-Dbx POST "/api/2.0/sql/warehouses" $body
    return $created.id
  }
  catch {
    Write-Warning "Serverless create failed ($_). Falling back to classic PRO $WarehouseClusterSize."
    $body.enable_serverless_compute = $false
    $created = Invoke-Dbx POST "/api/2.0/sql/warehouses" $body
    return $created.id
  }
}

# --- Execute one SQL statement and wait for a terminal state --------------
function Invoke-DbxSql {
  param([string]$WarehouseId, [string]$Statement)
  $body = @{
    warehouse_id    = $WarehouseId
    statement       = $Statement
    wait_timeout    = "${SqlWaitTimeoutSeconds}s"
    on_wait_timeout = "CONTINUE"
    format          = "JSON_ARRAY"
    disposition     = "INLINE"
  }
  $resp = Invoke-Dbx POST "/api/2.0/sql/statements" $body
  $id = $resp.statement_id
  while ($resp.status.state -in @("PENDING", "RUNNING")) {
    Start-Sleep -Seconds $SqlPollIntervalSeconds
    $resp = Invoke-Dbx GET "/api/2.0/sql/statements/$id"
  }
  if ($resp.status.state -ne "SUCCEEDED") {
    throw "Statement failed [$($resp.status.state)]: $($resp.status.error.message)"
  }
  return $resp
}

$warehouseId = Get-OrCreate-Warehouse
Write-Host "Using warehouse id=$warehouseId" -ForegroundColor Green

$raw = Get-Content -Path $SqlFile -Raw
$raw = $raw.Replace("$SourceCatalogToken.$SourceSchemaToken", "$Catalog.$Schema")
# Keep chunks that contain at least one non-comment, non-blank line. Uses simple
# per-line checks to avoid catastrophic regex backtracking on big comment blocks.
$statements = $raw -split '(?m)^\s*--\s*@statement\s*$' |
  ForEach-Object { $_.Trim() } |
  Where-Object {
    $_ -and (($_ -split "`n" | Where-Object { $_.Trim() -and ($_.Trim() -notmatch '^--') } | Measure-Object).Count -gt 0)
  }

Write-Host "Executing $($statements.Count) SQL statements..." -ForegroundColor Cyan
$i = 0
$lastResp = $null
foreach ($stmt in $statements) {
  $i++
  $preview = ($stmt -split "`n" | Where-Object { $_ -notmatch '^\s*--' } | Select-Object -First 1)
  Write-Host ("  [{0}/{1}] {2}" -f $i, $statements.Count, ($preview.Substring(0, [Math]::Min(70, $preview.Length))))
  $lastResp = Invoke-DbxSql -WarehouseId $warehouseId -Statement $stmt
}

Write-Host "`nSample data loaded. Row counts:" -ForegroundColor Green
if ($lastResp.result.data_array) {
  $cols = $lastResp.manifest.schema.columns.name
  $lastResp.result.data_array | ForEach-Object {
    Write-Host ("  {0,-18} {1,8}" -f $_[0], $_[1])
  }
}
Write-Host "`nWarehouse '$WarehouseName' (id=$warehouseId) will auto-stop after $WarehouseAutoStopMinutes idle minutes." -ForegroundColor DarkGray
Write-Output $warehouseId
