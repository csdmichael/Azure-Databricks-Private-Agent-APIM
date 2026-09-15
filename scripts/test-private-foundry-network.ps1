[CmdletBinding()]
param(
    [string] $ConfigPath = (Join-Path $PSScriptRoot '../config/deployment.json'),
    [string] $FoundryHost,
    [string] $ApimHost
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
. (Join-Path $PSScriptRoot 'config.ps1')

$config = Get-DeploymentConfig -Path $ConfigPath
if ([string]::IsNullOrWhiteSpace($FoundryHost)) {
    $FoundryHost = "$(Get-ConfigValue -Config $config -Path 'foundry.private.accountName').services.ai.azure.com"
}
if ([string]::IsNullOrWhiteSpace($ApimHost)) {
    $ApimHost = ([uri](Get-ConfigValue -Config $config -Path 'apim.gatewayUrl')).Host
}

function Test-PrivateAddress {
    param([string] $Address)

    return $Address -match '^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.)'
}

$foundryIps = @([System.Net.Dns]::GetHostAddresses($FoundryHost) | ForEach-Object { $_.IPAddressToString })
$apimIps = @([System.Net.Dns]::GetHostAddresses($ApimHost) | ForEach-Object { $_.IPAddressToString })

if (-not $foundryIps -or @($foundryIps | Where-Object { -not (Test-PrivateAddress $_) }).Count) {
    throw "Foundry did not resolve exclusively to private addresses: $($foundryIps -join ', ')"
}
if (-not $apimIps -or @($apimIps | Where-Object { -not (Test-PrivateAddress $_) }).Count) {
    throw "APIM did not resolve exclusively to private addresses: $($apimIps -join ', ')"
}
if (-not (Test-NetConnection $FoundryHost -Port 443 -InformationLevel Quiet)) {
    throw 'Foundry private endpoint is not reachable on TCP 443.'
}
if (-not (Test-NetConnection $ApimHost -Port 443 -InformationLevel Quiet)) {
    throw 'APIM private endpoint is not reachable on TCP 443.'
}

$python = Get-Command python.exe -ErrorAction SilentlyContinue
$tokenResponse = Invoke-RestMethod `
    -Headers @{ Metadata = 'true' } `
    -Uri 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2019-08-01&resource=https%3A%2F%2Fai.azure.com' `
    -Method Get

[pscustomobject]@{
    foundryIps = $foundryIps
    apimIps = $apimIps
    foundryTcp443 = $true
    apimTcp443 = $true
    pythonPath = if ($python) { $python.Source } else { $null }
    pythonVersion = if ($python) { ((& $python.Source --version 2>&1) | Out-String).Trim() } else { $null }
    managedIdentityTokenAcquired = [bool]$tokenResponse.access_token
} | ConvertTo-Json -Compress