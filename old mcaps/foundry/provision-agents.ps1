<#
.SYNOPSIS
  Provisions (and smoke-tests) the two Foundry prompt agents from a workstation.

.DESCRIPTION
  Mirrors the environment used by .github/workflows/provision-foundry-agent.yml
  so the same scripts can be run locally. The APIM subscription key is read at
  run time from APIM and kept in-process only.

.EXAMPLE
  ./provision-agents.ps1                 # both agents, with smoke tests
  ./provision-agents.ps1 -Agent genie -SkipTest
#>
[CmdletBinding()]
param(
    [string] $ConfigPath = (Join-Path $PSScriptRoot '../../config/deployment.json'),
    [ValidateSet("all", "databricks", "genie")]
    [string] $Agent = "all",
    [switch] $SkipTest,
    [string] $ResourceGroup,
    [string] $ApimName,
    [string] $SubscriptionId,
    [string] $ApimSubscriptionName,
    [string] $FoundryAccountName,
    [string] $FoundryProjectName,
    [string] $FoundryProjectEndpoint,
    [string] $FoundryModelDeploymentName,
    [string] $FoundryAgentName,
    [string] $McpConnectionName,
    [string] $McpServerUrl,
    [string] $FoundryGenieAgentName,
    [string] $GenieMcpConnectionName,
    [string] $GenieMcpServerUrl,
    [string] $OutputDirectory,
    [string] $PythonExe = "python"
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repoRoot 'scripts/config.ps1')

$config = Get-DeploymentConfig -Path $ConfigPath
$ResourceGroup = Get-ConfigValue -Config $config -Path 'azure.resourceGroup' -Override $ResourceGroup
$ApimName = Get-ConfigValue -Config $config -Path 'apim.serviceName' -Override $ApimName
$SubscriptionId = Get-ConfigValue -Config $config -Path 'azure.subscriptionId' -Override $SubscriptionId
$ApimSubscriptionName = Get-ConfigValue -Config $config -Path 'apim.subscriptionName' -Override $ApimSubscriptionName
$FoundryAccountName = Get-ConfigValue -Config $config -Path 'foundry.application.accountName' -Override $FoundryAccountName
$FoundryProjectName = Get-ConfigValue -Config $config -Path 'foundry.application.projectName' -Override $FoundryProjectName
if ([string]::IsNullOrWhiteSpace($FoundryModelDeploymentName)) {
    throw 'The application Foundry model deployment is not represented in config/deployment.json. Pass -FoundryModelDeploymentName explicitly.'
}
$sourceApiId = Get-ConfigValue -Config $config -Path 'apim.sourceApiId'
$gatewayUrl = (Get-ConfigValue -Config $config -Path 'apim.gatewayUrl').TrimEnd('/')
$mcpPath = (Get-ConfigValue -Config $config -Path 'apim.mcpPath').Trim('/')
if ([string]::IsNullOrWhiteSpace($FoundryProjectEndpoint)) { $FoundryProjectEndpoint = "https://$FoundryAccountName.services.ai.azure.com/api/projects/$FoundryProjectName" }
if ([string]::IsNullOrWhiteSpace($FoundryAgentName)) { $FoundryAgentName = "$sourceApiId-agent-mcp" }
if ([string]::IsNullOrWhiteSpace($McpConnectionName)) { $McpConnectionName = "$sourceApiId-apim-mcp" }
if ([string]::IsNullOrWhiteSpace($McpServerUrl)) { $McpServerUrl = "$gatewayUrl/$mcpPath/mcp" }
if ([string]::IsNullOrWhiteSpace($FoundryGenieAgentName)) { $FoundryGenieAgentName = "$sourceApiId-genie-agent" }
if ([string]::IsNullOrWhiteSpace($GenieMcpConnectionName)) { $GenieMcpConnectionName = "$sourceApiId-apim-genie-mcp" }
if ([string]::IsNullOrWhiteSpace($GenieMcpServerUrl)) { $GenieMcpServerUrl = "$gatewayUrl/$sourceApiId-genie-mcp/mcp" }
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) { $OutputDirectory = Join-Path $repoRoot 'artifacts' }

$env:AZURE_SUBSCRIPTION_ID = $SubscriptionId
$env:AZURE_RESOURCE_GROUP = $ResourceGroup
$env:FOUNDRY_ACCOUNT_NAME = $FoundryAccountName
$env:FOUNDRY_PROJECT_NAME = $FoundryProjectName
$env:FOUNDRY_PROJECT_ENDPOINT = $FoundryProjectEndpoint
$env:FOUNDRY_MODEL_DEPLOYMENT_NAME = $FoundryModelDeploymentName
$env:FOUNDRY_AGENT_NAME = $FoundryAgentName
$env:MCP_CONNECTION_NAME = $McpConnectionName
$env:MCP_SERVER_URL = $McpServerUrl
$env:FOUNDRY_GENIE_AGENT_NAME = $FoundryGenieAgentName
$env:GENIE_MCP_CONNECTION_NAME = $GenieMcpConnectionName
$env:GENIE_MCP_SERVER_URL = $GenieMcpServerUrl

$listSecrets = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.ApiManagement/service/$ApimName/subscriptions/$ApimSubscriptionName/listSecrets?api-version=2024-06-01-preview"
$env:APIM_SUBSCRIPTION_KEY = az rest --method post --url $listSecrets --query primaryKey -o tsv
if ($LASTEXITCODE -ne 0 -or -not $env:APIM_SUBSCRIPTION_KEY) { throw "Unable to read the APIM subscription key." }

$testArgs = @()
if ($SkipTest) { $testArgs += "--skip-test" }

try {
    Push-Location $PSScriptRoot
    if ($Agent -in @("all", "databricks")) {
        Write-Host "== $FoundryAgentName ==" -ForegroundColor Cyan
    & $PythonExe "provision_agent.py" @testArgs --output-dir $OutputDirectory
        if ($LASTEXITCODE -ne 0) { throw "provision_agent.py failed with exit code $LASTEXITCODE" }
    }
    if ($Agent -in @("all", "genie")) {
        Write-Host "== $FoundryGenieAgentName ==" -ForegroundColor Cyan
    & $PythonExe "provision_genie_agent.py" @testArgs --output-dir $OutputDirectory
        if ($LASTEXITCODE -ne 0) { throw "provision_genie_agent.py failed with exit code $LASTEXITCODE" }
    }
}
finally {
    Pop-Location
    $env:APIM_SUBSCRIPTION_KEY = $null
}

Write-Host "Done." -ForegroundColor Green
