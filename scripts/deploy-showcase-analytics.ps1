[CmdletBinding()]
param(
    [string] $ConfigPath = (Join-Path $PSScriptRoot '../config/deployment.json'),
    [string] $SubscriptionId,
    [string] $ResourceGroup,
    [string] $AppName,
    [string] $TenantId,
    [string[]] $AdminObjectIds,
    [string] $ApplicationDisplayName,
    [string] $DeploymentName = 'showcase-analytics',
    [string] $ArtifactDirectory,
    [string] $NodeVersion = '~24',
    [int] $CredentialLifetimeMonths = 6,
    [string] $CosmosDatabase,
    [string] $CosmosContainer,
    [Nullable[int]] $CosmosRequestTimeoutMs,
    [Nullable[int]] $CosmosMaxRetryAttempts,
    [Nullable[int]] $CosmosMaxRetryWaitSeconds,
    [string] $LogAnalyticsWorkspaceId,
    [string] $LogAnalyticsResourceId,
    [Nullable[int]] $LogAnalyticsQueryTimeoutMs,
    [Nullable[int]] $LogAnalyticsQueryMaxResults,
    [Nullable[int]] $AnalyticsTtlSeconds,
    [string] $DatabricksVnetName,
    [string] $IntegrationSubnetName,
    [Nullable[int]] $HealthTimeoutSeconds,
    [int] $ManagementRequestTimeoutSeconds = 60,
    [int] $RollbackDownloadTimeoutSeconds = 120,
    [int] $KuduConnectTimeoutSeconds = 30,
    [int] $KuduUploadTimeoutSeconds = 1200,
    [int] $PublicRetryCount = 24,
    [int] $PublicRetryDelaySeconds = 5,
    [int] $HealthProbeTimeoutSeconds = 15,
    [int] $PageRequestTimeoutSeconds = 30,
    [switch] $SkipInfrastructure,
    [switch] $ResumeConfiguration,
    [switch] $SkipBuild,
    [switch] $InfrastructureOnly
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'config.ps1')

$config = Get-DeploymentConfig -Path $ConfigPath
$SubscriptionId = Get-ConfigValue -Config $config -Path 'azure.subscriptionId' -Override $SubscriptionId
$ResourceGroup = Get-ConfigValue -Config $config -Path 'azure.resourceGroup' -Override $ResourceGroup
$AppName = Get-ConfigValue -Config $config -Path 'showcase.appName' -Override $AppName
$TenantId = Get-ConfigValue -Config $config -Path 'azure.tenantId' -Override $TenantId
$AdminObjectIds = @(Get-ConfigValue -Config $config -Path 'showcase.adminObjectIds' -Override $AdminObjectIds)
$ApplicationDisplayName = Get-ConfigValue -Config $config -Path 'showcase.applicationDisplayName' -Override $ApplicationDisplayName
$CosmosDatabase = Get-ConfigValue -Config $config -Path 'showcase.cosmosDatabase' -Override $CosmosDatabase
$CosmosContainer = Get-ConfigValue -Config $config -Path 'showcase.cosmosContainer' -Override $CosmosContainer
$CosmosRequestTimeoutMs = [int](Get-ConfigValue -Config $config -Path 'showcase.cosmosRequestTimeoutMs' -Override $CosmosRequestTimeoutMs)
$CosmosMaxRetryAttempts = [int](Get-ConfigValue -Config $config -Path 'showcase.cosmosMaxRetryAttempts' -Override $CosmosMaxRetryAttempts)
$CosmosMaxRetryWaitSeconds = [int](Get-ConfigValue -Config $config -Path 'showcase.cosmosMaxRetryWaitSeconds' -Override $CosmosMaxRetryWaitSeconds)
$LogAnalyticsWorkspaceId = Get-ConfigValue -Config $config -Path 'showcase.logAnalyticsWorkspaceId' -Override $LogAnalyticsWorkspaceId
$LogAnalyticsResourceId = Get-ConfigValue -Config $config -Path 'showcase.logAnalyticsResourceId' -Override $LogAnalyticsResourceId
$LogAnalyticsQueryTimeoutMs = [int](Get-ConfigValue -Config $config -Path 'showcase.logAnalyticsQueryTimeoutMs' -Override $LogAnalyticsQueryTimeoutMs)
$LogAnalyticsQueryMaxResults = [int](Get-ConfigValue -Config $config -Path 'showcase.logAnalyticsQueryMaxResults' -Override $LogAnalyticsQueryMaxResults)
$AnalyticsTtlSeconds = [int](Get-ConfigValue -Config $config -Path 'showcase.analyticsTtlSeconds' -Override $AnalyticsTtlSeconds)
$DatabricksVnetName = Get-ConfigValue -Config $config -Path 'network.databricksVnetName' -Override $DatabricksVnetName
$IntegrationSubnetName = Get-ConfigValue -Config $config -Path 'network.genieOboIntegrationSubnetName' -Override $IntegrationSubnetName
$HealthTimeoutSeconds = [int](Get-ConfigValue -Config $config -Path 'appService.healthTimeoutSeconds' -Override $HealthTimeoutSeconds)

$root = Split-Path -Parent $PSScriptRoot
$artifactDir = if ($ArtifactDirectory) { $ArtifactDirectory } else { Join-Path $root 'artifacts/showcase' }
$siteId = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.Web/sites/$AppName"
function Invoke-AzJson([string[]] $Arguments) {
    $result = & az @Arguments --subscription $SubscriptionId -o json --only-show-errors
    if ($LASTEXITCODE -ne 0) { throw "Azure command failed: $($Arguments[0..1] -join ' ')" }
    if ($result) { return ($result | ConvertFrom-Json) }
}
function Set-AppSettings([hashtable] $Values) {
    $armToken = az account get-access-token --resource https://management.azure.com --query accessToken -o tsv
    if ($LASTEXITCODE -ne 0) { throw 'ARM authentication failed.' }
    $headers = @{ Authorization = "Bearer $armToken" }
    try {
        $settings = Invoke-RestMethod -Method POST -Headers $headers -Uri "https://management.azure.com$siteId/config/appsettings/list?api-version=2023-12-01" -TimeoutSec $ManagementRequestTimeoutSeconds
        foreach ($key in $Values.Keys) { $settings.properties | Add-Member -NotePropertyName $key -NotePropertyValue $Values[$key] -Force }
        $body = @{ properties = $settings.properties } | ConvertTo-Json -Depth 10
        Invoke-RestMethod -Method PUT -Headers $headers -ContentType 'application/json' -Body $body -Uri "https://management.azure.com$siteId/config/appsettings?api-version=2023-12-01" -TimeoutSec $ManagementRequestTimeoutSeconds | Out-Null
    } finally { $armToken = $null; $headers = $null; $body = $null; $settings = $null }
}

$azureContext = az account show -o json | ConvertFrom-Json
if ($LASTEXITCODE -ne 0 -or $azureContext.id -ne $SubscriptionId -or $azureContext.tenantId -ne $TenantId) {
    throw 'Select the configured Azure subscription and tenant before deploying the showcase.'
}

if (-not $SkipInfrastructure) {
    $site = Invoke-AzJson @('resource', 'show', '--ids', $siteId, '--api-version', '2023-12-01')
    $planId = $site.properties.serverFarmId
    $plan = Invoke-AzJson @('resource', 'show', '--ids', $planId, '--api-version', '2023-12-01')
    if ($plan.sku.name -eq 'F1') { throw 'Upgrade the existing plan to B1 or higher with approval before deploying.' }
    $identity = Invoke-AzJson @('webapp', 'identity', 'assign', '-g', $ResourceGroup, '-n', $AppName)
    $apps = @(az ad app list --display-name $ApplicationDisplayName -o json --only-show-errors | ConvertFrom-Json)
    if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect Entra applications.' }
    if ($apps.Count -gt 1) { throw 'Ambiguous Showcase app registration.' }
    $registration = $apps | Select-Object -First 1
    if (-not $registration) {
        $registration = az ad app create --display-name $ApplicationDisplayName --sign-in-audience AzureADMyOrg --web-redirect-uris "https://$AppName.azurewebsites.net/.auth/login/aad/callback" --enable-id-token-issuance true -o json --only-show-errors | ConvertFrom-Json
        if ($LASTEXITCODE -ne 0) { throw 'Cannot create Showcase Entra registration.' }
    }
    $sp = az ad sp list --filter "appId eq '$($registration.appId)'" -o json --only-show-errors | ConvertFrom-Json
    if (-not $sp) { az ad sp create --id $registration.appId -o none --only-show-errors; if ($LASTEXITCODE -ne 0) { throw 'Cannot create application principal.' } }
    $graphToken = az account get-access-token --resource https://graph.microsoft.com --query accessToken -o tsv
    if ($LASTEXITCODE -ne 0) { throw 'Graph authentication failed.' }
    try {
        $password = Invoke-RestMethod -Method POST -Headers @{ Authorization = "Bearer $graphToken" } -ContentType 'application/json' -Uri "https://graph.microsoft.com/v1.0/applications/$($registration.id)/addPassword" -Body (@{ passwordCredential = @{ displayName = "$ApplicationDisplayName EasyAuth"; endDateTime = [DateTime]::UtcNow.AddMonths($CredentialLifetimeMonths).ToString('o') } } | ConvertTo-Json)
        Set-AppSettings @{ SHOWCASE_AUTH_CLIENT_SECRET = $password.secretText; ENTRA_TENANT_ID = $TenantId; STATS_ADMIN_OBJECT_IDS = ($AdminObjectIds -join ','); WEBSITE_NODE_DEFAULT_VERSION = $NodeVersion }
    } finally { $graphToken = $null; $password = $null }
    $deployment = Invoke-AzJson @('deployment', 'group', 'create', '-g', $ResourceGroup, '-n', $DeploymentName, '-f', "$root/bicep/showcase-analytics/main.bicep", '-p', "webPrincipalId=$($identity.principalId)", "authClientId=$($registration.appId)", "webAppName=$AppName", "tenantId=$TenantId")
}
if (-not $SkipInfrastructure -or $ResumeConfiguration) {
    $deployment = Invoke-AzJson @('deployment', 'group', 'show', '-g', $ResourceGroup, '-n', $DeploymentName)
    if ($deployment.properties.provisioningState -ne 'Succeeded') { throw 'Analytics infrastructure deployment has not succeeded.' }
    Set-AppSettings @{
        COSMOS_ENDPOINT = $deployment.properties.outputs.cosmosEndpoint.value
        COSMOS_DATABASE = $CosmosDatabase
        COSMOS_CONTAINER = $CosmosContainer
        COSMOS_REQUEST_TIMEOUT_MS = [string]$CosmosRequestTimeoutMs
        COSMOS_MAX_RETRY_ATTEMPTS = [string]$CosmosMaxRetryAttempts
        COSMOS_MAX_RETRY_WAIT_SECONDS = [string]$CosmosMaxRetryWaitSeconds
        LOG_ANALYTICS_WORKSPACE_ID = $LogAnalyticsWorkspaceId
        LOG_ANALYTICS_RESOURCE_ID = $LogAnalyticsResourceId
        LOG_ANALYTICS_QUERY_TIMEOUT_MS = [string]$LogAnalyticsQueryTimeoutMs
        LOG_ANALYTICS_QUERY_MAX_RESULTS = [string]$LogAnalyticsQueryMaxResults
        ANALYTICS_TTL_SECONDS = [string]$AnalyticsTtlSeconds
    }
    az webapp vnet-integration add -g $ResourceGroup -n $AppName --vnet $DatabricksVnetName --subnet $IntegrationSubnetName --subscription $SubscriptionId -o none --only-show-errors
    if ($LASTEXITCODE -ne 0) { throw 'VNet integration failed.' }
    az webapp config set -g $ResourceGroup -n $AppName --always-on true --use-32bit-worker-process false --ftps-state Disabled --min-tls-version 1.2 --subscription $SubscriptionId -o none --only-show-errors
    if ($LASTEXITCODE -ne 0) { throw 'Showcase runtime configuration failed.' }
}
if ($InfrastructureOnly) { return }
if (-not $SkipBuild) {
    npm ci --prefix "$root/showcase-server"
    if ($LASTEXITCODE -ne 0) { throw 'Server dependency installation failed.' }
    npm --prefix "$root/ui" run build -- --configuration production
    if ($LASTEXITCODE -ne 0) { throw 'UI build failed.' }
    npm test --prefix "$root/showcase-server"
    if ($LASTEXITCODE -ne 0) { throw 'Server tests failed.' }
}
New-Item -ItemType Directory -Path $artifactDir -Force | Out-Null
$zipPath = Join-Path $artifactDir "showcase-$([DateTime]::UtcNow.ToString('yyyyMMddHHmmss')).zip"
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::Open($zipPath, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($name in @('iisnode.js', 'server.js', 'analytics.js', 'history.js', 'package.json', 'package-lock.json', 'web.config')) {
        [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, "$root/showcase-server/$name", $name, [System.IO.Compression.CompressionLevel]::Fastest) | Out-Null
    }
    foreach ($source in @(@{ Directory = "$root/showcase-server/node_modules"; Prefix = 'node_modules' }, @{ Directory = "$root/ui/www"; Prefix = 'public' })) {
        $directory = (Resolve-Path $source.Directory).Path
        foreach ($file in Get-ChildItem $directory -File -Recurse) {
            $entry = $source.Prefix + '/' + $file.FullName.Substring($directory.Length + 1).Replace('\', '/')
            [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $file.FullName, $entry, [System.IO.Compression.CompressionLevel]::Fastest) | Out-Null
        }
    }
} finally { $archive.Dispose() }
$archive = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
try {
    $entries = @($archive.Entries.FullName)
    if (@($entries | Group-Object { $_.ToLowerInvariant() } | Where-Object Count -gt 1).Count -or
        @($entries | Where-Object { $_.Contains('\') }).Count -or
        'iisnode.js' -notin $entries -or 'public/index.html' -notin $entries) {
        throw 'Invalid deployment archive paths or missing runtime files.'
    }
} finally { $archive.Dispose() }
$armToken = az account get-access-token --resource https://management.azure.com --subscription $SubscriptionId --query accessToken -o tsv
if ($LASTEXITCODE -ne 0) { throw 'ARM authentication failed.' }
$scm = "https://$AppName.scm.azurewebsites.net"
$headers = @{ Authorization = "Bearer $armToken" }
try {
    $previousPackage = ([string](Invoke-WebRequest -UseBasicParsing -Uri "$scm/api/vfs/data/SitePackages/packagename.txt" -Headers $headers -TimeoutSec $ManagementRequestTimeoutSeconds).Content).Trim()
    if ($previousPackage -notmatch '^\d+\.zip$') { throw 'A valid mounted package is required for automatic rollback.' }
    Invoke-WebRequest -UseBasicParsing -Method HEAD -Uri "$scm/api/vfs/data/SitePackages/$previousPackage" -Headers $headers -TimeoutSec $ManagementRequestTimeoutSeconds | Out-Null
    $rollbackPath = Join-Path $artifactDir "rollback-$previousPackage"
    Invoke-WebRequest -UseBasicParsing -Uri "$scm/api/vfs/data/SitePackages/$previousPackage" -Headers $headers -OutFile $rollbackPath -TimeoutSec $RollbackDownloadTimeoutSeconds | Out-Null
    $rollbackArchive = [System.IO.Compression.ZipFile]::OpenRead($rollbackPath)
    try {
        if (-not $rollbackArchive.GetEntry('web.config') -or
            (-not $rollbackArchive.GetEntry('index.html') -and -not $rollbackArchive.GetEntry('public/index.html'))) {
            throw 'Rollback archive is missing the site configuration or SPA.'
        }
    } finally { $rollbackArchive.Dispose() }
    $settings = Invoke-RestMethod -Method POST -Headers $headers -Uri "https://management.azure.com$siteId/config/appsettings/list?api-version=2023-12-01" -TimeoutSec $ManagementRequestTimeoutSeconds
    try {
        if ($settings.properties.WEBSITE_RUN_FROM_PACKAGE -ne '1') { throw 'Rollback-protected deployment requires WEBSITE_RUN_FROM_PACKAGE=1.' }
    } finally { $settings = $null }
    try {
        & curl.exe --silent --show-error --fail --http1.1 -X POST -H "Authorization: Bearer $armToken" -H 'Content-Type: application/zip' -H 'Expect:' -T $zipPath --connect-timeout $KuduConnectTimeoutSeconds --max-time $KuduUploadTimeoutSeconds --output NUL "$scm/api/publish?type=zip&clean=true&restart=false"
        if ($LASTEXITCODE -ne 0) { throw 'Kudu publish upload failed.' }
        $latest = Invoke-RestMethod -Uri "$scm/api/deployments/latest" -Headers $headers -TimeoutSec $ManagementRequestTimeoutSeconds
        if ($latest.status -ne 4) { throw 'Kudu deployment did not succeed.' }
        az webapp restart -g $ResourceGroup -n $AppName --subscription $SubscriptionId -o none --only-show-errors
        if ($LASTEXITCODE -ne 0) { throw 'Showcase restart failed.' }
        $health = & curl.exe --silent --show-error --fail --retry $PublicRetryCount --retry-all-errors --retry-delay $PublicRetryDelaySeconds --retry-max-time $HealthTimeoutSeconds --max-time $HealthProbeTimeoutSeconds "https://$AppName.azurewebsites.net/api/health?verify=$([guid]::NewGuid())"
        if ($LASTEXITCODE -ne 0 -or ($health | ConvertFrom-Json).status -ne 'ok') { throw 'Showcase runtime health check failed.' }
        $showcase = Invoke-WebRequest -UseBasicParsing -Uri "https://$AppName.azurewebsites.net/showcase?verify=$([guid]::NewGuid())" -TimeoutSec $PageRequestTimeoutSeconds
        if ($showcase.Content -notmatch '<app-root') { throw 'Showcase SPA check failed.' }
        foreach ($route in @('api/visits/stats', 'api/exchanges/history')) {
            $status = & curl.exe --silent --show-error --output NUL --write-out '%{http_code}' --max-time $PageRequestTimeoutSeconds "https://$AppName.azurewebsites.net/$route"
            if ($LASTEXITCODE -ne 0 -or $status -ne '401') { throw 'Anonymous administrator API check failed.' }
        }
        Write-Host "Deployment verified: $($latest.id); rollback package: $previousPackage"
    } catch {
        $failure = $_
        $rollbackHeaders = @{ Authorization = "Bearer $armToken"; 'If-Match' = '*' }
        Invoke-WebRequest -UseBasicParsing -Method PUT -Uri "$scm/api/vfs/data/SitePackages/packagename.txt" -Headers $rollbackHeaders -ContentType 'text/plain; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($previousPackage)) -TimeoutSec $ManagementRequestTimeoutSeconds | Out-Null
        az webapp restart -g $ResourceGroup -n $AppName --subscription $SubscriptionId -o none --only-show-errors
        if ($LASTEXITCODE -ne 0) { throw 'Rollback package selected but restart failed; inspect the site immediately.' }
        & curl.exe --silent --show-error --fail --retry $PublicRetryCount --retry-all-errors --retry-delay $PublicRetryDelaySeconds --retry-max-time $HealthTimeoutSeconds --max-time $HealthProbeTimeoutSeconds --output NUL "https://$AppName.azurewebsites.net/showcase?rollback=$([guid]::NewGuid())"
        if ($LASTEXITCODE -ne 0) { throw 'Rollback package selected but public health is unverified; inspect the site immediately.' }
        throw "Deployment failed; previous package restored. $($failure.Exception.Message)"
    }
} finally { $armToken = $null; $headers = $null; $rollbackHeaders = $null }
Write-Host "Showcase: https://$AppName.azurewebsites.net/showcase"
Write-Host "Traffic: https://$AppName.azurewebsites.net/stats"