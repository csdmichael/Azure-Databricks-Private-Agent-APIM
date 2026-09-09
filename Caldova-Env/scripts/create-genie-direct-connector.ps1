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
  [string] $EnvironmentId = '52456fcd-1d20-ecdb-aa2e-8979e3f794f5',
  [string] $TenantId = '12a4b86b-e64c-43f9-af05-d9130a72dfd2',
  [string] $ConnectorName = 'Databricks Genie (Direct Private)',
  [string] $AppId = '82bbdaca-f996-452d-89c2-49dee7456ebe',
  [string] $SwaggerPath = "$PSScriptRoot/../connector/genie-direct-swagger.json",
  [string] $IconBrandColor = '#1B3139'
)

$ErrorActionPreference = 'Stop'
$DatabricksResourceId = '2ff814a6-3304-4ab8-85cb-cd0e6f879c1d'

if (-not (Test-Path $SwaggerPath)) { throw "Swagger not found: $SwaggerPath" }
$swagger = Get-Content $SwaggerPath -Raw | ConvertFrom-Json

# Rotating the secret here keeps it in-process; it is written only into the
# connector's oAuthSettings and never echoed or persisted to disk.
$secret = (az ad app credential reset --id $AppId --display-name 'powerplatform-connector' --years 1 -o json | ConvertFrom-Json).password
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
