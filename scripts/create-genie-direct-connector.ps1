<#
.SYNOPSIS
  Creates the Power Platform custom connector that reaches Azure Databricks
  Genie directly over Private Link, with no API Management hop.

.DESCRIPTION
  Uses delegated Entra ID auth so the connection runs as the signed-in maker.
  That avoids registering a service principal inside Databricks, which is not
  possible once the workspace has public network access disabled.

  Requires the Power Platform VNets to be peered directly to the Databricks
  VNet and linked to privatelink.azuredatabricks.net. Deploy
  bicep/power-platform-databricks-direct/main.bicep first, because VNet
  peering is not transitive.

.EXAMPLE
  ./create-genie-direct-connector.ps1
#>
[CmdletBinding()]
param(
  [string] $ConfigPath = (Join-Path $PSScriptRoot '../config/deployment.json'),
  [string] $EnvironmentId,
  [string] $TenantId,
  [string] $ConnectorName,
  [string] $AppId,
  [string] $WorkspaceUrl,
  [string] $SubscriptionId,
  [string] $ResourceGroup,
  [string] $ApimName,
  [string] $GenieSpaceId,
  [string] $SwaggerPath = "$PSScriptRoot/../connector/genie-direct-swagger.json",
  [string] $IconBrandColor,
  [int] $CredentialLifetimeYears = 1,
  [switch] $DefinitionOnly
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'config.ps1')

$config = Get-DeploymentConfig -Path $ConfigPath
$EnvironmentId = Get-ConfigValue -Config $config -Path 'powerPlatform.connectorEnvironmentId' -Override $EnvironmentId
$TenantId = Get-ConfigValue -Config $config -Path 'azure.tenantId' -Override $TenantId
$ConnectorName = Get-ConfigValue -Config $config -Path 'powerPlatform.connectors.directName' -Override $ConnectorName
$AppId = Get-ConfigValue -Config $config -Path 'powerPlatform.connectors.directApplicationId' -Override $AppId
$WorkspaceUrl = (Get-ConfigValue -Config $config -Path 'databricks.workspaceUrl' -Override $WorkspaceUrl).TrimEnd('/')
$SubscriptionId = Get-ConfigValue -Config $config -Path 'azure.subscriptionId' -Override $SubscriptionId
$ResourceGroup = Get-ConfigValue -Config $config -Path 'azure.resourceGroup' -Override $ResourceGroup
$ApimName = Get-ConfigValue -Config $config -Path 'apim.serviceName' -Override $ApimName
$IconBrandColor = Get-ConfigValue -Config $config -Path 'powerPlatform.connectors.iconBrandColor' -Override $IconBrandColor

# Azure Databricks is a fixed Microsoft audience ID.
$DatabricksResourceId = '2ff814a6-3304-4ab8-85cb-cd0e6f879c1d'

if (-not (Test-Path $SwaggerPath)) { throw "Swagger not found: $SwaggerPath" }
$swagger = Get-Content $SwaggerPath -Raw | ConvertFrom-Json
$swagger.host = ([uri]$WorkspaceUrl).Host

if ([string]::IsNullOrWhiteSpace($GenieSpaceId)) {
  $namedValueUrl = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.ApiManagement/service/$ApimName/namedValues/databricks-genie-space-id?api-version=2024-06-01-preview"
  $GenieSpaceId = az rest --method get --url $namedValueUrl --query properties.value -o tsv --only-show-errors
  if ($LASTEXITCODE -ne 0 -or -not $GenieSpaceId) { throw 'Unable to resolve the Genie space id. Pass -GenieSpaceId explicitly.' }
}
foreach ($path in $swagger.paths.PSObject.Properties.Value) {
  foreach ($operation in $path.PSObject.Properties.Value) {
    if (-not $operation.PSObject.Properties['parameters']) { continue }
    foreach ($parameter in @($operation.parameters | Where-Object { $_.name -eq 'spaceId' })) {
      $parameter.default = $GenieSpaceId
    }
  }
}

if ($DefinitionOnly) { return $swagger }

$context = az account show -o json | ConvertFrom-Json
if ($LASTEXITCODE -ne 0 -or $context.tenantId -ne $TenantId) { throw 'Select the intended Entra tenant first.' }

# Rotating the secret here keeps it in-process; it is written only into the
# connector's oAuthSettings and never echoed or persisted to disk.
$secret = (az ad app credential reset --id $AppId --display-name 'powerplatform-connector' --years $CredentialLifetimeYears -o json | ConvertFrom-Json).password
if (-not $secret) { throw 'Could not create a client secret for the app registration.' }

try {
  $token = az account get-access-token --resource 'https://service.powerapps.com/' --query accessToken -o tsv
  if ($LASTEXITCODE -ne 0 -or -not $token) { throw 'Unable to acquire a Power Platform token.' }

  $body = @{
    properties = @{
      displayName          = $ConnectorName
      description          = $swagger.info.description
      iconBrandColor       = $IconBrandColor
      environment          = @{ name = $EnvironmentId }
      backendService       = @{ serviceUrl = "https://$($swagger.host)$($swagger.basePath)" }
      openApiDefinition    = $swagger
      connectionParameters = @{
        token = @{
          type          = 'oauthSetting'
          oAuthSettings = @{
            identityProvider = 'aad'
            clientId         = $AppId
            clientSecret     = $secret
            scopes           = @()
            redirectMode     = 'Global'
            properties       = @{
              IsFirstParty                   = 'False'
              AzureActiveDirectoryResourceId = $DatabricksResourceId
            }
            customParameters = @{
              loginUri              = @{ value = 'https://login.microsoftonline.com' }
              tenantId              = @{ value = $TenantId }
              resourceUri           = @{ value = $DatabricksResourceId }
              enableOnbehalfOfLogin = @{ value = 'false' }
            }
          }
        }
      }
    }
  } | ConvertTo-Json -Depth 40

  $uri = "https://api.powerapps.com/providers/Microsoft.PowerApps/apis?api-version=2016-11-01&`$filter=environment eq '$EnvironmentId'"
  $created = Invoke-RestMethod -Method POST -Uri $uri -Headers @{ Authorization = "Bearer $token"; 'Content-Type' = 'application/json' } -Body $body

  [pscustomobject]@{
    Name        = $created.name
    DisplayName = $created.properties.displayName
    BackendUrl  = $created.properties.backendService.serviceUrl
    AuthMode    = 'Entra ID (delegated)'
  }
}
finally {
  $secret = $null
  $token = $null
  $body = $null
  [System.GC]::Collect()
}
