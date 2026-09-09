<#
.SYNOPSIS
  Creates or updates the Power Platform custom connector that lets a Copilot
  Studio agent reach the private APIM Genie API over the delegated subnet.

.DESCRIPTION
  Copilot Studio MCP servers are NOT covered by Power Platform virtual network
  support, so an MCP tool cannot reach a private API Management gateway.
  Custom connectors ARE covered, so this script projects the same APIM Genie
  REST API as a custom connector instead.

  The APIM subscription key is never handled here. The connector declares an
  api_key security definition; the maker supplies the value when creating the
  connection in Copilot Studio.

.EXAMPLE
  ./create-genie-connector.ps1
#>
[CmdletBinding()]
param(
  [string] $EnvironmentId = '52456fcd-1d20-ecdb-aa2e-8979e3f794f5',
  [string] $ConnectorName = 'Databricks Genie (Private APIM)',
  [string] $SwaggerPath = "$PSScriptRoot/../connector/genie-swagger2.json",
  [string] $OutputPath = "$PSScriptRoot/../connector/genie-connector-swagger.json",
  [string] $IconBrandColor = '#FF3621',
  [switch] $DefinitionOnly
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $SwaggerPath)) { throw "Swagger not found: $SwaggerPath" }
$swagger = Get-Content $SwaggerPath -Raw | ConvertFrom-Json

# Power Platform requires an explicit security definition so the maker is
# prompted for the APIM subscription key when creating the connection.
$swagger | Add-Member -NotePropertyName securityDefinitions -NotePropertyValue ([pscustomobject]@{
    api_key = [pscustomobject]@{
      type = 'apiKey'
      in   = 'header'
      name = 'Ocp-Apim-Subscription-Key'
    }
  }) -Force

$swagger | Add-Member -NotePropertyName security -NotePropertyValue @(
  [pscustomobject]@{ api_key = @() }
) -Force

$swagger.info | Add-Member -NotePropertyName description -NotePropertyValue 'Asks natural-language questions of private Azure Databricks data through AI/BI Genie, proxied by Azure API Management over Private Link. Reached from Power Platform through the delegated subnet.' -Force
$swagger.info.title = $ConnectorName
$swagger | Add-Member -NotePropertyName schemes -NotePropertyValue @('https') -Force

# APIM exports the request body with only an `example`, which gives Copilot
# Studio no typed input to bind, so it posts an empty body and Databricks
# returns 400 "Field 'content' is required". Declare the schema explicitly.
$contentBody = [pscustomobject]@{
  name     = 'body'
  'in'     = 'body'
  required = $true
  schema   = [pscustomobject]@{
    type       = 'object'
    required   = @('content')
    properties = [pscustomobject]@{
      content = [pscustomobject]@{
        type            = 'string'
        description     = 'The natural-language question to ask Genie.'
        'x-ms-summary'  = 'Question'
      }
    }
  }
}

foreach ($p in '/genie/ask', '/genie/conversations/{conversationId}/messages') {
  $op = $swagger.paths.$p.post
  if (-not $op) { continue }
  $rebuilt = @($op.parameters | Where-Object { $_.'in' -ne 'body' }) + $contentBody
  $op.parameters = $rebuilt
}

$swagger | ConvertTo-Json -Depth 40 | Set-Content -Path $OutputPath -Encoding utf8
Write-Host "Wrote connector definition: $OutputPath"

if ($DefinitionOnly) { return }

$token = az account get-access-token --resource 'https://service.powerapps.com/' --query accessToken -o tsv
if ($LASTEXITCODE -ne 0 -or -not $token) { throw 'Unable to acquire a Power Platform token.' }
$headers = @{ Authorization = "Bearer $token"; 'Content-Type' = 'application/json' }

$apiName = 'caldova-genie-private'
$uri = "https://api.powerapps.com/providers/Microsoft.PowerApps/apis?api-version=2016-11-01&`$filter=environment eq '$EnvironmentId'"

# The API rejects `apiType` and expects `openApiDefinition`, not `swagger`.
# connectionParameters must be supplied at creation; PATCH silently drops it.
$body = @{
  properties = @{
    displayName          = $ConnectorName
    description          = $swagger.info.description
    iconBrandColor       = $IconBrandColor
    environment          = @{ name = $EnvironmentId }
    backendService       = @{ serviceUrl = "https://$($swagger.host)$($swagger.basePath)" }
    openApiDefinition    = $swagger
    connectionParameters = @{
      api_key = @{
        type         = 'securestring'
        uiDefinition = @{
          displayName = 'APIM subscription key'
          description = 'Ocp-Apim-Subscription-Key for the databricks-agents product'
          tooltip     = 'Paste the APIM subscription key'
          constraints = @{ tabIndex = 2; clearText = $false; required = 'true' }
        }
      }
    }
  }
} | ConvertTo-Json -Depth 40

try {
  $created = Invoke-RestMethod -Method POST -Uri $uri -Headers $headers -Body $body
  $token = $null
  [pscustomobject]@{
    Name        = $created.name
    DisplayName = $created.properties.displayName
    Environment = $EnvironmentId
    BackendUrl  = $created.properties.backendService.serviceUrl
  }
}
catch {
  $token = $null
  Write-Warning "Connector API call failed: $($_.Exception.Message)"
  Write-Host "Import $OutputPath manually: make.powerapps.com -> Custom connectors -> New -> Import an OpenAPI file."
  throw
}
