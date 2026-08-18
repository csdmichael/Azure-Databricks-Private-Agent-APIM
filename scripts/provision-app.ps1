<#
.SYNOPSIS
  Provisions the App Service that hosts the Databricks Agents API and the Static
  Web App that hosts the Angular/Ionic UI.

.DESCRIPTION
  Idempotent. Creates (or reuses) a Linux App Service plan, the Python web app,
  its system-assigned identity and Foundry role assignments, and a free Static
  Web App. Prints the resulting URLs.

.EXAMPLE
  ./scripts/provision-app.ps1
  ./scripts/provision-app.ps1 -PlanSku B1
#>
[CmdletBinding()]
param(
    [string] $SubscriptionId = "86b37969-9445-49cf-b03f-d8866235171c",
    [string] $ResourceGroup = "ai-myaacoub",
    [string] $Location = "westus2",
    [string] $PlanName = "plan-databricks-agents-poc",
    [ValidateSet("F1", "B1")]
    [string] $PlanSku = "F1",
    [string] $ApiAppName = "databricks-agents-api-my",
    [string] $UiAppName = "databricks-agents-ui-my",
    [string] $FoundryAccountName = "002-ai-poc-private",
    [string] $FoundryProjectName = "proj-default"
)

$ErrorActionPreference = "Stop"

function Invoke-Az {
    param([string[]] $Arguments, [switch] $AllowFailure)
    # az writes warnings to stderr, which PowerShell would otherwise turn into a
    # terminating NativeCommandError; rely on the exit code instead.
    $previous = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try { $output = az @Arguments 2>&1 } finally { $ErrorActionPreference = $previous }
    if ($LASTEXITCODE -ne 0 -and -not $AllowFailure) {
        throw "az $($Arguments -join ' ') failed:`n$output"
    }
    return $output
}

# `az ... show` writes to stderr when a resource is absent, which PowerShell turns
# into a terminating NativeCommandError; probe with the preference relaxed.
function Get-AzValue {
    param([string[]] $Arguments)
    $previous = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try { $output = az @Arguments 2>&1 } finally { $ErrorActionPreference = $previous }
    if ($LASTEXITCODE -ne 0) { return $null }
    $value = (@($output) | Where-Object { $_ -is [string] }) -join ""
    if ([string]::IsNullOrWhiteSpace($value)) { return $null }
    return $value.Trim()
}

Write-Host "== App Service plan ($PlanSku, Linux) ==" -ForegroundColor Cyan
$plan = Get-AzValue @("appservice", "plan", "show", "-g", $ResourceGroup, "-n", $PlanName, "--query", "name", "-o", "tsv")
if (-not $plan) {
    Invoke-Az @("appservice", "plan", "create", "-g", $ResourceGroup, "-n", $PlanName,
        "--is-linux", "--sku", $PlanSku, "--location", $Location, "-o", "none") | Out-Null
    Write-Host "  created $PlanName"
}
else {
    Write-Host "  reusing $PlanName"
}

Write-Host "== API web app ==" -ForegroundColor Cyan
$api = Get-AzValue @("webapp", "show", "-g", $ResourceGroup, "-n", $ApiAppName, "--query", "name", "-o", "tsv")
if (-not $api) {
    Invoke-Az @("webapp", "create", "-g", $ResourceGroup, "-p", $PlanName, "-n", $ApiAppName,
        "--runtime", "PYTHON:3.12", "-o", "none") | Out-Null
    Write-Host "  created $ApiAppName"
}
else {
    Write-Host "  reusing $ApiAppName"
}

$apiUrl = "https://$ApiAppName.azurewebsites.net"

Write-Host "== Static Web App (Free) ==" -ForegroundColor Cyan
$ui = Get-AzValue @("staticwebapp", "show", "-g", $ResourceGroup, "-n", $UiAppName, "--query", "name", "-o", "tsv")
if (-not $ui) {
    Invoke-Az @("staticwebapp", "create", "-g", $ResourceGroup, "-n", $UiAppName,
        "--location", $Location, "--sku", "Free", "-o", "none") | Out-Null
    Write-Host "  created $UiAppName"
}
else {
    Write-Host "  reusing $UiAppName"
}
$uiHost = Get-AzValue @("staticwebapp", "show", "-g", $ResourceGroup, "-n", $UiAppName, "--query", "defaultHostname", "-o", "tsv")
$uiUrl = "https://$uiHost"

Write-Host "== API configuration ==" -ForegroundColor Cyan
$settings = @(
    "SCM_DO_BUILD_DURING_DEPLOYMENT=true",
    "WEBSITES_CONTAINER_START_TIME_LIMIT=600",
    "PUBLIC_API_URL=$apiUrl",
    "CORS_ALLOW_ORIGINS=$uiUrl,http://localhost:4200,http://localhost:8100",
    "FOUNDRY_PROJECT_ENDPOINT=https://$FoundryAccountName.services.ai.azure.com/api/projects/$FoundryProjectName",
    "APIM_BASE_URL=https://ai-gateway-apim-poc-my.azure-api.net",
    "GITHUB_REPO_URL=https://github.com/csdmichael/Azure-Databricks-Private-Agent-APIM"
)
Invoke-Az (@("webapp", "config", "appsettings", "set", "-g", $ResourceGroup, "-n", $ApiAppName, "-o", "none", "--settings") + $settings) | Out-Null

# One worker only: the chat job store lives in process memory.
$startup = "gunicorn app.main:app -k uvicorn.workers.UvicornWorker --workers 1 --threads 8 --timeout 600 --bind 0.0.0.0:8000"
Invoke-Az @("webapp", "config", "set", "-g", $ResourceGroup, "-n", $ApiAppName,
    "--startup-file", $startup, "--http20-enabled", "true", "-o", "none") | Out-Null
Write-Host "  app settings and startup command applied"

Write-Host "== Managed identity and Foundry access ==" -ForegroundColor Cyan
$principalId = Get-AzValue @("webapp", "identity", "assign", "-g", $ResourceGroup, "-n", $ApiAppName, "--query", "principalId", "-o", "tsv")
if (-not $principalId) { throw "Could not assign a system-assigned identity to $ApiAppName." }
Write-Host "  principalId $principalId"

$projectScope = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.CognitiveServices/accounts/$FoundryAccountName/projects/$FoundryProjectName"
# The API only invokes agents and reads Code Interpreter output files, so it does
# not need the Foundry Project Manager role that the provisioning workflow uses.
foreach ($role in @("Foundry User")) {
    $existing = Get-AzValue @("role", "assignment", "list", "--assignee", $principalId, "--scope", $projectScope, "--role", $role, "--query", "[0].id", "-o", "tsv")
    if ($existing) {
        Write-Host "  '$role' already assigned"
        continue
    }
    $result = Invoke-Az @("role", "assignment", "create", "--assignee-object-id", $principalId,
        "--assignee-principal-type", "ServicePrincipal", "--role", $role, "--scope", $projectScope, "-o", "none") -AllowFailure
    if ($LASTEXITCODE -eq 0) { Write-Host "  assigned '$role'" }
    else { Write-Warning "  could not assign '$role': $result" }
}

Write-Host ""
Write-Host "API : $apiUrl"          -ForegroundColor Green
Write-Host "Docs: $apiUrl/docs"     -ForegroundColor Green
Write-Host "UI  : $uiUrl"           -ForegroundColor Green
