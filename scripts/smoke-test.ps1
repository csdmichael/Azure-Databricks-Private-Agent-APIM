<#
.SYNOPSIS
  Verifies the APIM -> private Databricks path for both the SQL and Genie APIs.

.DESCRIPTION
  Reads the APIM product subscription key at run time and never writes it to
  disk or output. Run from a host that can reach the APIM gateway: from
  anywhere while public access is enabled, or from inside a peered VNet after
  the stage 2 lockdown.
#>
[CmdletBinding()]
param(
  [string] $SubscriptionId = 'cf824570-a8ba-497a-a184-0a52f1830aa9',
  [string] $ResourceGroup = 'm365-myaacoub',
  [string] $ApimName = 'caldova-apim-westus',
  [string] $ApimSubscriptionName = 'DatabricksSubscription',
  [string] $GatewayUrl = 'https://caldova-apim-westus.azure-api.net',
  [string] $Catalog = 'caldova_dbx_westus2',
  [string] $Schema = 'arrow_semiconductor',
  [string] $Question = 'What was total revenue by region?'
)

$ErrorActionPreference = 'Stop'

$secretsUrl = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.ApiManagement/service/$ApimName/subscriptions/$ApimSubscriptionName/listSecrets?api-version=2024-05-01"
$key = (az rest --method post --url $secretsUrl | ConvertFrom-Json).primaryKey
if (-not $key) { throw 'Could not read the APIM subscription key.' }

try {
  $headers = @{ 'Ocp-Apim-Subscription-Key' = $key; 'Content-Type' = 'application/json' }

  Write-Host 'POST /databricks/query ...' -ForegroundColor Cyan
  $sqlBody = @{ statement = "SELECT COUNT(*) AS row_count FROM $Catalog.$Schema.fab_production" } | ConvertTo-Json
  $sql = Invoke-RestMethod -Method POST -Uri "$GatewayUrl/databricks/query" -Headers $headers -Body $sqlBody
  Write-Host "  OK -> $($sql | ConvertTo-Json -Depth 6 -Compress)" -ForegroundColor Green

  Write-Host 'GET /databricks/tables ...' -ForegroundColor Cyan
  $tables = Invoke-RestMethod -Method GET -Uri "$GatewayUrl/databricks/tables" -Headers $headers
  Write-Host "  OK -> $($tables | ConvertTo-Json -Depth 6 -Compress)" -ForegroundColor Green

  Write-Host 'POST /databricks-genie/genie/ask ...' -ForegroundColor Cyan
  $genieBody = @{ content = $Question } | ConvertTo-Json
  $genie = Invoke-RestMethod -Method POST -Uri "$GatewayUrl/databricks-genie/genie/ask" -Headers $headers -Body $genieBody
  Write-Host "  OK -> $($genie | ConvertTo-Json -Depth 8 -Compress)" -ForegroundColor Green

  Write-Host 'POST /databricks-genie-mcp/mcp (tools/list) ...' -ForegroundColor Cyan
  $mcpHeaders = @{
    'Ocp-Apim-Subscription-Key' = $key
    'Content-Type'              = 'application/json'
    'Accept'                    = 'application/json, text/event-stream'
  }
  $mcpBody = @{ jsonrpc = '2.0'; id = 1; method = 'tools/list' } | ConvertTo-Json
  $mcp = Invoke-WebRequest -Method POST -Uri "$GatewayUrl/databricks-genie-mcp/mcp" -Headers $mcpHeaders -Body $mcpBody
  Write-Host "  OK -> HTTP $($mcp.StatusCode)" -ForegroundColor Green
  Write-Host "  $($mcp.Content)"
}
finally {
  $key = $null
  $headers = $null
  $mcpHeaders = $null
  [System.GC]::Collect()
}
