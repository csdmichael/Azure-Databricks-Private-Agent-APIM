<#
.SYNOPSIS
    Creates (or reuses) an AI/BI Genie space over the configured sample data and
    points the APIM `databricks-genie-space-id` named value at it.

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
    [string] $ConfigPath = (Join-Path $PSScriptRoot '../config/deployment.json'),
    [string] $WorkspaceUrl,
    [string] $WarehouseId,
    [string] $Catalog,
    [string] $Schema,
    [string] $Title,
    [string[]] $SampleQuestions,
    [string] $ResourceGroup,
    [string] $ApimName,
    [string] $SubscriptionId,
    [string] $ApimApplicationId,
    [int] $GeniePageSize = 100,
    [switch] $SkipApimUpdate
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot 'config.ps1')

$config = Get-DeploymentConfig -Path $ConfigPath
$WorkspaceUrl = (Get-ConfigValue -Config $config -Path 'databricks.workspaceUrl' -Override $WorkspaceUrl).TrimEnd('/')
$WarehouseId = Get-ConfigValue -Config $config -Path 'databricks.warehouseId' -Override $WarehouseId
$Catalog = Get-ConfigValue -Config $config -Path 'databricks.catalog' -Override $Catalog
$Schema = Get-ConfigValue -Config $config -Path 'databricks.schema' -Override $Schema
$Title = Get-ConfigValue -Config $config -Path 'databricks.genieSpaceTitle' -Override $Title
if (-not $PSBoundParameters.ContainsKey('SampleQuestions')) {
    $SampleQuestions = @(
        Get-ConfigValue -Config $config -Path 'tests.geniePrompt'
        Get-ConfigValue -Config $config -Path 'tests.smokePrompt'
        Get-ConfigValue -Config $config -Path 'tests.apiPrompt'
    ) | Select-Object -Unique
}
$ResourceGroup = Get-ConfigValue -Config $config -Path 'azure.resourceGroup' -Override $ResourceGroup
$ApimName = Get-ConfigValue -Config $config -Path 'apim.serviceName' -Override $ApimName
$SubscriptionId = Get-ConfigValue -Config $config -Path 'azure.subscriptionId' -Override $SubscriptionId
$ApimApplicationId = Get-ConfigValue -Config $config -Path 'apim.applicationId' -Override $ApimApplicationId

# Azure Databricks is a fixed Microsoft audience ID.
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
    $list = Invoke-RestMethod -Method GET -Uri "$WorkspaceUrl/api/2.0/genie/spaces?page_size=$GeniePageSize" -Headers $headers
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

    $questions = @($SampleQuestions | ForEach-Object {
        [ordered]@{ id = (New-GenieId); question = @($_) }
    }) | Sort-Object -Property { $_.id }

    $serializedSpace = [ordered]@{
        version      = 2
        config       = [ordered]@{ sample_questions = @($questions) }
        data_sources = [ordered]@{ tables = @($tables) }
    }

    $payload = @{
        title            = $Title
        description      = "Curated Genie space over the configured data in $fq."
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
