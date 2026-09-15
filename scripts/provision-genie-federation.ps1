[CmdletBinding()]
param(
    [string] $ConfigPath = (Join-Path $PSScriptRoot '../config/deployment.json'),
    [string] $TenantId,
    [string] $AccountId,
    [string] $ApiClientId,
    [Nullable[int]] $RequestTimeoutSeconds,
    [switch] $ReadOnly
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'config.ps1')

$config = Get-DeploymentConfig -Path $ConfigPath
$TenantId = Get-ConfigValue -Config $config -Path 'azure.tenantId' -Override $TenantId
$AccountId = Get-ConfigValue -Config $config -Path 'databricks.accountId' -Override $AccountId
$ApiClientId = Get-ConfigValue -Config $config -Path 'obo.apiClientId' -Override $ApiClientId
$RequestTimeoutSeconds = [int](Get-ConfigValue -Config $config -Path 'databricks.apiTimeoutSeconds' -Override $RequestTimeoutSeconds)

foreach ($identifier in @($TenantId, $AccountId, $ApiClientId)) {
    $parsed = [guid]::Empty
    if (-not [guid]::TryParse($identifier, [ref]$parsed)) { throw 'Tenant, account and API identifiers must be UUIDs.' }
}
$context = az account show -o json | ConvertFrom-Json
if ($LASTEXITCODE -ne 0 -or $context.tenantId -ne $TenantId) { throw 'Select the intended Entra tenant first.' }
$token = az account get-access-token --resource 2ff814a6-3304-4ab8-85cb-cd0e6f879c1d --query accessToken -o tsv
if ($LASTEXITCODE -ne 0) { throw 'Databricks authentication failed.' }
try {
    $uri = "https://accounts.azuredatabricks.net/api/2.0/accounts/$AccountId/federationPolicies"
    $headers = @{ Authorization = "Bearer $token" }
    $issuer = "https://login.microsoftonline.com/$TenantId/v2.0"
    $response = Invoke-RestMethod -Uri $uri -Headers $headers -TimeoutSec $RequestTimeoutSeconds
    if ($response.PSObject.Properties['next_page_token'] -and $response.next_page_token) { throw 'Policy pagination requires review before creating another trust.' }
    $matching = @($response.policies | Where-Object { $_.oidc_policy.audiences -contains $ApiClientId })
    if ($matching.Count -gt 1) { throw 'Multiple policies trust the API audience; review them explicitly.' }
    if ($matching.Count -eq 1) {
        $policy = $matching[0]
        if ($policy.oidc_policy.issuer -ne $issuer -or $policy.oidc_policy.subject_claim -ne 'preferred_username' -or @($policy.oidc_policy.audiences).Count -ne 1) {
            throw 'Existing trust differs from the approved policy; no update was made.'
        }
    } elseif ($ReadOnly) {
        [pscustomobject]@{ status = 'Missing'; issuer = $issuer; audience = $ApiClientId }
        return
    } else {
        $body = @{ oidc_policy = @{ issuer = $issuer; audiences = @($ApiClientId); subject_claim = 'preferred_username' } } | ConvertTo-Json -Depth 5
        $policy = Invoke-RestMethod -Method POST -Uri $uri -Headers $headers -ContentType 'application/json' -Body $body -TimeoutSec $RequestTimeoutSeconds
    }
    [pscustomobject]@{ policyId = $policy.policy_id; issuer = $policy.oidc_policy.issuer; audiences = $policy.oidc_policy.audiences; subjectClaim = $policy.oidc_policy.subject_claim }
} finally { $token = $null; $headers = $null }