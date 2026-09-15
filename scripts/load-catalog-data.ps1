<#
.SYNOPSIS
  Creates the Unity Catalog schema and loads the sample dataset into the
  configured Databricks workspace using the SQL Statement Execution API.

.DESCRIPTION
  Reuses the dataset definition in databricks/sql/01_create_and_load.sql from the
  source repository and retargets it at the configured catalog and schema.
  Run this while the workspace still allows public network access (stage 1), or
  from a host inside the injected VNet after lockdown.

.EXAMPLE
  ./load-catalog-data.ps1 -WorkspaceUrl https://adb-123.4.azuredatabricks.net
#>
[CmdletBinding()]
param(
  [string] $ConfigPath = (Join-Path $PSScriptRoot '../config/deployment.json'),
  [string] $WorkspaceUrl,
  [string] $Catalog,
  [string] $Schema,
  [string] $WarehouseName,
  [string] $SqlFile = "$PSScriptRoot/../databricks/sql/01_create_and_load.sql",
  [string] $SourceCatalogToken,
  [string] $SourceSchemaToken,
  [string] $WarehouseClusterSize = '2X-Small',
  [int] $WarehouseAutoStopMinutes = 5,
  [int] $WarehouseMinClusters = 1,
  [int] $WarehouseMaxClusters = 1,
  [Nullable[int]] $SqlWaitTimeoutSeconds,
  [int] $SqlPollIntervalSeconds = 3
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'config.ps1')

$config = Get-DeploymentConfig -Path $ConfigPath
$WorkspaceUrl = (Get-ConfigValue -Config $config -Path 'databricks.workspaceUrl' -Override $WorkspaceUrl).TrimEnd('/')
$Catalog = Get-ConfigValue -Config $config -Path 'databricks.catalog' -Override $Catalog
$Schema = Get-ConfigValue -Config $config -Path 'databricks.schema' -Override $Schema
$WarehouseName = Get-ConfigValue -Config $config -Path 'databricks.warehouseName' -Override $WarehouseName
$SourceCatalogToken = Get-ConfigValue -Config $config -Path 'databricks.sourceCatalogToken' -Override $SourceCatalogToken
$SourceSchemaToken = Get-ConfigValue -Config $config -Path 'databricks.sourceSchemaToken' -Override $SourceSchemaToken
$SqlWaitTimeoutSeconds = [int](Get-ConfigValue -Config $config -Path 'databricks.sqlWaitTimeoutSeconds' -Override $SqlWaitTimeoutSeconds)

# Azure Databricks is a fixed Microsoft audience ID.
$DatabricksResourceId = '2ff814a6-3304-4ab8-85cb-cd0e6f879c1d'

if (-not (Test-Path $SqlFile)) { throw "SQL file not found: $SqlFile" }

$token = az account get-access-token --resource $DatabricksResourceId --query accessToken -o tsv
if ($LASTEXITCODE -ne 0 -or -not $token) { throw 'Unable to acquire an Azure Databricks Entra token.' }
$headers = @{ Authorization = "Bearer $token"; 'Content-Type' = 'application/json' }

function Invoke-Dbx {
  param([string]$Method, [string]$Path, [object]$Body)
  $json = if ($Body) { $Body | ConvertTo-Json -Depth 12 } else { $null }
  Invoke-RestMethod -Method $Method -Uri "$WorkspaceUrl$Path" -Headers $headers -Body $json
}

function Get-Warehouse {
  $list = Invoke-Dbx GET '/api/2.0/sql/warehouses'
  $wh = $null
  if ($list.warehouses) { $wh = $list.warehouses | Where-Object { $_.name -eq $WarehouseName } | Select-Object -First 1 }
  if ($wh) { Write-Host "Using existing warehouse $($wh.id)"; return $wh.id }

  Write-Host "Creating serverless $WarehouseClusterSize warehouse (auto-stop $WarehouseAutoStopMinutes min)..."
  $body = @{
    name                      = $WarehouseName
    cluster_size              = $WarehouseClusterSize
    min_num_clusters          = $WarehouseMinClusters
    max_num_clusters          = $WarehouseMaxClusters
    auto_stop_mins            = $WarehouseAutoStopMinutes
    enable_serverless_compute = $true
    warehouse_type            = 'PRO'
    spot_instance_policy      = 'COST_OPTIMIZED'
  }
  try { return (Invoke-Dbx POST '/api/2.0/sql/warehouses' $body).id }
  catch {
    Write-Warning "Serverless create failed. Falling back to classic PRO. $_"
    $body.enable_serverless_compute = $false
    return (Invoke-Dbx POST '/api/2.0/sql/warehouses' $body).id
  }
}

function Invoke-DbxSql {
  param([string]$WarehouseId, [string]$Statement)
  $resp = Invoke-Dbx POST '/api/2.0/sql/statements' @{
    warehouse_id    = $WarehouseId
    statement       = $Statement
    wait_timeout    = "${SqlWaitTimeoutSeconds}s"
    on_wait_timeout = 'CONTINUE'
    format          = 'JSON_ARRAY'
    disposition     = 'INLINE'
  }
  while ($resp.status.state -in @('PENDING', 'RUNNING')) {
    Start-Sleep -Seconds $SqlPollIntervalSeconds
    $resp = Invoke-Dbx GET "/api/2.0/sql/statements/$($resp.statement_id)"
  }
  if ($resp.status.state -ne 'SUCCEEDED') {
    throw "Statement failed [$($resp.status.state)]: $($resp.status.error.message)"
  }
  return $resp
}

$warehouseId = Get-Warehouse

$raw = Get-Content -Path $SqlFile -Raw
$raw = $raw.Replace("$SourceCatalogToken.$SourceSchemaToken", "$Catalog.$Schema")

$statements = $raw -split '(?m)^\s*--\s*@statement\s*$' |
  ForEach-Object { $_.Trim() } |
  Where-Object {
    $_ -and (($_ -split "`n" | Where-Object { $_.Trim() -and ($_.Trim() -notmatch '^--') } | Measure-Object).Count -gt 0)
  }

Write-Host "Executing $($statements.Count) statements against $Catalog.$Schema ..."
$i = 0
foreach ($stmt in $statements) {
  $i++
  Write-Host "  [$i/$($statements.Count)]"
  Invoke-DbxSql $warehouseId $stmt | Out-Null
}

$tables = (Invoke-DbxSql $warehouseId "SHOW TABLES IN $Catalog.$Schema").result.data_array
Write-Host "Loaded $($tables.Count) table(s) into $Catalog.$Schema" -ForegroundColor Green
[pscustomobject]@{ Catalog = $Catalog; Schema = $Schema; WarehouseId = $warehouseId; Tables = $tables.Count }
