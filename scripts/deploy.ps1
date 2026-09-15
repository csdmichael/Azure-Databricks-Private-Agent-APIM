<#
.SYNOPSIS
  One-shot local deployment of the private Databricks POC via Terraform.
  Requires: Azure CLI logged in (`az login`) to the target subscription,
  and Terraform >= 1.5 on PATH.

.EXAMPLE
  ./scripts/deploy.ps1
  ./scripts/deploy.ps1 -PlanOnly
#>
[CmdletBinding()]
param(
  [string] $ConfigPath = (Join-Path $PSScriptRoot '../config/deployment.json'),
  [switch] $PlanOnly,
  [switch] $LoadData,
  [string] $TerraformDir = "$PSScriptRoot/../terraform",
  [string] $PlanFileName = 'tfplan',
  [string] $SubscriptionId,
  [string] $ResourceGroup,
  [string] $Location,
  [string] $DatabricksVnetName
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot 'config.ps1')
$config = Get-DeploymentConfig -Path $ConfigPath
$SubscriptionId = Get-ConfigValue -Config $config -Path 'azure.subscriptionId' -Override $SubscriptionId
$ResourceGroup = Get-ConfigValue -Config $config -Path 'azure.resourceGroup' -Override $ResourceGroup
$Location = Get-ConfigValue -Config $config -Path 'network.databricksLocation' -Override $Location
$DatabricksVnetName = Get-ConfigValue -Config $config -Path 'network.databricksVnetName' -Override $DatabricksVnetName
$terraformVariables = @(
  '-var', "subscription_id=$SubscriptionId",
  '-var', "resource_group_name=$ResourceGroup",
  '-var', "location=$Location",
  '-var', "vnet_name=$DatabricksVnetName"
)

az account set --subscription $SubscriptionId
if ($LASTEXITCODE -ne 0) { throw "Unable to select Azure subscription $SubscriptionId." }

Push-Location $TerraformDir
try {
  Write-Host "== terraform init ==" -ForegroundColor Cyan
  terraform init -input=false

  Write-Host "== terraform validate ==" -ForegroundColor Cyan
  terraform validate

  Write-Host "== terraform plan ==" -ForegroundColor Cyan
  terraform plan -input=false "-out=$PlanFileName" @terraformVariables

  if ($PlanOnly) { Write-Host "Plan-only mode; stopping." -ForegroundColor Yellow; return }

  Write-Host "== terraform apply ==" -ForegroundColor Cyan
  terraform apply -input=false -auto-approve $PlanFileName

  $workspaceUrl = terraform output -raw workspace_url
  Write-Host "`nWorkspace URL: $workspaceUrl" -ForegroundColor Green
}
finally { Pop-Location }

if ($LoadData) {
  Write-Host "`n== loading sample data ==" -ForegroundColor Cyan
  & "$PSScriptRoot/load-sample-data.ps1" -ConfigPath $ConfigPath -WorkspaceUrl $workspaceUrl -UseAzureCli
}
