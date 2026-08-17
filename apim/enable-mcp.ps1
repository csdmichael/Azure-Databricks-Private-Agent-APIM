<#
.SYNOPSIS
  Exposes the Databricks API's operations as an MCP server in APIM so Foundry
  Agents / Copilot Studio can consume them as tools.

.DESCRIPTION
  APIM's "expose an API as an MCP server" capability is in preview. This script
  makes a best-effort call against the preview management API; if the API shape
  differs in your region, follow the printed portal steps instead.

  MCP endpoint (once created): https://<apim>.azure-api.net/<mcp-path>/mcp

.EXAMPLE
  ./apim/enable-mcp.ps1 -SourceApiId databricks -McpPath databricks-mcp
#>
[CmdletBinding()]
param(
  [string] $ResourceGroup = "ai-myaacoub",
  [string] $ApimName = "ai-gateway-apim-poc-my",
  [string] $SubscriptionId = "86b37969-9445-49cf-b03f-d8866235171c",
  [string] $SourceApiId = "databricks",
  [string] $McpDisplayName = "Databricks MCP",
  [string] $McpPath = "databricks-mcp",
  [string] $ApiVersion = "2024-06-01-preview"
)

$ErrorActionPreference = "Stop"
$base = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.ApiManagement/service/$ApimName"

# Discover operations on the source API to expose them all as MCP tools.
Write-Host "Reading operations on API '$SourceApiId'..." -ForegroundColor Cyan
$ops = az rest --method get --url "$base/apis/$SourceApiId/operations?api-version=$ApiVersion" | ConvertFrom-Json
$opIds = @($ops.value | ForEach-Object { $_.name })
Write-Host "  Operations: $($opIds -join ', ')"

$mcpApiId = "$SourceApiId-mcp"
$srcApiResourceId = "$base/apis/$SourceApiId"
$bodyObj = @{
  properties = @{
    type        = "mcp"
    displayName = $McpDisplayName
    path        = $McpPath
    protocols   = @("https")
    # Each tool maps to an operation of the source API (full resource id required).
    mcpTools    = @($opIds | ForEach-Object { @{ name = $_; operationId = "$srcApiResourceId/operations/$_" } })
  }
}
$tmp = New-TemporaryFile
$bodyObj | ConvertTo-Json -Depth 8 | Set-Content -Path $tmp -Encoding utf8

Write-Host "Creating MCP server '$mcpApiId' (preview)..." -ForegroundColor Yellow
# az is a native command; check the exit code (try/catch does not trap it).
$out = az rest --method put `
  --url "$base/apis/$mcpApiId?api-version=$ApiVersion" `
  --headers "Content-Type=application/json" `
  --body "@$tmp" 2>&1
Remove-Item $tmp -ErrorAction SilentlyContinue

if ($LASTEXITCODE -eq 0) {
  Write-Host "MCP server created." -ForegroundColor Green
  Write-Host "MCP endpoint: https://$ApimName.azure-api.net/$McpPath/mcp" -ForegroundColor Green
}
else {
  Write-Warning "Preview MCP API call failed (exit $LASTEXITCODE):"
  Write-Host $out
  Write-Host @"

Do this in the Azure Portal instead (preview):
  1. APIM ($ApimName) -> APIs -> MCP Servers -> + Create MCP server.
  2. Choose 'Expose an API as an MCP server'.
  3. Source API: 'Databricks SQL' ($SourceApiId). Select operations: query, tables.
  4. Name: $McpDisplayName   Path: $McpPath
  5. Create. MCP endpoint = https://$ApimName.azure-api.net/$McpPath/mcp
  6. Repeat for 'Databricks Genie' if you want Genie exposed as MCP too.
"@ -ForegroundColor Cyan
}
