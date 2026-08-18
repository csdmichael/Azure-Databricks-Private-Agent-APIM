<#
.SYNOPSIS
  Creates (or reuses) the AI/BI Genie space over the Arrow semiconductor sample
  data and points the APIM `databricks-genie-space-id` named value at it.

.DESCRIPTION
  Genie spaces are created from a serialized (version 2) payload that lists the
  data sources, sample questions, and instructions. Authentication uses the
  caller's Azure AD token for the Azure Databricks resource, so no PAT is needed.

.EXAMPLE
  ./scripts/create-genie-space.ps1
  ./scripts/create-genie-space.ps1 -SkipApimUpdate
#>
[CmdletBinding()]
param(
    [string] $WorkspaceUrl = "https://adb-7405608662655754.14.azuredatabricks.net",
    [string] $WarehouseId = "64777231f8249fdb",
    [string] $Catalog = "databricks_ws_ai_poc",
    [string] $Schema = "arrow_semiconductor",
    [string] $Title = "Arrow Semiconductor Analytics",
    [string] $ResourceGroup = "ai-myaacoub",
    [string] $ApimName = "ai-gateway-apim-poc-my",
    [string] $SubscriptionId = "86b37969-9445-49cf-b03f-d8866235171c",
    [string] $ApimApplicationId = "49ff6000-cfb2-4b1c-94cc-4de99251d5d6",
    [switch] $SkipApimUpdate
)

$ErrorActionPreference = "Stop"
$DatabricksResourceId = "2ff814a6-3304-4ab8-85cb-cd0e6f879c1d"

function New-GenieId {
    -join ((1..32) | ForEach-Object { '0123456789abcdef'[(Get-Random -Maximum 16)] })
}

Write-Host "Acquiring Azure AD token for Azure Databricks..." -ForegroundColor Cyan
$token = az account get-access-token --resource $DatabricksResourceId --query accessToken -o tsv
if ($LASTEXITCODE -ne 0 -or -not $token) { throw "Unable to acquire a Databricks access token. Run 'az login' first." }
$headers = @{ Authorization = "Bearer $token"; "Content-Type" = "application/json" }

# Reuse an existing space with the same title so the script is idempotent.
$existing = $null
try {
    $list = Invoke-RestMethod -Method GET -Uri "$WorkspaceUrl/api/2.0/genie/spaces?page_size=100" -Headers $headers
    $existing = @($list.spaces) | Where-Object { $_.title -eq $Title } | Select-Object -First 1
}
catch {
    Write-Warning "Could not list Genie spaces: $($_.Exception.Message)"
}

if ($existing) {
    $spaceId = $existing.space_id
    Write-Host "Reusing existing Genie space '$Title' ($spaceId)." -ForegroundColor Green
}
else {
    $fq = "$Catalog.$Schema"
    # The export proto validator rejects unsorted collections, so sort by key.
    $tables = @(
        [ordered]@{ identifier = "$fq.product_sales";   description = @("Revenue in USD, units sold, and gross margin percent by region, fiscal quarter, and product family.") }
        [ordered]@{ identifier = "$fq.fab_production";  description = @("Monthly wafer starts, good dies, and yield by fab and process node.") }
        [ordered]@{ identifier = "$fq.wafer_yield";     description = @("Actual versus target yield percent by month and process node.") }
        [ordered]@{ identifier = "$fq.defect_analysis"; description = @("Defect counts by category and severity, used for Pareto analysis.") }
        [ordered]@{ identifier = "$fq.inventory";       description = @("On-hand units, days of supply, and stock status by product family and warehouse region.") }
        [ordered]@{ identifier = "$fq.supply_chain";    description = @("Supplier lead time days, on-time delivery percent, quality score, and risk level.") }
    ) | Sort-Object -Property { $_.identifier }

    $questions = @(
        [ordered]@{ id = (New-GenieId); question = @("What was total revenue in USD millions by region for the latest fiscal quarter?") }
        [ordered]@{ id = (New-GenieId); question = @("Show monthly average wafer yield percent by process node.") }
        [ordered]@{ id = (New-GenieId); question = @("Which defect categories account for 80 percent of all defects?") }
        [ordered]@{ id = (New-GenieId); question = @("Rank suppliers by lead time and flag the high risk ones.") }
        [ordered]@{ id = (New-GenieId); question = @("Compare gross margin percent and revenue by product family.") }
    ) | Sort-Object -Property { $_.id }

    $serializedSpace = [ordered]@{
        version      = 2
        config       = [ordered]@{ sample_questions = @($questions) }
        data_sources = [ordered]@{ tables = @($tables) }
    }

    $payload = @{
        title            = $Title
        description      = "Curated Genie space over the Arrow-style semiconductor POC data in $fq."
        warehouse_id     = $WarehouseId
        serialized_space = ($serializedSpace | ConvertTo-Json -Depth 10 -Compress)
    } | ConvertTo-Json -Depth 10

    Write-Host "Creating Genie space '$Title'..." -ForegroundColor Yellow
    try {
        $created = Invoke-RestMethod -Method POST -Uri "$WorkspaceUrl/api/2.0/genie/spaces" -Headers $headers -Body $payload
    }
    catch {
        $detail = if ($_.ErrorDetails) { $_.ErrorDetails.Message } else { $_.Exception.Message }
        throw "Genie space creation failed: $detail"
    }
    $spaceId = $created.space_id
    Write-Host "Created Genie space $spaceId" -ForegroundColor Green
}

Write-Host ""
Write-Host "Genie space id : $spaceId"
Write-Host "Genie space URL: $WorkspaceUrl/genie/rooms/$spaceId"

# The APIM managed identity calls Genie on behalf of agents, so it needs CAN_RUN
# on the space itself; catalog grants alone are not enough.
if ($ApimApplicationId) {
    Write-Host ""
    Write-Host "Granting CAN_RUN on the space to the APIM managed identity ($ApimApplicationId)..." -ForegroundColor Cyan
    $acl = @{ access_control_list = @(@{ service_principal_name = $ApimApplicationId; permission_level = "CAN_RUN" }) } | ConvertTo-Json -Depth 5
    try {
        Invoke-RestMethod -Method PATCH -Uri "$WorkspaceUrl/api/2.0/permissions/genie/$spaceId" -Headers $headers -Body $acl | Out-Null
        Write-Host "Permission granted." -ForegroundColor Green
    }
    catch {
        $detail = if ($_.ErrorDetails) { $_.ErrorDetails.Message } else { $_.Exception.Message }
        Write-Warning "Could not grant Genie space permission: $detail"
    }
}

if (-not $SkipApimUpdate) {
    Write-Host ""
    Write-Host "Updating APIM named value 'databricks-genie-space-id'..." -ForegroundColor Cyan
    $nvUrl = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.ApiManagement/service/$ApimName/namedValues/databricks-genie-space-id?api-version=2024-06-01-preview"
    $nvFile = New-TemporaryFile
    @{ properties = @{ displayName = "databricks-genie-space-id"; value = $spaceId; secret = $false } } |
        ConvertTo-Json -Depth 5 | Set-Content -Path $nvFile -Encoding utf8
    az rest --method put --url $nvUrl --headers "Content-Type=application/json" --body "@$nvFile" --only-show-errors | Out-Null
    $exit = $LASTEXITCODE
    Remove-Item $nvFile -ErrorAction SilentlyContinue
    if ($exit -ne 0) { throw "Failed to update the APIM named value (exit $exit)." }
    Write-Host "APIM named value updated." -ForegroundColor Green
}

$spaceId
