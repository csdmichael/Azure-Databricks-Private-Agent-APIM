<#
.SYNOPSIS
  End-to-end smoke test of the Databricks Genie API exposed through APIM.

.DESCRIPTION
  Runs the full ask -> poll -> result flow against
  https://<apim>.azure-api.net/databricks-genie. The APIM subscription key is
  read at run time from the APIM subscription (listSecrets) unless -ApimKey is
  supplied, and is never written to disk or echoed.

.EXAMPLE
  ./scripts/test-genie.ps1
  ./scripts/test-genie.ps1 -Question "Top 3 product families by revenue?"
#>
[CmdletBinding()]
param(
    [string] $Question = "What was total revenue in USD millions by region? Return the top 5 regions.",
    [string] $ApimBaseUrl = "https://ai-gateway-apim-poc-my.azure-api.net/databricks-genie",
    [string] $ApimKey,
    [string] $ResourceGroup = "ai-myaacoub",
    [string] $ApimName = "ai-gateway-apim-poc-my",
    [string] $SubscriptionId = "86b37969-9445-49cf-b03f-d8866235171c",
    [string] $ApimSubscriptionName = "DatabricksSubscription",
    [int]    $TimeoutSeconds = 300
)

$ErrorActionPreference = "Stop"

if (-not $ApimKey) {
    $url = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.ApiManagement/service/$ApimName/subscriptions/$ApimSubscriptionName/listSecrets?api-version=2024-06-01-preview"
    $ApimKey = (az rest --method post --url $url --query primaryKey -o tsv)
    if ($LASTEXITCODE -ne 0 -or -not $ApimKey) { throw "Unable to read the APIM subscription key. Pass -ApimKey instead." }
}

$headers = @{ "Ocp-Apim-Subscription-Key" = $ApimKey; "Content-Type" = "application/json" }

Write-Host "Q: $Question" -ForegroundColor Cyan
$start = Invoke-RestMethod -Method POST -Uri "$ApimBaseUrl/genie/ask" -Headers $headers `
    -Body (@{ content = $Question } | ConvertTo-Json)

$conversationId = $start.conversation_id
$messageId = if ($start.message_id) { $start.message_id } else { $start.message.id }
if (-not $conversationId -or -not $messageId) {
    throw "Genie did not return conversation/message ids. Response: $($start | ConvertTo-Json -Depth 6)"
}
Write-Host "conversation_id=$conversationId message_id=$messageId" -ForegroundColor DarkGray

$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
$message = $null
do {
    Start-Sleep -Seconds 4
    $message = Invoke-RestMethod -Method GET -Headers $headers `
        -Uri "$ApimBaseUrl/genie/conversations/$conversationId/messages/$messageId"
    Write-Host "  status=$($message.status)" -ForegroundColor DarkGray
} while ($message.status -notin @("COMPLETED", "FAILED", "CANCELLED", "QUERY_RESULT_EXPIRED") -and (Get-Date) -lt $deadline)

if ($message.status -ne "COMPLETED") { throw "Genie message ended with status '$($message.status)'." }

$textAnswer = @($message.attachments | ForEach-Object { $_.text.content }) -join "`n"
if ($textAnswer.Trim()) {
    Write-Host ""
    Write-Host "Genie answer:" -ForegroundColor Green
    Write-Host $textAnswer
}

$queryAttachment = @($message.attachments | Where-Object { $_.query }) | Select-Object -First 1
if ($queryAttachment) {
    Write-Host ""
    Write-Host "Generated SQL:" -ForegroundColor Green
    Write-Host $queryAttachment.query.query
    $result = Invoke-RestMethod -Method GET -Headers $headers `
        -Uri "$ApimBaseUrl/genie/conversations/$conversationId/messages/$messageId/result"
    $columns = @($result.statement_response.manifest.schema.columns | ForEach-Object { $_.name })
    Write-Host ""
    Write-Host "Columns: $($columns -join ', ')" -ForegroundColor Green
    $rows = $result.statement_response.result.data_array
    for ($i = 0; $i -lt $rows.Count; $i++) { Write-Host "  $(($rows[$i]) -join ' | ')" }
}

Write-Host ""
Write-Host "Genie smoke test passed." -ForegroundColor Green
