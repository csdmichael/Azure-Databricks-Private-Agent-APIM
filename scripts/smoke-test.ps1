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
  [string] $ConfigPath = (Join-Path $PSScriptRoot '../config/deployment.json'),
  [string] $SubscriptionId,
  [string] $ResourceGroup,
  [string] $ApimName,
  [string] $ApimSubscriptionName,
  [string] $GatewayUrl,
  [string] $Catalog,
  [string] $Schema,
  [string] $Question,
  [string] $SqlApiPath,
  [string] $GenieApiPath,
  [string] $GenieMcpPath,
  [Nullable[int]] $RequestTimeoutSeconds
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'config.ps1')

$config = Get-DeploymentConfig -Path $ConfigPath
$SubscriptionId = Get-ConfigValue -Config $config -Path 'azure.subscriptionId' -Override $SubscriptionId
$ResourceGroup = Get-ConfigValue -Config $config -Path 'azure.resourceGroup' -Override $ResourceGroup
$ApimName = Get-ConfigValue -Config $config -Path 'apim.serviceName' -Override $ApimName
$ApimSubscriptionName = Get-ConfigValue -Config $config -Path 'apim.subscriptionName' -Override $ApimSubscriptionName
$GatewayUrl = (Get-ConfigValue -Config $config -Path 'apim.gatewayUrl' -Override $GatewayUrl).TrimEnd('/')
$Catalog = Get-ConfigValue -Config $config -Path 'databricks.catalog' -Override $Catalog
$Schema = Get-ConfigValue -Config $config -Path 'databricks.schema' -Override $Schema
$Question = Get-ConfigValue -Config $config -Path 'tests.smokePrompt' -Override $Question
$RequestTimeoutSeconds = [int](Get-ConfigValue -Config $config -Path 'databricks.apiTimeoutSeconds' -Override $RequestTimeoutSeconds)
$sourceApiId = Get-ConfigValue -Config $config -Path 'apim.sourceApiId'
if ([string]::IsNullOrWhiteSpace($SqlApiPath)) { $SqlApiPath = "/$sourceApiId" }
if ([string]::IsNullOrWhiteSpace($GenieApiPath)) { $GenieApiPath = "/$sourceApiId-genie" }
if ([string]::IsNullOrWhiteSpace($GenieMcpPath)) { $GenieMcpPath = "/$sourceApiId-genie-mcp" }

$secretsUrl = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.ApiManagement/service/$ApimName/subscriptions/$ApimSubscriptionName/listSecrets?api-version=2024-05-01"
$key = (az rest --method post --url $secretsUrl | ConvertFrom-Json).primaryKey
if (-not $key) { throw 'Could not read the APIM subscription key.' }

try {
  $headers = @{ 'Ocp-Apim-Subscription-Key' = $key; 'Content-Type' = 'application/json' }

  Write-Host "POST $SqlApiPath/query ..." -ForegroundColor Cyan
  $sqlBody = @{ statement = "SELECT COUNT(*) AS row_count FROM $Catalog.$Schema.fab_production" } | ConvertTo-Json
  $sql = Invoke-RestMethod -Method POST -Uri "$GatewayUrl$SqlApiPath/query" -Headers $headers -Body $sqlBody -TimeoutSec $RequestTimeoutSeconds
  Write-Host "  OK -> $($sql | ConvertTo-Json -Depth 6 -Compress)" -ForegroundColor Green

  Write-Host "GET $SqlApiPath/tables ..." -ForegroundColor Cyan
  $tables = Invoke-RestMethod -Method GET -Uri "$GatewayUrl$SqlApiPath/tables" -Headers $headers -TimeoutSec $RequestTimeoutSeconds
  Write-Host "  OK -> $($tables | ConvertTo-Json -Depth 6 -Compress)" -ForegroundColor Green

  Write-Host "POST $GenieApiPath/genie/ask ..." -ForegroundColor Cyan
  $genieBody = @{ content = $Question } | ConvertTo-Json
  $genie = Invoke-RestMethod -Method POST -Uri "$GatewayUrl$GenieApiPath/genie/ask" -Headers $headers -Body $genieBody -TimeoutSec $RequestTimeoutSeconds
  Write-Host "  OK -> $($genie | ConvertTo-Json -Depth 8 -Compress)" -ForegroundColor Green

  Write-Host "POST $GenieMcpPath/mcp (tools/list) ..." -ForegroundColor Cyan
  $mcpHeaders = @{
    'Ocp-Apim-Subscription-Key' = $key
    'Content-Type'              = 'application/json'
    'Accept'                    = 'application/json, text/event-stream'
  }
  $mcpBody = @{ jsonrpc = '2.0'; id = 1; method = 'tools/list' } | ConvertTo-Json
  $mcp = Invoke-WebRequest -Method POST -Uri "$GatewayUrl$GenieMcpPath/mcp" -Headers $mcpHeaders -Body $mcpBody -TimeoutSec $RequestTimeoutSeconds
  Write-Host "  OK -> HTTP $($mcp.StatusCode)" -ForegroundColor Green
  Write-Host "  $($mcp.Content)"
}
finally {
  $key = $null
  $headers = $null
  $mcpHeaders = $null
  [System.GC]::Collect()
}
