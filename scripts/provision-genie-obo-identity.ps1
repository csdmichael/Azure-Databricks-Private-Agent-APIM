[CmdletBinding()]
param(
    [string] $ConfigPath = (Join-Path $PSScriptRoot '../config/deployment.json'),
    [string] $TenantId,
    [string] $ApiDisplayName,
    [string] $ConnectorDisplayName,
    [string] $ConsentUserId,
    [string] $Scope,
    [string] $RedirectUri
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'config.ps1')

$config = Get-DeploymentConfig -Path $ConfigPath
$TenantId = Get-ConfigValue -Config $config -Path 'azure.tenantId' -Override $TenantId
$ApiDisplayName = Get-ConfigValue -Config $config -Path 'obo.apiDisplayName' -Override $ApiDisplayName
$ConnectorDisplayName = Get-ConfigValue -Config $config -Path 'obo.connectorDisplayName' -Override $ConnectorDisplayName
$ConsentUserId = Get-ConfigValue -Config $config -Path 'obo.allowedUserId' -Override $ConsentUserId
$Scope = Get-ConfigValue -Config $config -Path 'obo.scope' -Override $Scope

$context = az account show -o json | ConvertFrom-Json
if ($LASTEXITCODE -ne 0 -or $context.tenantId -ne $TenantId) { throw 'Authenticate to the intended tenant first.' }
if ($RedirectUri -and ([uri]$RedirectUri).Scheme -ne 'https') { throw 'Connector redirect must use HTTPS.' }
$graphToken = az account get-access-token --resource https://graph.microsoft.com --query accessToken -o tsv
if ($LASTEXITCODE -ne 0) { throw 'Graph authentication failed.' }
function Invoke-Graph([string] $Method, [string] $Path, $Body) {
    $arguments = @{ Method = $Method; Uri = "https://graph.microsoft.com/v1.0/$Path"; Headers = @{ Authorization = "Bearer $graphToken" } }
    if ($null -ne $Body) { $arguments.ContentType = 'application/json'; $arguments.Body = ConvertTo-Json -InputObject $Body -Depth 20 }
    Invoke-RestMethod @arguments
}
function Ensure-Application([string] $Name) {
    $filter = [uri]::EscapeDataString("displayName eq '$($Name.Replace("'", "''"))'")
    $applications = @( (Invoke-Graph GET "applications?`$filter=$filter&`$select=id,appId,displayName,api,requiredResourceAccess,web" $null).value )
    if ($applications.Count -gt 1) { throw "Multiple registrations named $Name. Resolve the ambiguity before proceeding." }
    if ($applications.Count -eq 1) { return $applications[0] }
    Invoke-Graph POST 'applications' @{ displayName = $Name; signInAudience = 'AzureADMyOrg'; isFallbackPublicClient = $false }
}
function Ensure-Principal([string] $AppId) {
    $principals = @( (Invoke-Graph GET "servicePrincipals?`$filter=appId eq '$AppId'&`$select=id,appId" $null).value )
    if ($principals.Count -gt 1) { throw 'Ambiguous application principal.' }
    if ($principals.Count -eq 1) { return $principals[0] }
    Invoke-Graph POST 'servicePrincipals' @{ appId = $AppId }
}
try {
    $api = Ensure-Application $ApiDisplayName
    $scopes = @($api.api.oauth2PermissionScopes | Where-Object { $_ })
    $scopeDefinition = $scopes | Where-Object value -EQ $Scope | Select-Object -First 1
    if (-not $scopeDefinition) {
        $scopeDefinition = @{
            id = [guid]::NewGuid().ToString(); value = $Scope; type = 'Admin'; isEnabled = $true
            adminConsentDisplayName = 'Access private Genie as the signed-in user'
            adminConsentDescription = 'Exchange the signed-in user token for Databricks Genie access under that user permissions.'
        }
        $scopes += $scopeDefinition
    }
    Invoke-Graph PATCH "applications/$($api.id)" @{
        identifierUris = @("api://$($api.appId)")
        api = @{ requestedAccessTokenVersion = 2; oauth2PermissionScopes = $scopes }
        optionalClaims = @{ accessToken = @(@{ name = 'idtyp'; essential = $false; additionalProperties = @() }) }
    } | Out-Null
    $connector = Ensure-Application $ConnectorDisplayName
    $permissions = @($connector.requiredResourceAccess | Where-Object { $_ -and $_.resourceAppId -ne $api.appId })
    $permissions += @{ resourceAppId = $api.appId; resourceAccess = @(@{ id = $scopeDefinition.id; type = 'Scope' }) }
    $patch = @{ requiredResourceAccess = $permissions; isFallbackPublicClient = $false }
    if ($RedirectUri) {
        $redirects = @(@($connector.web.redirectUris) + $RedirectUri | Where-Object { $_ } | Select-Object -Unique)
        $patch.web = @{ redirectUris = $redirects }
    }
    Invoke-Graph PATCH "applications/$($connector.id)" $patch | Out-Null
    $apiPrincipal = Ensure-Principal $api.appId
    $connectorPrincipal = Ensure-Principal $connector.appId
    $grants = @( (Invoke-Graph GET "oauth2PermissionGrants?`$filter=clientId eq '$($connectorPrincipal.id)'" $null).value )
    $grant = $grants | Where-Object { $_.resourceId -eq $apiPrincipal.id -and $_.principalId -eq $ConsentUserId -and $_.consentType -eq 'Principal' } | Select-Object -First 1
    if ($grant) {
        $grantScopes = @(@($grant.scope -split ' ') + $Scope | Where-Object { $_ } | Select-Object -Unique)
        Invoke-Graph PATCH "oauth2PermissionGrants/$($grant.id)" @{ scope = $grantScopes -join ' ' } | Out-Null
    } else {
        Invoke-Graph POST 'oauth2PermissionGrants' @{
            clientId = $connectorPrincipal.id; resourceId = $apiPrincipal.id
            consentType = 'Principal'; principalId = $ConsentUserId; scope = $Scope
        } | Out-Null
    }
    [pscustomobject]@{
        tenantId = $TenantId; apiClientId = $api.appId; apiObjectId = $api.id
        connectorClientId = $connector.appId; connectorObjectId = $connector.id
        scopeId = $scopeDefinition.id; consentUserId = $ConsentUserId
    }
} finally { $graphToken = $null }