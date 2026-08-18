<#
.SYNOPSIS
  Provisions (and smoke-tests) the two Foundry prompt agents from a workstation.

.DESCRIPTION
  Mirrors the environment used by .github/workflows/provision-foundry-agent.yml
  so the same scripts can be run locally. The APIM subscription key is read at
  run time from APIM and kept in-process only.

.EXAMPLE
  ./scripts/provision-agents.ps1                 # both agents, with smoke tests
  ./scripts/provision-agents.ps1 -Agent genie -SkipTest
#>
[CmdletBinding()]
param(
    [ValidateSet("all", "databricks", "genie")]
    [string] $Agent = "all",
    [switch] $SkipTest,
    [string] $ResourceGroup = "ai-myaacoub",
    [string] $ApimName = "ai-gateway-apim-poc-my",
    [string] $SubscriptionId = "86b37969-9445-49cf-b03f-d8866235171c",
    [string] $ApimSubscriptionName = "DatabricksSubscription",
    [string] $PythonExe = "python"
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot

$env:AZURE_SUBSCRIPTION_ID = $SubscriptionId
$env:AZURE_RESOURCE_GROUP = $ResourceGroup
$env:FOUNDRY_ACCOUNT_NAME = "002-ai-poc-private"
$env:FOUNDRY_PROJECT_NAME = "proj-default"
$env:FOUNDRY_PROJECT_ENDPOINT = "https://002-ai-poc-private.services.ai.azure.com/api/projects/proj-default"
$env:FOUNDRY_MODEL_DEPLOYMENT_NAME = "gpt-4.1"
$env:FOUNDRY_AGENT_NAME = "databricks-agent-mcp"
$env:MCP_CONNECTION_NAME = "databricks-apim-mcp"
$env:MCP_SERVER_URL = "https://ai-gateway-apim-poc-my.azure-api.net/databricks-mcp/mcp"
$env:FOUNDRY_GENIE_AGENT_NAME = "databricks-genie-agent"
$env:GENIE_MCP_CONNECTION_NAME = "databricks-apim-genie-mcp"
$env:GENIE_MCP_SERVER_URL = "https://ai-gateway-apim-poc-my.azure-api.net/databricks-genie-mcp/mcp"

$listSecrets = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.ApiManagement/service/$ApimName/subscriptions/$ApimSubscriptionName/listSecrets?api-version=2024-06-01-preview"
$env:APIM_SUBSCRIPTION_KEY = az rest --method post --url $listSecrets --query primaryKey -o tsv
if ($LASTEXITCODE -ne 0 -or -not $env:APIM_SUBSCRIPTION_KEY) { throw "Unable to read the APIM subscription key." }

$testArg = if ($SkipTest) { @("--skip-test") } else { @() }

try {
    Push-Location (Join-Path $repoRoot "foundry")
    if ($Agent -in @("all", "databricks")) {
        Write-Host "== databricks-agent-mcp ==" -ForegroundColor Cyan
        & $PythonExe "provision_agent.py" @testArg --output-dir (Join-Path $repoRoot "artifacts")
        if ($LASTEXITCODE -ne 0) { throw "provision_agent.py failed with exit code $LASTEXITCODE" }
    }
    if ($Agent -in @("all", "genie")) {
        Write-Host "== databricks-genie-agent ==" -ForegroundColor Cyan
        & $PythonExe "provision_genie_agent.py" @testArg --output-dir (Join-Path $repoRoot "artifacts")
        if ($LASTEXITCODE -ne 0) { throw "provision_genie_agent.py failed with exit code $LASTEXITCODE" }
    }
}
finally {
    Pop-Location
    $env:APIM_SUBSCRIPTION_KEY = $null
}

Write-Host "Done." -ForegroundColor Green
