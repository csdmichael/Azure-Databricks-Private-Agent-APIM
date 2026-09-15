[CmdletBinding()]
param(
    [string] $ConfigPath = (Join-Path $PSScriptRoot '../config/deployment.json'),
    [string] $SubscriptionId,
    [string] $ResourceGroup,
    [string] $ApimName,
    [string] $ApimSubscriptionName,
    [string] $FoundryAccountName,
    [string] $FoundryProjectName,
    [string] $ConnectionName,
    [string] $McpServerUrl
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'config.ps1')

$config = Get-DeploymentConfig -Path $ConfigPath
$SubscriptionId = Get-ConfigValue -Config $config -Path 'azure.subscriptionId' -Override $SubscriptionId
$ResourceGroup = Get-ConfigValue -Config $config -Path 'azure.resourceGroup' -Override $ResourceGroup
$ApimName = Get-ConfigValue -Config $config -Path 'apim.serviceName' -Override $ApimName
$ApimSubscriptionName = Get-ConfigValue -Config $config -Path 'apim.subscriptionName' -Override $ApimSubscriptionName
$FoundryAccountName = Get-ConfigValue -Config $config -Path 'foundry.private.accountName' -Override $FoundryAccountName
$FoundryProjectName = Get-ConfigValue -Config $config -Path 'foundry.private.projectName' -Override $FoundryProjectName
$ConnectionName = Get-ConfigValue -Config $config -Path 'foundry.private.connectionName' -Override $ConnectionName
if ([string]::IsNullOrWhiteSpace($McpServerUrl)) {
    $gatewayUrl = (Get-ConfigValue -Config $config -Path 'apim.gatewayUrl').TrimEnd('/')
    $mcpPath = (Get-ConfigValue -Config $config -Path 'apim.mcpPath').Trim('/')
    $McpServerUrl = "$gatewayUrl/$mcpPath/mcp"
}

$context = az account show -o json | ConvertFrom-Json
if ($LASTEXITCODE -ne 0 -or $context.id -ne $SubscriptionId) {
    throw "Select Azure subscription $SubscriptionId before creating the connection."
}

$secretsUrl = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.ApiManagement/service/$ApimName/subscriptions/$ApimSubscriptionName/listSecrets?api-version=2024-05-01"
$connectionUrl = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.CognitiveServices/accounts/$FoundryAccountName/projects/$FoundryProjectName/connections/$ConnectionName`?api-version=2025-06-01"

$secretResult = az rest --method post --url $secretsUrl -o json --only-show-errors | ConvertFrom-Json
if ($LASTEXITCODE -ne 0 -or -not $secretResult.primaryKey) {
    throw 'Unable to read the APIM subscription key.'
}

$apimKey = $secretResult.primaryKey
try {
    $armToken = az account get-access-token --resource https://management.azure.com --query accessToken -o tsv
    if ($LASTEXITCODE -ne 0 -or -not $armToken) { throw 'Unable to acquire an ARM token.' }

    $body = @{
        properties = @{
            category = 'RemoteTool'
            target = $McpServerUrl
            authType = 'CustomKeys'
            credentials = @{
                keys = @{ 'Ocp-Apim-Subscription-Key' = $apimKey }
            }
            metadata = @{ type = 'custom_MCP' }
            isSharedToAll = $false
        }
    } | ConvertTo-Json -Depth 8

    $response = Invoke-RestMethod `
        -Method Put `
        -Uri $connectionUrl `
        -Headers @{ Authorization = "Bearer $armToken" } `
        -ContentType 'application/json' `
        -Body $body

    [pscustomobject]@{
        name = $response.name
        category = $response.properties.category
        target = $response.properties.target
        authType = $response.properties.authType
    }
} finally {
    $apimKey = $null
    $secretResult = $null
    $armToken = $null
    $body = $null
    $response = $null
}