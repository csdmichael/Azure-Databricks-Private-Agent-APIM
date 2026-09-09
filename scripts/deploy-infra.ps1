<#
.SYNOPSIS
  Deploys the Caldova private Databricks + APIM + Power Platform environment.

.DESCRIPTION
  Every resource lands in the subscription/resource group below. Steps are
  ordered; `lockdown` must run last because the earlier steps need public
  control-plane access to load data and validate the private endpoints.

    providers      Register the required resource providers.
    databricks     Terraform: VNet-injected Databricks in West US 2 (stage 1).
    data           Create the Unity Catalog schema and load the dataset.
    apim           Bicep: private APIM in West US + peering to Databricks.
    powerplatform  Bicep: East/West US Power Platform VNets + enterprise policy.
    link           Bind the enterprise policy to the Power Platform environment.
    lockdown       Stage 2: disable public network access on Databricks + APIM.

.EXAMPLE
  ./deploy.ps1 -Step all
.EXAMPLE
  ./deploy.ps1 -Step lockdown
#>
[CmdletBinding()]
param(
  [ValidateSet('providers', 'databricks', 'data', 'apim', 'powerplatform', 'link', 'lockdown', 'all')]
  [string] $Step = 'all',
  [string] $SubscriptionId = 'cf824570-a8ba-497a-a184-0a52f1830aa9',
  [string] $ResourceGroup = 'm365-myaacoub',
  [string] $ApimServiceName = 'caldova-apim-westus',
  [string] $PowerPlatformEnvironmentId = 'd35d1518-b911-ec93-b145-aec5290161f0'
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$tf = Join-Path $root 'terraform'
$apimDir = Join-Path $root 'bicep/apim-private'
$ppDir = Join-Path $root 'bicep/power-platform-private'

function Assert-LastExit { param([string]$What) if ($LASTEXITCODE -ne 0) { throw "$What failed with exit code $LASTEXITCODE." } }

function Step-Header { param([string]$Name) Write-Host "`n=== $Name ===" -ForegroundColor Cyan }

$run = { param([string]$Name) $Step -eq 'all' -or $Step -eq $Name }

az account set --subscription $SubscriptionId
Assert-LastExit 'az account set'

if (& $run 'providers') {
  Step-Header 'Register resource providers'
  foreach ($p in 'Microsoft.Databricks', 'Microsoft.ApiManagement', 'Microsoft.Network', 'Microsoft.PowerPlatform', 'Microsoft.Storage', 'Microsoft.ManagedIdentity', 'Microsoft.KeyVault') {
    az provider register --namespace $p --wait
    Assert-LastExit "register $p"
    Write-Host "  registered: $p"
  }
}

if (& $run 'databricks') {
  Step-Header 'Databricks (West US 2, stage 1)'
  terraform -chdir="$tf" init -input=false
  Assert-LastExit 'terraform init'
  terraform -chdir="$tf" apply -input=false -auto-approve -var "lockdown=false"
  Assert-LastExit 'terraform apply'
}

if (& $run 'data') {
  Step-Header 'Unity Catalog schema and data'
  $workspaceUrl = terraform -chdir="$tf" output -raw workspace_url
  Assert-LastExit 'terraform output workspace_url'
  & (Join-Path $PSScriptRoot 'load-catalog-data.ps1') -WorkspaceUrl $workspaceUrl
}

if (& $run 'apim') {
  Step-Header 'API Management (West US, stage 1) + VNet peering'
  $dbxVnet = terraform -chdir="$tf" output -raw vnet_name
  Assert-LastExit 'terraform output vnet_name'
  az deployment group create `
    --resource-group $ResourceGroup `
    --name caldova-apim-private `
    --template-file (Join-Path $apimDir 'main.bicep') `
    --parameters (Join-Path $apimDir 'stage1.bicepparam') `
    --parameters apimServiceName=$ApimServiceName databricksVnetName=$dbxVnet `
    --query properties.outputs -o json
  Assert-LastExit 'apim deployment'
}

if (& $run 'powerplatform') {
  Step-Header 'Power Platform VNets + enterprise policy'
  az deployment group create `
    --resource-group $ResourceGroup `
    --name caldova-power-platform-private `
    --template-file (Join-Path $ppDir 'main.bicep') `
    --parameters apimServiceName=$ApimServiceName `
    --query properties.outputs -o json
  Assert-LastExit 'power platform deployment'
}

if (& $run 'link') {
  Step-Header 'Link Power Platform environment'
  $policyId = az deployment group show `
    --resource-group $ResourceGroup `
    --name caldova-power-platform-private `
    --query properties.outputs.enterprisePolicyResourceId.value -o tsv
  Assert-LastExit 'read enterprise policy id'
  & (Join-Path $PSScriptRoot 'link-power-platform-environment.ps1') `
    -EnvironmentId $PowerPlatformEnvironmentId -PolicyArmId $policyId
}

if (& $run 'lockdown') {
  Step-Header 'Stage 2 lockdown: disable public network access'
  terraform -chdir="$tf" apply -input=false -auto-approve -var "lockdown=true"
  Assert-LastExit 'terraform lockdown apply'

  $dbxVnet = terraform -chdir="$tf" output -raw vnet_name
  az deployment group create `
    --resource-group $ResourceGroup `
    --name caldova-apim-private-lockdown `
    --template-file (Join-Path $apimDir 'main.bicep') `
    --parameters (Join-Path $apimDir 'stage2.bicepparam') `
    --parameters apimServiceName=$ApimServiceName databricksVnetName=$dbxVnet `
    --query properties.outputs -o json
  Assert-LastExit 'apim lockdown deployment'
}

Write-Host "`nDone: step '$Step'." -ForegroundColor Green
