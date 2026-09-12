[CmdletBinding()]
param(
    [string] $SubscriptionId = 'cf824570-a8ba-497a-a184-0a52f1830aa9',
    [string] $ResourceGroup = 'm365-myaacoub',
    [string] $AppName = 'caldova-databricks-showcase',
    [string] $TenantId = '12a4b86b-e64c-43f9-af05-d9130a72dfd2',
    [string[]] $AdminObjectIds = @('715bb744-31d0-4f76-ac85-7193bcf5a4eb'),
    [switch] $SkipInfrastructure,
    [switch] $ResumeConfiguration,
    [switch] $SkipBuild,
    [switch] $InfrastructureOnly
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
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
        $settings = Invoke-RestMethod -Method POST -Headers $headers -Uri "https://management.azure.com$siteId/config/appsettings/list?api-version=2023-12-01"
        foreach ($key in $Values.Keys) { $settings.properties | Add-Member -NotePropertyName $key -NotePropertyValue $Values[$key] -Force }
        $body = @{ properties = $settings.properties } | ConvertTo-Json -Depth 10
        Invoke-RestMethod -Method PUT -Headers $headers -ContentType 'application/json' -Body $body -Uri "https://management.azure.com$siteId/config/appsettings?api-version=2023-12-01" | Out-Null
    } finally { $armToken = $null; $headers = $null; $body = $null; $settings = $null }
}

if (-not $SkipInfrastructure) {
    $site = Invoke-AzJson @('resource', 'show', '--ids', $siteId, '--api-version', '2023-12-01')
    $planId = $site.properties.serverFarmId
    $plan = Invoke-AzJson @('resource', 'show', '--ids', $planId, '--api-version', '2023-12-01')
    if ($plan.sku.name -eq 'F1') { throw 'Upgrade the existing plan to B1 or higher with approval before deploying.' }
    $identity = Invoke-AzJson @('webapp', 'identity', 'assign', '-g', $ResourceGroup, '-n', $AppName)
    $displayName = 'Caldova Showcase Statistics'
    $apps = @(az ad app list --display-name $displayName -o json --only-show-errors | ConvertFrom-Json)
    if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect Entra applications.' }
    if ($apps.Count -gt 1) { throw 'Ambiguous Showcase app registration.' }
    $registration = $apps | Select-Object -First 1
    if (-not $registration) {
        $registration = az ad app create --display-name $displayName --sign-in-audience AzureADMyOrg --web-redirect-uris "https://$AppName.azurewebsites.net/.auth/login/aad/callback" --enable-id-token-issuance true -o json --only-show-errors | ConvertFrom-Json
        if ($LASTEXITCODE -ne 0) { throw 'Cannot create Showcase Entra registration.' }
    }
    $sp = az ad sp list --filter "appId eq '$($registration.appId)'" -o json --only-show-errors | ConvertFrom-Json
    if (-not $sp) { az ad sp create --id $registration.appId -o none --only-show-errors; if ($LASTEXITCODE -ne 0) { throw 'Cannot create application principal.' } }
    $graphToken = az account get-access-token --resource https://graph.microsoft.com --query accessToken -o tsv
    if ($LASTEXITCODE -ne 0) { throw 'Graph authentication failed.' }
    try {
        $password = Invoke-RestMethod -Method POST -Headers @{ Authorization = "Bearer $graphToken" } -ContentType 'application/json' -Uri "https://graph.microsoft.com/v1.0/applications/$($registration.id)/addPassword" -Body (@{ passwordCredential = @{ displayName = 'Showcase EasyAuth'; endDateTime = [DateTime]::UtcNow.AddMonths(6).ToString('o') } } | ConvertTo-Json)
        Set-AppSettings @{ SHOWCASE_AUTH_CLIENT_SECRET = $password.secretText; ENTRA_TENANT_ID = $TenantId; STATS_ADMIN_OBJECT_IDS = ($AdminObjectIds -join ','); WEBSITE_NODE_DEFAULT_VERSION = '~24' }
    } finally { $graphToken = $null; $password = $null }
    $deployment = Invoke-AzJson @('deployment', 'group', 'create', '-g', $ResourceGroup, '-n', 'showcase-analytics', '-f', "$root/bicep/showcase-analytics/main.bicep", '-p', "webPrincipalId=$($identity.principalId)", "authClientId=$($registration.appId)", "webAppName=$AppName", "tenantId=$TenantId")
}
if (-not $SkipInfrastructure -or $ResumeConfiguration) {
    $deployment = Invoke-AzJson @('deployment', 'group', 'show', '-g', $ResourceGroup, '-n', 'showcase-analytics')
    if ($deployment.properties.provisioningState -ne 'Succeeded') { throw 'Analytics infrastructure deployment has not succeeded.' }
    Set-AppSettings @{
        COSMOS_ENDPOINT = $deployment.properties.outputs.cosmosEndpoint.value
        LOG_ANALYTICS_WORKSPACE_ID = 'b41e5454-7d6c-4764-ba87-fa8174e71e1c'
        LOG_ANALYTICS_RESOURCE_ID = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.Insights/components/caldova-genie-obo-insights"
    }
    az webapp vnet-integration add -g $ResourceGroup -n $AppName --vnet 'caldova-dbx-vnet-westus2' --subnet 'genie-obo-integration' --subscription $SubscriptionId -o none --only-show-errors
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
$artifactDir = Join-Path $root 'artifacts/showcase'
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
Set-AppSettings @{ WEBSITE_RUN_FROM_PACKAGE = '1' }
az webapp deploy -g $ResourceGroup -n $AppName --subscription $SubscriptionId --src-path $zipPath --type zip --async false --timeout 600000 -o none --only-show-errors
if ($LASTEXITCODE -ne 0) { throw 'Showcase deployment failed; inspect Kudu deployment status before retrying.' }
az webapp restart -g $ResourceGroup -n $AppName --subscription $SubscriptionId -o none --only-show-errors
if ($LASTEXITCODE -ne 0) { throw 'Showcase restart failed.' }
Write-Host "Showcase: https://$AppName.azurewebsites.net/showcase"
Write-Host "Traffic: https://$AppName.azurewebsites.net/stats"