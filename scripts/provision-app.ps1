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
    [string] $ConfigPath = (Join-Path $PSScriptRoot '../config/deployment.json'),
    [string] $SubscriptionId,
    [string] $TenantId,
    [string] $ResourceGroup,
    [string] $Location,
    [string] $PlanName,
    [ValidateSet("F1", "B1")]
    [string] $PlanSku,
    [string] $ApiAppName,
    [string] $UiAppName,
    [string] $FoundryAccountName,
    [string] $FoundryProjectName,
    [string] $StaticWebAppSku,
    [string] $PythonRuntime,
    [Nullable[int]] $ContainerStartTimeLimitSeconds,
    [Nullable[int]] $GunicornWorkers,
    [Nullable[int]] $GunicornThreads,
    [Nullable[int]] $GunicornTimeoutSeconds,
    [string] $GunicornBind
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot 'config.ps1')

$config = Get-DeploymentConfig -Path $ConfigPath
$SubscriptionId = Get-ConfigValue -Config $config -Path 'azure.subscriptionId' -Override $SubscriptionId
$TenantId = Get-ConfigValue -Config $config -Path 'azure.tenantId' -Override $TenantId
$ResourceGroup = Get-ConfigValue -Config $config -Path 'azure.resourceGroup' -Override $ResourceGroup
$Location = Get-ConfigValue -Config $config -Path 'appService.location' -Override $Location
$PlanName = Get-ConfigValue -Config $config -Path 'appService.planName' -Override $PlanName
$PlanSku = Get-ConfigValue -Config $config -Path 'appService.planSku' -Override $PlanSku
$ApiAppName = Get-ConfigValue -Config $config -Path 'appService.apiAppName' -Override $ApiAppName
$UiAppName = Get-ConfigValue -Config $config -Path 'appService.uiAppName' -Override $UiAppName
$FoundryAccountName = Get-ConfigValue -Config $config -Path 'foundry.application.accountName' -Override $FoundryAccountName
$FoundryProjectName = Get-ConfigValue -Config $config -Path 'foundry.application.projectName' -Override $FoundryProjectName
$StaticWebAppSku = Get-ConfigValue -Config $config -Path 'appService.staticWebAppSku' -Override $StaticWebAppSku
$PythonRuntime = Get-ConfigValue -Config $config -Path 'appService.pythonRuntime' -Override $PythonRuntime
$ContainerStartTimeLimitSeconds = [int](Get-ConfigValue -Config $config -Path 'appService.containerStartTimeLimitSeconds' -Override $ContainerStartTimeLimitSeconds)
$GunicornWorkers = [int](Get-ConfigValue -Config $config -Path 'appService.gunicornWorkers' -Override $GunicornWorkers)
$GunicornThreads = [int](Get-ConfigValue -Config $config -Path 'appService.gunicornThreads' -Override $GunicornThreads)
$GunicornTimeoutSeconds = [int](Get-ConfigValue -Config $config -Path 'appService.gunicornTimeoutSeconds' -Override $GunicornTimeoutSeconds)
$GunicornBind = Get-ConfigValue -Config $config -Path 'appService.gunicornBind' -Override $GunicornBind

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

az account set --subscription $SubscriptionId
if ($LASTEXITCODE -ne 0) { throw "Unable to select Azure subscription $SubscriptionId." }
$signedInTenantId = Get-AzValue @('account', 'show', '--query', 'tenantId', '-o', 'tsv')
if ($signedInTenantId -ne $TenantId) { throw "Authenticate to configured tenant $TenantId before provisioning the app." }

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
        "--runtime", $PythonRuntime, "-o", "none") | Out-Null
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
        "--location", $Location, "--sku", $StaticWebAppSku, "-o", "none") | Out-Null
    Write-Host "  created $UiAppName"
}
else {
    Write-Host "  reusing $UiAppName"
}
$uiHost = Get-AzValue @("staticwebapp", "show", "-g", $ResourceGroup, "-n", $UiAppName, "--query", "defaultHostname", "-o", "tsv")
$uiUrl = "https://$uiHost"

Write-Host "== API configuration ==" -ForegroundColor Cyan
$foundryProjectEndpoint = "https://$FoundryAccountName.services.ai.azure.com/api/projects/$FoundryProjectName"
$corsOrigins = @(@($uiUrl) + @(Get-ConfigValue -Config $config -Path 'api.corsAllowOrigins') | Where-Object { $_ } | Select-Object -Unique)
$settings = @(
    "SCM_DO_BUILD_DURING_DEPLOYMENT=true",
    "WEBSITES_CONTAINER_START_TIME_LIMIT=$ContainerStartTimeLimitSeconds",
    "PUBLIC_API_URL=$apiUrl",
    "CORS_ALLOW_ORIGINS=$($corsOrigins -join ',')",
    "FOUNDRY_PROJECT_ENDPOINT=$foundryProjectEndpoint",
    "APIM_BASE_URL=$(Get-ConfigValue -Config $config -Path 'apim.gatewayUrl')",
    "DATABRICKS_WORKSPACE_URL=$(Get-ConfigValue -Config $config -Path 'databricks.workspaceUrl')",
    "GITHUB_REPO_URL=$(Get-ConfigValue -Config $config -Path 'api.githubRepoUrl')",
    "TEAMS_APP_ID_NAMESPACE=$(Get-ConfigValue -Config $config -Path 'api.teamsAppIdNamespace')",
    "DATABRICKS_CATALOG=$(Get-ConfigValue -Config $config -Path 'databricks.catalog')",
    "DATABRICKS_SCHEMA=$(Get-ConfigValue -Config $config -Path 'databricks.schema')",
    "DATABRICKS_SQL_FOUNDRY_AGENT_NAME=$(Get-ConfigValue -Config $config -Path 'api.agents.sqlFoundryName')",
    "DATABRICKS_GENIE_FOUNDRY_AGENT_NAME=$(Get-ConfigValue -Config $config -Path 'api.agents.genieFoundryName')",
    "API_TITLE=$(Get-ConfigValue -Config $config -Path 'api.title')",
    "API_VERSION=$(Get-ConfigValue -Config $config -Path 'api.version')",
    "API_CONTACT_NAME=$(Get-ConfigValue -Config $config -Path 'api.contactName')",
    "API_LICENSE_NAME=$(Get-ConfigValue -Config $config -Path 'api.licenseName')",
    "REQUEST_TIMEOUT_SECONDS=$(Get-ConfigValue -Config $config -Path 'api.requestTimeoutSeconds')",
    "JOB_TTL_SECONDS=$(Get-ConfigValue -Config $config -Path 'api.jobTtlSeconds')",
    "MAX_JOBS=$(Get-ConfigValue -Config $config -Path 'api.maxJobs')",
    "CHAT_JOB_WORKERS=$(Get-ConfigValue -Config $config -Path 'api.chatJobWorkers')",
    "MAX_MCP_APPROVAL_ROUNDS=$(Get-ConfigValue -Config $config -Path 'foundry.maxMcpApprovalRounds')",
    "TEAMS_MANIFEST_VERSION=$(Get-ConfigValue -Config $config -Path 'api.teamsManifestVersion')",
    "DECLARATIVE_AGENT_VERSION=$(Get-ConfigValue -Config $config -Path 'api.declarativeAgentVersion')",
    "PLUGIN_SCHEMA_VERSION=$(Get-ConfigValue -Config $config -Path 'api.pluginSchemaVersion')",
    "M365_DEVELOPER_NAME=$(Get-ConfigValue -Config $config -Path 'api.m365DeveloperName')",
    "M365_APP_VERSION=$(Get-ConfigValue -Config $config -Path 'api.m365AppVersion')",
    "M365_NAME_SUFFIX=$(Get-ConfigValue -Config $config -Path 'api.m365NameSuffix')"
)
Invoke-Az (@("webapp", "config", "appsettings", "set", "-g", $ResourceGroup, "-n", $ApiAppName, "-o", "none", "--settings") + $settings) | Out-Null

# Keep the worker count aligned with the API's in-process chat job store.
$startup = "gunicorn app.main:app -k uvicorn.workers.UvicornWorker --workers $GunicornWorkers --threads $GunicornThreads --timeout $GunicornTimeoutSeconds --bind $GunicornBind"
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
