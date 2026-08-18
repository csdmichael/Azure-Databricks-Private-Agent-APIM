<#
.SYNOPSIS
  Packages and deploys the Databricks Agents API to Azure App Service.

.DESCRIPTION
  Builds the zip with POSIX entry names (Windows-created archives with backslash
  entries do not extract correctly on Linux App Service), pushes it with
  `az webapp deploy`, then polls /health because the CLI can report a warm-up
  failure while the Oryx build is still finishing server side.

.EXAMPLE
  ./scripts/deploy-api.ps1
#>
[CmdletBinding()]
param(
    [string] $ResourceGroup = "ai-myaacoub",
    [string] $ApiAppName = "databricks-agents-api-my",
    [int] $HealthTimeoutSeconds = 900
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$apiDir = Join-Path $repoRoot "api"
$zipPath = Join-Path $repoRoot "artifacts/api.zip"
$python = Join-Path $repoRoot ".venv/Scripts/python.exe"
if (-not (Test-Path $python)) { $python = "python" }

New-Item -ItemType Directory -Force -Path (Split-Path $zipPath) | Out-Null
Remove-Item $zipPath -ErrorAction SilentlyContinue

Write-Host "Packaging $apiDir ..." -ForegroundColor Cyan
$packScript = @'
import os, sys, zipfile
source, target = sys.argv[1], sys.argv[2]
skip_dirs = {"__pycache__", ".pytest_cache", ".venv", "antenv"}
with zipfile.ZipFile(target, "w", zipfile.ZIP_DEFLATED) as archive:
    for root, dirs, files in os.walk(source):
        dirs[:] = [d for d in dirs if d not in skip_dirs]
        for name in files:
            if name.endswith((".pyc", ".pyo")):
                continue
            full = os.path.join(root, name)
            archive.write(full, os.path.relpath(full, source).replace("\\", "/"))
print(os.path.getsize(target), "bytes")
'@
$packFile = New-TemporaryFile
Set-Content -Path $packFile -Value $packScript -Encoding utf8
& $python $packFile.FullName $apiDir $zipPath
Remove-Item $packFile -ErrorAction SilentlyContinue
if ($LASTEXITCODE -ne 0) { throw "Packaging failed." }

Write-Host "Deploying to $ApiAppName ..." -ForegroundColor Yellow
$previous = $ErrorActionPreference
$ErrorActionPreference = "Continue"
try {
    az webapp deploy --resource-group $ResourceGroup --name $ApiAppName `
        --src-path $zipPath --type zip --async false 2>&1 | Out-String | Write-Host
}
finally { $ErrorActionPreference = $previous }

# The CLI exit code is unreliable during warm-up, so health is the real signal.
$healthUrl = "https://$ApiAppName.azurewebsites.net/health"
Write-Host "Waiting for $healthUrl ..." -ForegroundColor Cyan
$deadline = (Get-Date).AddSeconds($HealthTimeoutSeconds)
while ((Get-Date) -lt $deadline) {
    try {
        $response = Invoke-RestMethod -Uri $healthUrl -TimeoutSec 30
        if ($response.status -eq "ok") {
            Write-Host "Healthy: $($response | ConvertTo-Json -Compress)" -ForegroundColor Green
            Write-Host "Swagger: https://$ApiAppName.azurewebsites.net/docs" -ForegroundColor Green
            exit 0
        }
    }
    catch { Write-Host "  not ready yet..." -ForegroundColor DarkGray }
    Start-Sleep -Seconds 15
}
throw "The API did not become healthy within $HealthTimeoutSeconds seconds."
