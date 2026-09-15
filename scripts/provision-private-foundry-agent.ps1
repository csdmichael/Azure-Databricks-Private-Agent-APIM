[CmdletBinding()]
param(
    [string] $ConfigPath = (Join-Path $PSScriptRoot '../config/deployment.json'),
    [ValidateSet('Create', 'Test', 'All')]
    [string] $Mode = 'All',
    [string] $FoundryAccountName,
    [string] $ProjectName,
    [string] $ProjectEndpoint,
    [string] $AgentName,
    [string] $ModelDeploymentName,
    [string] $ConnectionName,
    [string] $McpServerUrl,
    [string] $AgentInstructions = '',
    [string] $FoundryFeatures = 'WorkflowAgents=V1Preview,ExternalAgents=V1Preview,DraftAgents=V1Preview,AgentsOptimization=V2Preview',
    [string] $TestPrompt,
    [ValidateSet('minimal', 'low', 'medium', 'high')]
    [string] $ReasoningEffort = 'low',
    [Nullable[int]] $RequestTimeoutSeconds
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
. (Join-Path $PSScriptRoot 'config.ps1')

$config = Get-DeploymentConfig -Path $ConfigPath
$FoundryAccountName = Get-ConfigValue -Config $config -Path 'foundry.private.accountName' -Override $FoundryAccountName
$ProjectName = Get-ConfigValue -Config $config -Path 'foundry.private.projectName' -Override $ProjectName
$AgentName = Get-ConfigValue -Config $config -Path 'foundry.private.agentName' -Override $AgentName
$ModelDeploymentName = Get-ConfigValue -Config $config -Path 'foundry.private.modelDeploymentName' -Override $ModelDeploymentName
$ConnectionName = Get-ConfigValue -Config $config -Path 'foundry.private.connectionName' -Override $ConnectionName
$TestPrompt = Get-ConfigValue -Config $config -Path 'tests.smokePrompt' -Override $TestPrompt
$RequestTimeoutSeconds = [int](Get-ConfigValue -Config $config -Path 'api.requestTimeoutSeconds' -Override $RequestTimeoutSeconds)
if ([string]::IsNullOrWhiteSpace($ProjectEndpoint)) {
    $ProjectEndpoint = "https://$FoundryAccountName.services.ai.azure.com/api/projects/$ProjectName"
}
if ([string]::IsNullOrWhiteSpace($McpServerUrl)) {
    $gatewayUrl = (Get-ConfigValue -Config $config -Path 'apim.gatewayUrl').TrimEnd('/')
    $mcpPath = (Get-ConfigValue -Config $config -Path 'apim.mcpPath').Trim('/')
    $McpServerUrl = "$gatewayUrl/$mcpPath/mcp"
}

$agentNameEncoded = [Uri]::EscapeDataString($AgentName)
$tokenResponse = Invoke-RestMethod `
    -Headers @{ Metadata = 'true' } `
    -Uri 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2019-08-01&resource=https%3A%2F%2Fai.azure.com' `
    -Method Get

if (-not $tokenResponse.access_token) { throw 'Managed identity did not return a Foundry access token.' }

$headers = @{
    Authorization = "Bearer $($tokenResponse.access_token)"
    'Foundry-Features' = $FoundryFeatures
}

function Invoke-FoundryJson {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Post', 'Delete', 'Get')]
        [string] $Method,
        [Parameter(Mandatory)]
        [string] $Uri,
        [string] $Body
    )

    $parameters = @{
        Method = $Method
        Uri = $Uri
        Headers = $headers
        TimeoutSec = $RequestTimeoutSeconds
    }
    if ($Body) {
        $parameters.ContentType = 'application/json'
        $parameters.Body = $Body
    }
    return Invoke-RestMethod @parameters
}

$result = [ordered]@{
    mode = $Mode
    projectEndpoint = $projectEndpoint
}

if ($Mode -in @('Create', 'All')) {
    $agentBody = @{
        definition = @{
            kind = 'prompt'
            model = $ModelDeploymentName
            instructions = $AgentInstructions
            reasoning = @{ effort = $ReasoningEffort }
            tools = @(
                @{
                    type = 'mcp'
                    server_label = $ConnectionName
                    server_url = $McpServerUrl
                    project_connection_id = $ConnectionName
                    allowed_tools = @()
                    require_approval = 'never'
                }
            )
        }
        description = "$AgentName prompt agent"
    } | ConvertTo-Json -Depth 12 -Compress

    $agent = Invoke-FoundryJson `
        -Method Post `
        -Uri "$projectEndpoint/agents/$agentNameEncoded/versions?api-version=v1" `
        -Body $agentBody
    $result.agentName = $agent.name
    $result.agentVersion = $agent.version
}

if ($Mode -in @('Test', 'All')) {
    $foundryIps = @([Net.Dns]::GetHostAddresses("$FoundryAccountName.services.ai.azure.com") | ForEach-Object { $_.IPAddressToString })
    $apimHost = ([Uri]$McpServerUrl).Host
    $apimIps = @([Net.Dns]::GetHostAddresses($apimHost) | ForEach-Object { $_.IPAddressToString })
    if (@($foundryIps | Where-Object { $_ -notmatch '^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.)' }).Count) {
        throw "Foundry resolved to a non-private address: $($foundryIps -join ', ')"
    }
    if (@($apimIps | Where-Object { $_ -notmatch '^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.)' }).Count) {
        throw "APIM resolved to a non-private address: $($apimIps -join ', ')"
    }

    $openAiEndpoint = "$projectEndpoint/agents/$agentNameEncoded/endpoint/protocols/openai"
    $conversation = Invoke-FoundryJson `
        -Method Post `
        -Uri "$openAiEndpoint/conversations?api-version=v1" `
        -Body '{}'
    try {
        $responseBody = @{
            conversation = $conversation.id
            input = "Use the $ConnectionName tool to answer this request: $TestPrompt"
        } | ConvertTo-Json -Compress
        $response = Invoke-FoundryJson `
            -Method Post `
            -Uri "$openAiEndpoint/responses?api-version=v1" `
            -Body $responseBody
        $outputTypes = @($response.output | ForEach-Object { $_.type })
        $mcpCalls = @($response.output | Where-Object { $_.type -eq 'mcp_call' })
        if (-not $mcpCalls.Count) {
            throw "Agent response did not contain an MCP call. Output types: $($outputTypes -join ', ')"
        }
        $failedMcpCalls = @($mcpCalls | Where-Object {
            $errorValue = if ($_.PSObject.Properties['error']) { $_.error } else { $null }
            $statusValue = if ($_.PSObject.Properties['status']) { $_.status } else { $null }
            $errorValue -or ($statusValue -and $statusValue -notin @('completed', 'succeeded'))
        })
        if ($failedMcpCalls.Count) {
            throw 'Agent response contained a failed MCP call.'
        }
        $result.responseStatus = $response.status
        $result.outputTypes = $outputTypes
        $result.mcpCalls = @($mcpCalls | ForEach-Object {
            $statusValue = if ($_.PSObject.Properties['status']) { $_.status } else { $null }
            $errorValue = if ($_.PSObject.Properties['error']) { $_.error } else { $null }
            [ordered]@{
                name = $_.name
                status = $statusValue
                hasError = [bool]$errorValue
            }
        })
        $result.foundryIps = $foundryIps
        $result.apimIps = $apimIps
        $result.mcpToolUsed = $true
    } finally {
        if ($conversation.id) {
            Invoke-FoundryJson `
                -Method Delete `
                -Uri "$openAiEndpoint/conversations/$($conversation.id)?api-version=v1" | Out-Null
        }
    }
}

$tokenResponse = $null
$headers.Authorization = $null
$result | ConvertTo-Json -Depth 6 -Compress