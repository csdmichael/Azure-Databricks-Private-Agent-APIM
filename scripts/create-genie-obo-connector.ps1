[CmdletBinding()]
param(
    [string] $EnvironmentId = '52456fcd-1d20-ecdb-aa2e-8979e3f794f5',
    [string] $TenantId = '12a4b86b-e64c-43f9-af05-d9130a72dfd2',
    [string] $ApiClientId = 'bdd127ff-fd4c-45f5-b553-ff77a7755161',
    [string] $ConnectorClientId = '8127fb92-0641-4f6e-9d6e-f508e18e9606',
    [string] $ConnectorName = 'Databricks Genie OBO Private',
    [switch] $DefinitionOnly
)
$ErrorActionPreference = 'Stop'
$swagger = Get-Content "$PSScriptRoot/../connector/genie-connector-swagger.json" -Raw | ConvertFrom-Json
$swagger.info.title = $ConnectorName
$swagger.info.description = 'Private Databricks Genie with the signed-in user identity and Unity Catalog permissions.'
$swagger.basePath = '/databricks-genie-obo'
$swagger.securityDefinitions = [pscustomobject]@{
    oauth2 = @{
        type = 'oauth2'; flow = 'accessCode'
        authorizationUrl = "https://login.microsoftonline.com/$TenantId/oauth2/authorize"
        tokenUrl = "https://login.microsoftonline.com/$TenantId/oauth2/token"
        scopes = @{ 'Genie.Access' = 'Access Genie as the signed-in user' }
    }
}
$swagger.security = @(@{ oauth2 = @('Genie.Access') })
if ($DefinitionOnly) { return $swagger }
$context = az account show -o json | ConvertFrom-Json
if ($LASTEXITCODE -ne 0 -or $context.tenantId -ne $TenantId) { throw 'Select the intended Entra tenant first.' }
$powerToken = az account get-access-token --resource https://service.powerapps.com/ --query accessToken -o tsv
if ($LASTEXITCODE -ne 0) { throw 'Power Platform authentication failed.' }
$graphToken = az account get-access-token --resource https://graph.microsoft.com/ --query accessToken -o tsv
if ($LASTEXITCODE -ne 0) { throw 'Graph authentication failed.' }
try {
    $headers = @{ Authorization = "Bearer $powerToken" }
    $graphHeaders = @{ Authorization = "Bearer $graphToken" }
    $adminUri = "https://api.powerapps.com/providers/Microsoft.PowerApps/scopes/admin/environments/$EnvironmentId/apis"
    $apis = Invoke-RestMethod -Uri "${adminUri}?api-version=2016-11-01" -Headers $headers
    if ($apis.nextLink) { throw 'Connector pagination requires review before creation.' }
    $existing = @($apis.value | Where-Object { $_.properties.displayName -eq $ConnectorName })
    if ($existing.Count -gt 1) { throw 'Duplicate OBO connectors require explicit resolution.' }
    $applications = Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/applications?`$filter=appId eq '$ConnectorClientId'" -Headers $graphHeaders
    if (@($applications.value).Count -ne 1) { throw 'Connector application lookup was ambiguous.' }
    $application = $applications.value[0]
    if ($existing.Count -eq 1) {
        $connector = Invoke-RestMethod -Uri "$adminUri/$($existing[0].name)?api-version=2016-11-01" -Headers $headers
    } else {
        $passwordBody = @{ passwordCredential = @{ displayName = 'Genie OBO Power Platform'; endDateTime = [DateTime]::UtcNow.AddMonths(6).ToString('o') } } | ConvertTo-Json
        $password = Invoke-RestMethod -Method POST -Uri "https://graph.microsoft.com/v1.0/applications/$($application.id)/addPassword" -Headers $graphHeaders -ContentType 'application/json' -Body $passwordBody
        $body = @{
            properties = @{
                displayName = $ConnectorName; description = $swagger.info.description
                iconBrandColor = '#FF3621'; environment = @{ name = $EnvironmentId }
                backendService = @{ serviceUrl = "https://$($swagger.host)$($swagger.basePath)" }
                openApiDefinition = $swagger
                connectionParameters = @{
                    token = @{
                        type = 'oAuthSetting'; uiDefinition = $null
                        oAuthSettings = @{
                            identityProvider = 'aad'; clientId = $ConnectorClientId; clientSecret = $password.secretText
                            scopes = @('Genie.Access'); redirectMode = 'GlobalPerConnector'
                            customParameters = @{
                                LoginUri = @{ value = 'https://login.microsoftonline.com' }
                                TenantId = @{ value = $TenantId }
                                ResourceUri = @{ value = "api://$ApiClientId" }
                                EnableOnbehalfOfLogin = @{ value = $false }
                            }
                        }
                    }
                }
            }
        } | ConvertTo-Json -Depth 30
        $connector = Invoke-RestMethod -Method POST -Uri "https://api.powerapps.com/providers/Microsoft.PowerApps/apis?api-version=2016-11-01&`$filter=environment eq '$EnvironmentId'" -Headers $headers -ContentType 'application/json' -Body $body
        $password = $null
        $body = $null
    }
    $redirect = $connector.properties.connectionParameters.token.oAuthSettings.redirectUrl
    if (-not $redirect) { throw "Connector $($connector.name) exists, but no generated redirect URL was returned. Inspect it in the maker portal before creating a connection." }
    $redirectUri = [uri]$redirect
    if ($redirectUri.Scheme -ne 'https' -or -not $redirectUri.Host.EndsWith('.consent.azure-apim.net')) { throw 'Unexpected connector redirect host; review it before registration.' }
    $redirects = @(@($application.web.redirectUris) + $redirect | Where-Object { $_ } | Select-Object -Unique)
    Invoke-RestMethod -Method PATCH -Uri "https://graph.microsoft.com/v1.0/applications/$($application.id)" -Headers $graphHeaders -ContentType 'application/json' -Body (@{ web = @{ redirectUris = $redirects } } | ConvertTo-Json -Depth 5) | Out-Null
    [pscustomobject]@{ name = $connector.name; displayName = $ConnectorName; redirectUrl = $redirect; clientId = $ConnectorClientId; environmentId = $EnvironmentId }
} finally {
    $powerToken = $null; $graphToken = $null; $password = $null; $body = $null
    $headers = $null; $graphHeaders = $null; $connector = $null
}