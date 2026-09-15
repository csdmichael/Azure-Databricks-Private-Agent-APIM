[CmdletBinding()]
param(
    [string] $ConfigPath = (Join-Path $PSScriptRoot '../config/deployment.json'),
    [string] $SubscriptionId,
    [string] $ResourceGroup,
    [string] $FunctionName,
    [string] $JumpVmName,
    [Nullable[int]] $JwkFetchTimeoutMs,
    [Nullable[int]] $TokenExchangeTimeoutMs,
    [string] $NodeReleaseChannel = 'v22.x',
    [int] $NodeMetadataTimeoutSeconds = 60,
    [int] $NodeDownloadTimeoutSeconds = 180,
    [int] $KuduDeploymentTimeoutSeconds = 600,
    [int] $KuduStatusTimeoutSeconds = 60,
    [int] $RunCommandTimeoutSeconds = 1200,
    [int] $ArmRequestTimeoutSeconds = 1500,
    [string] $RunCommandName,
    [switch] $PrepareOnly
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'config.ps1')

$config = Get-DeploymentConfig -Path $ConfigPath
$SubscriptionId = Get-ConfigValue -Config $config -Path 'azure.subscriptionId' -Override $SubscriptionId
$ResourceGroup = Get-ConfigValue -Config $config -Path 'azure.resourceGroup' -Override $ResourceGroup
$FunctionName = Get-ConfigValue -Config $config -Path 'obo.functionName' -Override $FunctionName
$JumpVmName = Get-ConfigValue -Config $config -Path 'obo.jumpVmName' -Override $JumpVmName
$JwkFetchTimeoutMs = [int](Get-ConfigValue -Config $config -Path 'obo.jwkFetchTimeoutMs' -Override $JwkFetchTimeoutMs)
$TokenExchangeTimeoutMs = [int](Get-ConfigValue -Config $config -Path 'obo.tokenExchangeTimeoutMs' -Override $TokenExchangeTimeoutMs)
if ([string]::IsNullOrWhiteSpace($RunCommandName)) { $RunCommandName = "$FunctionName-code-deploy" }

$root = Split-Path -Parent $PSScriptRoot
$project = Join-Path $root 'functions/genie-token-exchange'
npm test --prefix $project
if ($LASTEXITCODE -ne 0) { throw 'Broker build or tests failed.' }
$files = @{}
foreach ($relative in @('package.json', 'package-lock.json', 'host.json')) {
    $files[$relative] = [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $project $relative)))
}
foreach ($file in Get-ChildItem (Join-Path $project 'dist/src') -File -Recurse) {
    $relative = $file.FullName.Substring($project.Length + 1).Replace('\', '/')
    $files[$relative] = [Convert]::ToBase64String([IO.File]::ReadAllBytes($file.FullName))
}
$payload = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($files | ConvertTo-Json -Compress)))
$remoteScript = @'
param(
    [string] $ArmToken,
    [string] $FunctionName,
    [string] $NodeReleaseChannel,
    [int] $NodeMetadataTimeoutSeconds,
    [int] $NodeDownloadTimeoutSeconds,
    [int] $KuduDeploymentTimeoutSeconds,
    [int] $KuduStatusTimeoutSeconds
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$stage = Join-Path $env:TEMP ('genie-obo-' + [guid]::NewGuid().ToString('N'))
$phase = 'prepare'
try {
    $app = Join-Path $stage 'app'
    New-Item -ItemType Directory -Path $app -Force | Out-Null
    $files = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('__PAYLOAD__')) | ConvertFrom-Json
    foreach ($file in $files.PSObject.Properties) {
        $path = Join-Path $app $file.Name
        New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null
        [IO.File]::WriteAllBytes($path, [Convert]::FromBase64String($file.Value))
    }
    $phase = 'node-download'
    $nodeBaseUrl = "https://nodejs.org/dist/latest-$NodeReleaseChannel"
    $checksums = (Invoke-WebRequest -UseBasicParsing -Uri "$nodeBaseUrl/SHASUMS256.txt" -TimeoutSec $NodeMetadataTimeoutSeconds).Content
    $checksum = @($checksums -split "`n" | Where-Object { $_ -match '^([a-f0-9]{64})\s+(node-v[0-9]+\.[0-9]+\.[0-9]+-win-x64\.zip)\s*$' })
    if ($checksum.Count -ne 1) { throw 'Node checksum selection failed.' }
    $parts = $checksum[0].Trim() -split '\s+'
    $nodeZip = Join-Path $stage 'node.zip'
    Invoke-WebRequest -UseBasicParsing -Uri ("$nodeBaseUrl/" + $parts[1]) -OutFile $nodeZip -TimeoutSec $NodeDownloadTimeoutSeconds
    if ((Get-FileHash $nodeZip -Algorithm SHA256).Hash -ne $parts[0]) { throw 'Node checksum mismatch.' }
    Expand-Archive $nodeZip -DestinationPath $stage
    $nodeDirectory = Join-Path $stage ($parts[1] -replace '\.zip$', '')
    $env:PATH = $nodeDirectory + ';' + $env:PATH
    $phase = 'dependencies'
    & (Join-Path $nodeDirectory 'npm.cmd') ci --prefix $app --omit=dev --ignore-scripts --no-audit --no-fund *> (Join-Path $stage 'npm.log')
    if ($LASTEXITCODE -ne 0) { throw 'Production dependency installation failed.' }
    $phase = 'package'
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zipPath = Join-Path $stage 'app.zip'
    $archive = [IO.Compression.ZipFile]::Open($zipPath, [IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($file in Get-ChildItem $app -File -Recurse) {
            $entry = $file.FullName.Substring($app.Length + 1).Replace('\', '/')
            [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $file.FullName, $entry, [IO.Compression.CompressionLevel]::Optimal) | Out-Null
        }
    } finally { $archive.Dispose() }
    $phase = 'private-zipdeploy'
    Invoke-WebRequest -UseBasicParsing -Method POST -Uri "https://$FunctionName.scm.azurewebsites.net/api/zipdeploy?isAsync=false" -Headers @{ Authorization = "Bearer $ArmToken" } -ContentType 'application/zip' -InFile $zipPath -TimeoutSec $KuduDeploymentTimeoutSeconds | Out-Null
    $phase = 'verify-deployment'
    $deployment = Invoke-RestMethod -Uri "https://$FunctionName.scm.azurewebsites.net/api/deployments/latest" -Headers @{ Authorization = "Bearer $ArmToken" } -TimeoutSec $KuduStatusTimeoutSeconds
    if ($deployment.status -ne 4) { throw 'Kudu deployment has not succeeded.' }
    [pscustomobject]@{ status = 'Succeeded'; deploymentId = $deployment.id; packageBytes = (Get-Item $zipPath).Length } | ConvertTo-Json -Compress
} catch {
    Write-Output ("Broker deployment failed at phase: " + $phase)
    if ($phase -eq 'dependencies' -and (Test-Path (Join-Path $stage 'npm.log'))) {
        Get-Content (Join-Path $stage 'npm.log') -Tail 25 | Write-Output
    }
    exit 1
} finally {
    $ArmToken = $null
    if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
}
'@
$remoteScript = $remoteScript.Replace('__PAYLOAD__', $payload)
$syntaxErrors = $null
[Management.Automation.Language.Parser]::ParseInput($remoteScript, [ref]$null, [ref]$syntaxErrors) | Out-Null
if ($syntaxErrors.Count) { throw 'Generated deployment script has syntax errors.' }
if ($PrepareOnly) {
    [pscustomobject]@{ fileCount = $files.Count; scriptBytes = [Text.Encoding]::UTF8.GetByteCount($remoteScript); syntax = 'Passed' }
    return
}
$context = az account show -o json | ConvertFrom-Json
if ($LASTEXITCODE -ne 0 -or $context.id -ne $SubscriptionId) { throw 'Select the intended subscription before deployment.' }
az functionapp config appsettings set --subscription $SubscriptionId --resource-group $ResourceGroup --name $FunctionName --settings "JWK_FETCH_TIMEOUT_MS=$JwkFetchTimeoutMs" "TOKEN_EXCHANGE_TIMEOUT_MS=$TokenExchangeTimeoutMs" -o none --only-show-errors
if ($LASTEXITCODE -ne 0) { throw 'Could not apply the configured OBO timeout settings.' }
$vm = az vm show -g $ResourceGroup -n $JumpVmName --subscription $SubscriptionId -o json | ConvertFrom-Json
if ($LASTEXITCODE -ne 0 -or $vm.storageProfile.osDisk.osType -ne 'Windows') { throw 'A Windows jump VM is required.' }
$armToken = az account get-access-token --resource https://management.azure.com/ --query accessToken -o tsv
if ($LASTEXITCODE -ne 0) { throw 'ARM authentication failed.' }
try {
    $runCommandId = "$($vm.id)/runCommands/$RunCommandName"
    $body = @{
        location = $vm.location
        properties = @{
            source = @{ script = $remoteScript }
            parameters = @(
                @{ name = 'FunctionName'; value = $FunctionName }
                @{ name = 'NodeReleaseChannel'; value = $NodeReleaseChannel }
                @{ name = 'NodeMetadataTimeoutSeconds'; value = [string]$NodeMetadataTimeoutSeconds }
                @{ name = 'NodeDownloadTimeoutSeconds'; value = [string]$NodeDownloadTimeoutSeconds }
                @{ name = 'KuduDeploymentTimeoutSeconds'; value = [string]$KuduDeploymentTimeoutSeconds }
                @{ name = 'KuduStatusTimeoutSeconds'; value = [string]$KuduStatusTimeoutSeconds }
            )
            protectedParameters = @(@{ name = 'ArmToken'; value = $armToken })
            asyncExecution = $false
            timeoutInSeconds = $RunCommandTimeoutSeconds
            treatFailureAsDeploymentFailure = $true
        }
    } | ConvertTo-Json -Depth 10
    $result = Invoke-RestMethod -Method PUT -Uri "https://management.azure.com${runCommandId}?api-version=2023-03-01" -Headers @{ Authorization = "Bearer $armToken" } -ContentType 'application/json' -Body $body -TimeoutSec $ArmRequestTimeoutSeconds
    [pscustomobject]@{ runCommandId = $runCommandId; provisioningState = $result.properties.provisioningState }
} finally { $armToken = $null; $body = $null; $result = $null }