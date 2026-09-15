<#
.SYNOPSIS
  End-to-end smoke test of the Databricks Genie API exposed through APIM.

.DESCRIPTION
  Runs the full ask -> poll -> result flow against
    https://<apim>.azure-api.net/<genie-api-path>. The APIM subscription key is
  read at run time from the APIM subscription (listSecrets) unless -ApimKey is
  supplied, and is never written to disk or echoed.

.EXAMPLE
  ./scripts/test-genie.ps1
    ./scripts/test-genie.ps1 -Question "<question>"
#>
[CmdletBinding()]
param(
        [string] $ConfigPath = (Join-Path $PSScriptRoot '../config/deployment.json'),
        [string] $Question,
        [string] $ApimBaseUrl,
    [string] $ApimKey,
        [string] $ResourceGroup,
        [string] $ApimName,
        [string] $SubscriptionId,
        [string] $ApimSubscriptionName,
        [Nullable[int]] $TimeoutSeconds,
        [Nullable[int]] $RequestTimeoutSeconds,
        [int] $PollIntervalSeconds = 4
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot 'config.ps1')

$config = Get-DeploymentConfig -Path $ConfigPath
$Question = Get-ConfigValue -Config $config -Path 'tests.geniePrompt' -Override $Question
$ResourceGroup = Get-ConfigValue -Config $config -Path 'azure.resourceGroup' -Override $ResourceGroup
$ApimName = Get-ConfigValue -Config $config -Path 'apim.serviceName' -Override $ApimName
$SubscriptionId = Get-ConfigValue -Config $config -Path 'azure.subscriptionId' -Override $SubscriptionId
$ApimSubscriptionName = Get-ConfigValue -Config $config -Path 'apim.subscriptionName' -Override $ApimSubscriptionName
$TimeoutSeconds = [int](Get-ConfigValue -Config $config -Path 'tests.genieTimeoutSeconds' -Override $TimeoutSeconds)
$RequestTimeoutSeconds = [int](Get-ConfigValue -Config $config -Path 'databricks.apiTimeoutSeconds' -Override $RequestTimeoutSeconds)
if ([string]::IsNullOrWhiteSpace($ApimBaseUrl)) {
        $gatewayUrl = (Get-ConfigValue -Config $config -Path 'apim.gatewayUrl').TrimEnd('/')
        $sourceApiId = (Get-ConfigValue -Config $config -Path 'apim.sourceApiId').Trim('/')
        $ApimBaseUrl = "$gatewayUrl/$sourceApiId-genie"
}

if (-not $ApimKey) {
    $url = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.ApiManagement/service/$ApimName/subscriptions/$ApimSubscriptionName/listSecrets?api-version=2024-06-01-preview"
    $ApimKey = (az rest --method post --url $url --query primaryKey -o tsv)
    if ($LASTEXITCODE -ne 0 -or -not $ApimKey) { throw "Unable to read the APIM subscription key. Pass -ApimKey instead." }
}

$headers = @{ "Ocp-Apim-Subscription-Key" = $ApimKey; "Content-Type" = "application/json" }

Write-Host "Q: $Question" -ForegroundColor Cyan
$start = Invoke-RestMethod -Method POST -Uri "$ApimBaseUrl/genie/ask" -Headers $headers `
    -Body (@{ content = $Question } | ConvertTo-Json) -TimeoutSec $RequestTimeoutSeconds

$conversationId = $start.conversation_id
$messageId = if ($start.PSObject.Properties['message_id'] -and $start.message_id) {
    $start.message_id
} elseif ($start.PSObject.Properties['message'] -and $start.message.PSObject.Properties['id']) {
    $start.message.id
} else {
    $null
}
if (-not $conversationId -or -not $messageId) {
    throw "Genie did not return conversation/message ids. Response: $($start | ConvertTo-Json -Depth 6)"
}
Write-Host "conversation_id=$conversationId message_id=$messageId" -ForegroundColor DarkGray

$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
$message = $null
do {
    Start-Sleep -Seconds $PollIntervalSeconds
    $message = Invoke-RestMethod -Method GET -Headers $headers `
        -Uri "$ApimBaseUrl/genie/conversations/$conversationId/messages/$messageId" -TimeoutSec $RequestTimeoutSeconds
    Write-Host "  status=$($message.status)" -ForegroundColor DarkGray
} while ($message.status -notin @("COMPLETED", "FAILED", "CANCELLED", "QUERY_RESULT_EXPIRED") -and (Get-Date) -lt $deadline)

if ($message.status -ne "COMPLETED") { throw "Genie message ended with status '$($message.status)'." }

$attachments = if ($message.PSObject.Properties['attachments']) { @($message.attachments) } else { @() }
$textAnswer = @($attachments | ForEach-Object {
    if ($_.PSObject.Properties['text'] -and $_.text -and $_.text.PSObject.Properties['content']) { $_.text.content }
}) -join "`n"
if ($textAnswer.Trim()) {
    Write-Host ""
    Write-Host "Genie answer:" -ForegroundColor Green
    Write-Host $textAnswer
}

$queryAttachment = @($attachments | Where-Object { $_.PSObject.Properties['query'] -and $_.query }) | Select-Object -First 1
if ($queryAttachment) {
    Write-Host ""
    Write-Host "Generated SQL:" -ForegroundColor Green
    Write-Host $queryAttachment.query.query
    $result = Invoke-RestMethod -Method GET -Headers $headers `
        -Uri "$ApimBaseUrl/genie/conversations/$conversationId/messages/$messageId/result" -TimeoutSec $RequestTimeoutSeconds
    $columns = @($result.statement_response.manifest.schema.columns | ForEach-Object { $_.name })
    Write-Host ""
    Write-Host "Columns: $($columns -join ', ')" -ForegroundColor Green
    $rows = $result.statement_response.result.data_array
    for ($i = 0; $i -lt $rows.Count; $i++) { Write-Host "  $(($rows[$i]) -join ' | ')" }
}

Write-Host ""
Write-Host "Genie smoke test passed." -ForegroundColor Green
