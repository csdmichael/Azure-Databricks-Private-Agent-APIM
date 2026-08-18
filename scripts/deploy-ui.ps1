<#
.SYNOPSIS
  Builds the Angular/Ionic UI and deploys it to the Azure Static Web App.

.DESCRIPTION
  Uses the Static Web Apps CLI with a deployment token read at run time from
  Azure. The token stays in-process and is never written to disk or echoed.

.EXAMPLE
  ./scripts/deploy-ui.ps1
#>
[CmdletBinding()]
param(
    [string] $ResourceGroup = "ai-myaacoub",
    [string] $UiAppName = "databricks-agents-ui-my",
    [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$uiDir = Join-Path $repoRoot "ui"

if (-not $SkipBuild) {
    Write-Host "Building the UI (production)..." -ForegroundColor Cyan
    npm --prefix $uiDir run build -- --configuration production | Out-String | Write-Host
    if ($LASTEXITCODE -ne 0) { throw "UI build failed." }
}

$previous = $ErrorActionPreference
$ErrorActionPreference = "Continue"
try {
    $token = az staticwebapp secrets list -g $ResourceGroup -n $UiAppName --query "properties.apiKey" -o tsv 2>&1
}
finally { $ErrorActionPreference = $previous }
if ($LASTEXITCODE -ne 0 -or -not $token) { throw "Could not read the Static Web App deployment token." }

Write-Host "Deploying to $UiAppName ..." -ForegroundColor Yellow
try {
    # Pinned: newer CLI builds pull @azure/core-process, which some npm feeds do not mirror.
    npx --yes @azure/static-web-apps-cli@2.0.6 deploy (Join-Path $uiDir "www") `
        --deployment-token $token --env production | Out-String | Write-Host
    if ($LASTEXITCODE -ne 0) { throw "Static Web Apps deployment failed." }
}
finally {
    Remove-Variable token -ErrorAction SilentlyContinue
    [System.GC]::Collect()
}

$previous = $ErrorActionPreference
$ErrorActionPreference = "Continue"
try { $uiHost = az staticwebapp show -g $ResourceGroup -n $UiAppName --query defaultHostname -o tsv 2>&1 }
finally { $ErrorActionPreference = $previous }

Write-Host "UI: https://$uiHost" -ForegroundColor Green
