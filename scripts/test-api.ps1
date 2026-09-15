<#
.SYNOPSIS
  End-to-end smoke test of the Databricks Agents API.

.DESCRIPTION
  Checks the health, catalog, Swagger and Microsoft 365 package endpoints, then
  runs one asynchronous chat turn per agent and downloads any generated file.

.EXAMPLE
  ./scripts/test-api.ps1
    ./scripts/test-api.ps1 -BaseUrl https://<api-app>.azurewebsites.net
#>
[CmdletBinding()]
param(
        [string] $ConfigPath = (Join-Path $PSScriptRoot '../config/deployment.json'),
        [string] $BaseUrl,
        [string[]] $AgentIds,
        [string] $Message,
        [Nullable[int]] $TimeoutSeconds,
        [string] $OutputDir,
        [int] $RequestTimeoutSeconds = 60,
        [int] $PackageDownloadTimeoutSeconds = 120,
        [int] $PollIntervalSeconds = 5,
        [int] $GeneratedFileDownloadTimeoutSeconds = 300
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot 'config.ps1')

$config = Get-DeploymentConfig -Path $ConfigPath
$BaseUrl = (Get-ConfigValue -Config $config -Path 'tests.localApiBaseUrl' -Override $BaseUrl).TrimEnd('/')
$AgentIds = @(Get-ConfigValue -Config $config -Path 'tests.agentIds' -Override $AgentIds)
$Message = Get-ConfigValue -Config $config -Path 'tests.apiPrompt' -Override $Message
$TimeoutSeconds = [int](Get-ConfigValue -Config $config -Path 'tests.timeoutSeconds' -Override $TimeoutSeconds)
$OutputDir = Get-ConfigValue -Config $config -Path 'tests.outputDirectory' -Override $OutputDir

function Get-Json($path) { Invoke-RestMethod -Uri "$BaseUrl$path" -TimeoutSec $RequestTimeoutSeconds }

Write-Host "== health ==" -ForegroundColor Cyan
(Get-Json "/health") | ConvertTo-Json -Compress

Write-Host "== swagger ==" -ForegroundColor Cyan
foreach ($path in @("/openapi.json", "/docs", "/redoc")) {
    $code = (Invoke-WebRequest -Uri "$BaseUrl$path" -UseBasicParsing -TimeoutSec $RequestTimeoutSeconds).StatusCode
    Write-Host "  $path -> $code"
}

Write-Host "== agents ==" -ForegroundColor Cyan
foreach ($agent in (Get-Json "/api/agents")) { Write-Host "  $($agent.id): $($agent.displayName)" }

Write-Host "== microsoft 365 packages ==" -ForegroundColor Cyan
foreach ($package in (Get-Json "/api/m365/packages")) {
    $zip = Invoke-WebRequest -Uri "$BaseUrl/api/m365/packages/$($package.agentId)" -UseBasicParsing -TimeoutSec $PackageDownloadTimeoutSeconds
    Write-Host "  $($package.fileName): $($zip.RawContentLength) bytes, appId $($package.teamsAppId)"
}

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

foreach ($agentId in $AgentIds) {
    Write-Host "== chat: $agentId ==" -ForegroundColor Cyan
    $job = Invoke-RestMethod -Method POST -Uri "$BaseUrl/api/agents/$agentId/chat" `
        -ContentType "application/json" -Body (@{ message = $Message } | ConvertTo-Json) -TimeoutSec $RequestTimeoutSeconds
    Write-Host "  jobId=$($job.jobId)"

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        Start-Sleep -Seconds $PollIntervalSeconds
        $state = Invoke-RestMethod -Uri "$BaseUrl/api/chat/jobs/$($job.jobId)" -TimeoutSec $RequestTimeoutSeconds
    } while ($state.status -eq "running" -and (Get-Date) -lt $deadline)

    if ($state.status -ne "completed") { throw "Chat job for $agentId ended as '$($state.status)': $($state.error)" }

    $result = $state.result
    Write-Host "  toolCalls: $($result.toolCalls -join ', ')"
    $preview = $result.reply -replace "\s+", " "
    Write-Host "  reply: $($preview.Substring(0, [Math]::Min(220, $preview.Length)))..."

    foreach ($file in $result.files) {
        $target = Join-Path $OutputDir "$agentId-$($file.filename)"
        Invoke-WebRequest -Uri $file.downloadUrl -OutFile $target -UseBasicParsing -TimeoutSec $GeneratedFileDownloadTimeoutSeconds
        $size = (Get-Item $target).Length
        Write-Host "  downloaded $target ($size bytes)" -ForegroundColor Green
        if ($target.ToLower().EndsWith(".pptx")) {
            Add-Type -AssemblyName System.IO.Compression
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            $archive = [System.IO.Compression.ZipFile]::OpenRead((Resolve-Path $target))
            $hasDeck = @($archive.Entries | Where-Object { $_.FullName -eq "ppt/presentation.xml" }).Count -eq 1
            $archive.Dispose()
            if (-not $hasDeck) { throw "$target is not a valid PowerPoint package" }
            Write-Host "  validated Office Open XML package" -ForegroundColor Green
        }
    }
}

Write-Host ""
Write-Host "API smoke test passed." -ForegroundColor Green
