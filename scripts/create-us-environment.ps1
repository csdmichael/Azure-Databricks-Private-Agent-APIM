<#
.SYNOPSIS
  Creates a Dataverse-backed Power Platform environment in the United States
  geo, enables Managed Environment on it, and returns its environment ID.

.DESCRIPTION
  Virtual network support requires a Managed Environment whose Dataverse region
  matches the enterprise policy location. The configured enterprise policy and
  environment must use the same geo.

.EXAMPLE
  ./create-us-environment.ps1 -DisplayName '<environment-display-name>'
#>
[CmdletBinding()]
param(
  [string] $ConfigPath = (Join-Path $PSScriptRoot '../config/deployment.json'),
  [string] $DisplayName,
  [string] $DomainName,
  [ValidateSet('Sandbox', 'Production', 'Trial')]
  [string] $EnvironmentSku,
  [string] $Location,
  [string] $CurrencyCode,
  [Nullable[int]] $BaseLanguage,
  [string] $TenantId
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'config.ps1')

$config = Get-DeploymentConfig -Path $ConfigPath
$DisplayName = Get-ConfigValue -Config $config -Path 'powerPlatform.environment.displayName' -Override $DisplayName
$DomainName = Get-ConfigValue -Config $config -Path 'powerPlatform.environment.domainName' -Override $DomainName
$EnvironmentSku = Get-ConfigValue -Config $config -Path 'powerPlatform.environment.sku' -Override $EnvironmentSku
$Location = Get-ConfigValue -Config $config -Path 'powerPlatform.environment.location' -Override $Location
$CurrencyCode = Get-ConfigValue -Config $config -Path 'powerPlatform.environment.currencyCode' -Override $CurrencyCode
$BaseLanguage = [int](Get-ConfigValue -Config $config -Path 'powerPlatform.environment.baseLanguage' -Override $BaseLanguage)
$TenantId = Get-ConfigValue -Config $config -Path 'azure.tenantId' -Override $TenantId

$context = az account show -o json | ConvertFrom-Json
if ($LASTEXITCODE -ne 0 -or $context.tenantId -ne $TenantId) { throw 'Select the configured Entra tenant before managing Power Platform environments.' }

$bap = 'https://api.bap.microsoft.com'
$apiVersion = '2021-04-01'

function Get-BapHeaders {
  $token = az account get-access-token --resource 'https://service.powerapps.com/' --query accessToken -o tsv
  if ($LASTEXITCODE -ne 0 -or -not $token) { throw 'Unable to acquire a Power Platform token.' }
  @{ Authorization = "Bearer $token"; 'Content-Type' = 'application/json' }
}

$headers = Get-BapHeaders

$existing = (Invoke-RestMethod -Method GET -Headers $headers `
    -Uri "$bap/providers/Microsoft.BusinessAppPlatform/scopes/admin/environments?api-version=$apiVersion").value |
  Where-Object { $_.properties.displayName -eq $DisplayName } | Select-Object -First 1

if ($existing) {
  Write-Host "Environment '$DisplayName' already exists: $($existing.name)"
  $environmentId = $existing.name
}
else {
  if (-not (Get-Module -ListAvailable -Name Microsoft.PowerApps.Administration.PowerShell)) {
    Write-Host 'Installing Microsoft.PowerApps.Administration.PowerShell ...'
    Install-Module Microsoft.PowerApps.Administration.PowerShell -Scope CurrentUser -Force -AllowClobber
  }
  Import-Module Microsoft.PowerApps.Administration.PowerShell -Force

  # The module keeps its own token cache, separate from the Azure CLI session.
  Add-PowerAppsAccount -Endpoint prod -TenantID $TenantId | Out-Null

  Write-Host "Creating environment '$DisplayName' in $Location ..."
  $created = New-AdminPowerAppEnvironment `
    -DisplayName $DisplayName `
    -Location $Location `
    -EnvironmentSku $EnvironmentSku `
    -ProvisionDatabase `
    -CurrencyName $CurrencyCode `
    -LanguageName $BaseLanguage `
    -DomainName $DomainName `
    -WaitUntilFinished $true

  if (-not $created -or -not $created.EnvironmentName) {
    throw "Environment creation failed: $($created | ConvertTo-Json -Depth 6)"
  }
  $environmentId = $created.EnvironmentName
  Write-Host "Created environment $environmentId"
}

# Managed Environment is a prerequisite for subnet injection.
$headers = Get-BapHeaders
$env = Invoke-RestMethod -Method GET -Headers $headers `
  -Uri "$bap/providers/Microsoft.BusinessAppPlatform/scopes/admin/environments/$environmentId`?api-version=$apiVersion"

$governance = if ($env.properties.PSObject.Properties['governanceConfiguration']) { $env.properties.governanceConfiguration } else { $null }
$protectionLevel = if ($governance -and $governance.PSObject.Properties['protectionLevel']) { $governance.protectionLevel } else { $null }
if ($protectionLevel -ne 'Standard') {
  Write-Host 'Enabling Managed Environment ...'
  Invoke-RestMethod -Method PUT -Headers $headers `
    -Body (@{ protectionLevel = 'Standard' } | ConvertTo-Json) `
    -Uri "$bap/providers/Microsoft.BusinessAppPlatform/scopes/admin/environments/$environmentId/governanceConfiguration?api-version=$apiVersion" | Out-Null
}

$headers = Get-BapHeaders
$env = Invoke-RestMethod -Method GET -Headers $headers `
  -Uri "$bap/providers/Microsoft.BusinessAppPlatform/scopes/admin/environments/$environmentId`?api-version=$apiVersion"
$governance = if ($env.properties.PSObject.Properties['governanceConfiguration']) { $env.properties.governanceConfiguration } else { $null }
$protectionLevel = if ($governance -and $governance.PSObject.Properties['protectionLevel']) { $governance.protectionLevel } else { $null }

[pscustomobject]@{
  EnvironmentId   = $environmentId
  DisplayName     = $env.properties.displayName
  Geo             = $env.location
  AzureRegion     = $env.properties.azureRegion
  ProtectionLevel = $protectionLevel
  DataverseUrl    = $env.properties.linkedEnvironmentMetadata.instanceUrl
}
