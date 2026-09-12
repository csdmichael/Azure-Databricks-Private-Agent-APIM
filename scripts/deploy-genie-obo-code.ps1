[CmdletBinding()]
param(
    [string] $SubscriptionId = 'cf824570-a8ba-497a-a184-0a52f1830aa9',
    [string] $ResourceGroup = 'm365-myaacoub',
    [string] $FunctionName = 'caldova-genie-obo-fn',
    [string] $JumpVmName = 'caldova-jump',
    [switch] $PrepareOnly
)
$ErrorActionPreference = 'Stop'
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
param([string] $ArmToken, [string] $FunctionName)
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
    $checksums = (Invoke-WebRequest -UseBasicParsing -Uri 'https://nodejs.org/dist/latest-v22.x/SHASUMS256.txt' -TimeoutSec 60).Content
    $checksum = @($checksums -split "`n" | Where-Object { $_ -match '^([a-f0-9]{64})\s+(node-v22\.[0-9]+\.[0-9]+-win-x64\.zip)\s*$' })
    if ($checksum.Count -ne 1) { throw 'Node checksum selection failed.' }
    $parts = $checksum[0].Trim() -split '\s+'
    $nodeZip = Join-Path $stage 'node.zip'
    Invoke-WebRequest -UseBasicParsing -Uri ('https://nodejs.org/dist/latest-v22.x/' + $parts[1]) -OutFile $nodeZip -TimeoutSec 180
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
    Invoke-WebRequest -UseBasicParsing -Method POST -Uri "https://$FunctionName.scm.azurewebsites.net/api/zipdeploy?isAsync=false" -Headers @{ Authorization = "Bearer $ArmToken" } -ContentType 'application/zip' -InFile $zipPath -TimeoutSec 600 | Out-Null
    $phase = 'verify-deployment'
    $deployment = Invoke-RestMethod -Uri "https://$FunctionName.scm.azurewebsites.net/api/deployments/latest" -Headers @{ Authorization = "Bearer $ArmToken" } -TimeoutSec 60
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
$vm = az vm show -g $ResourceGroup -n $JumpVmName --subscription $SubscriptionId -o json | ConvertFrom-Json
if ($LASTEXITCODE -ne 0 -or $vm.storageProfile.osDisk.osType -ne 'Windows') { throw 'A Windows jump VM is required.' }
$armToken = az account get-access-token --resource https://management.azure.com/ --query accessToken -o tsv
if ($LASTEXITCODE -ne 0) { throw 'ARM authentication failed.' }
try {
    $runCommandId = "$($vm.id)/runCommands/genie-obo-code"
    $body = @{
        location = $vm.location
        properties = @{
            source = @{ script = $remoteScript }
            parameters = @(@{ name = 'FunctionName'; value = $FunctionName })
            protectedParameters = @(@{ name = 'ArmToken'; value = $armToken })
            asyncExecution = $false
            timeoutInSeconds = 1200
            treatFailureAsDeploymentFailure = $true
        }
    } | ConvertTo-Json -Depth 10
    $result = Invoke-RestMethod -Method PUT -Uri "https://management.azure.com${runCommandId}?api-version=2023-03-01" -Headers @{ Authorization = "Bearer $armToken" } -ContentType 'application/json' -Body $body -TimeoutSec 1500
    [pscustomobject]@{ runCommandId = $runCommandId; provisioningState = $result.properties.provisioningState }
} finally { $armToken = $null; $body = $null; $result = $null }