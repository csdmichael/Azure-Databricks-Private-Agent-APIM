<#
.SYNOPSIS
  Deploys the configured private Databricks + APIM + Power Platform environment.

.DESCRIPTION
  Every resource lands in the subscription/resource group below. Steps are
  ordered; `lockdown` must run last because the earlier steps need public
  control-plane access to load data and validate the private endpoints.

    providers      Register the required resource providers.
    databricks     Terraform: VNet-injected Databricks (stage 1).
    data           Create the Unity Catalog schema and load the dataset.
    apim           Bicep: private APIM + peering to Databricks.
    powerplatform  Bicep: Power Platform VNets + enterprise policy.
    link           Bind the enterprise policy to the Power Platform environment.
    lockdown       Stage 2: disable public network access on Databricks + APIM.

.EXAMPLE
  ./deploy.ps1 -Step all
.EXAMPLE
  ./deploy.ps1 -Step lockdown
#>
[CmdletBinding()]
param(
  [string] $ConfigPath = (Join-Path $PSScriptRoot '../config/deployment.json'),
  [ValidateSet('providers', 'databricks', 'data', 'apim', 'powerplatform', 'link', 'lockdown', 'all')]
  [string] $Step = 'all',
  [string] $SubscriptionId,
  [string] $ResourceGroup,
  [string] $ApimServiceName,
  [string] $PowerPlatformEnvironmentId,
  [string] $DatabricksLocation,
  [string] $DatabricksVnetName,
  [string] $ApimLocation,
  [string] $ApimVnetCidr,
  [string] $ApimIntegrationSubnetName,
  [string] $ApimIntegrationSubnetCidr,
  [string] $PrivateEndpointSubnetName,
  [string] $PrivateEndpointSubnetCidr,
  [string] $PowerPlatformPrimaryRegion,
  [string] $PowerPlatformSecondaryRegion,
  [string] $PowerPlatformPrimaryVnetName,
  [string] $PowerPlatformSecondaryVnetName,
  [string] $PowerPlatformSubnetName,
  [string] $PowerPlatformPrimaryVnetCidr,
  [string] $PowerPlatformPrimarySubnetCidr,
  [string] $PowerPlatformSecondaryVnetCidr,
  [string] $PowerPlatformSecondarySubnetCidr,
  [string] $PowerPlatformPolicyLocation,
  [string] $PowerPlatformEnterprisePolicyName,
  [string] $ApimDeploymentName,
  [string] $ApimLockdownDeploymentName,
  [string] $PowerPlatformDeploymentName
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'config.ps1')

$config = Get-DeploymentConfig -Path $ConfigPath
$SubscriptionId = Get-ConfigValue -Config $config -Path 'azure.subscriptionId' -Override $SubscriptionId
$ResourceGroup = Get-ConfigValue -Config $config -Path 'azure.resourceGroup' -Override $ResourceGroup
$ApimServiceName = Get-ConfigValue -Config $config -Path 'apim.serviceName' -Override $ApimServiceName
$PowerPlatformEnvironmentId = Get-ConfigValue -Config $config -Path 'powerPlatform.infrastructureEnvironmentId' -Override $PowerPlatformEnvironmentId
$DatabricksLocation = Get-ConfigValue -Config $config -Path 'network.databricksLocation' -Override $DatabricksLocation
$DatabricksVnetName = Get-ConfigValue -Config $config -Path 'network.databricksVnetName' -Override $DatabricksVnetName
$ApimLocation = Get-ConfigValue -Config $config -Path 'network.apimLocation' -Override $ApimLocation
$ApimVnetCidr = Get-ConfigValue -Config $config -Path 'network.apimVnetCidr' -Override $ApimVnetCidr
$ApimIntegrationSubnetName = Get-ConfigValue -Config $config -Path 'network.apimIntegrationSubnetName' -Override $ApimIntegrationSubnetName
$ApimIntegrationSubnetCidr = Get-ConfigValue -Config $config -Path 'network.apimIntegrationSubnetCidr' -Override $ApimIntegrationSubnetCidr
$PrivateEndpointSubnetName = Get-ConfigValue -Config $config -Path 'network.privateEndpointSubnetName' -Override $PrivateEndpointSubnetName
$PrivateEndpointSubnetCidr = Get-ConfigValue -Config $config -Path 'network.privateEndpointSubnetCidr' -Override $PrivateEndpointSubnetCidr
$PowerPlatformPrimaryRegion = Get-ConfigValue -Config $config -Path 'network.powerPlatformPrimaryRegion' -Override $PowerPlatformPrimaryRegion
$PowerPlatformSecondaryRegion = Get-ConfigValue -Config $config -Path 'network.powerPlatformSecondaryRegion' -Override $PowerPlatformSecondaryRegion
$PowerPlatformPrimaryVnetName = Get-ConfigValue -Config $config -Path 'network.powerPlatformPrimaryVnetName' -Override $PowerPlatformPrimaryVnetName
$PowerPlatformSecondaryVnetName = Get-ConfigValue -Config $config -Path 'network.powerPlatformSecondaryVnetName' -Override $PowerPlatformSecondaryVnetName
$PowerPlatformSubnetName = Get-ConfigValue -Config $config -Path 'network.powerPlatformSubnetName' -Override $PowerPlatformSubnetName
$PowerPlatformPrimaryVnetCidr = Get-ConfigValue -Config $config -Path 'network.powerPlatformPrimaryVnetCidr' -Override $PowerPlatformPrimaryVnetCidr
$PowerPlatformPrimarySubnetCidr = Get-ConfigValue -Config $config -Path 'network.powerPlatformPrimarySubnetCidr' -Override $PowerPlatformPrimarySubnetCidr
$PowerPlatformSecondaryVnetCidr = Get-ConfigValue -Config $config -Path 'network.powerPlatformSecondaryVnetCidr' -Override $PowerPlatformSecondaryVnetCidr
$PowerPlatformSecondarySubnetCidr = Get-ConfigValue -Config $config -Path 'network.powerPlatformSecondarySubnetCidr' -Override $PowerPlatformSecondarySubnetCidr
$PowerPlatformEnterprisePolicyName = Get-ConfigValue -Config $config -Path 'powerPlatform.enterprisePolicyName' -Override $PowerPlatformEnterprisePolicyName
$ApimDeploymentName = Get-ConfigValue -Config $config -Path 'deployments.apimPrivateName' -Override $ApimDeploymentName
$ApimLockdownDeploymentName = Get-ConfigValue -Config $config -Path 'deployments.apimLockdownName' -Override $ApimLockdownDeploymentName
$PowerPlatformDeploymentName = Get-ConfigValue -Config $config -Path 'deployments.powerPlatformPrivateName' -Override $PowerPlatformDeploymentName
if ([string]::IsNullOrWhiteSpace($PowerPlatformPolicyLocation)) {
  $policyGeographies = @{
    canadacentral = 'canada'
    canadaeast = 'canada'
    eastus = 'unitedstates'
    eastus2 = 'unitedstates'
    centralus = 'unitedstates'
    northcentralus = 'unitedstates'
    southcentralus = 'unitedstates'
    westcentralus = 'unitedstates'
    westus = 'unitedstates'
    westus2 = 'unitedstates'
    westus3 = 'unitedstates'
  }
  $PowerPlatformPolicyLocation = $policyGeographies[$PowerPlatformPrimaryRegion]
  if (-not $PowerPlatformPolicyLocation) {
    throw "Cannot derive a Power Platform policy geography from region '$PowerPlatformPrimaryRegion'. Pass -PowerPlatformPolicyLocation explicitly."
  }
}

$root = Split-Path -Parent $PSScriptRoot
$tf = Join-Path $root 'terraform'
$apimDir = Join-Path $root 'bicep/apim-private'
$ppDir = Join-Path $root 'bicep/power-platform-private'
$tagsJson = $config.tags | ConvertTo-Json -Compress
$terraformVariables = @(
  '-var', "subscription_id=$SubscriptionId",
  '-var', "resource_group_name=$ResourceGroup",
  '-var', "location=$DatabricksLocation",
  '-var', "vnet_name=$DatabricksVnetName"
)

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
  Step-Header "Databricks ($DatabricksLocation, stage 1)"
  terraform -chdir="$tf" init -input=false
  Assert-LastExit 'terraform init'
  terraform -chdir="$tf" apply -input=false -auto-approve @terraformVariables -var "lockdown=false"
  Assert-LastExit 'terraform apply'
}

if (& $run 'data') {
  Step-Header 'Unity Catalog schema and data'
  $workspaceUrl = terraform -chdir="$tf" output -raw workspace_url
  Assert-LastExit 'terraform output workspace_url'
  & (Join-Path $PSScriptRoot 'load-catalog-data.ps1') -ConfigPath $ConfigPath -WorkspaceUrl $workspaceUrl
}

if (& $run 'apim') {
  Step-Header "API Management ($ApimLocation, stage 1) + VNet peering"
  $dbxVnet = terraform -chdir="$tf" output -raw vnet_name
  Assert-LastExit 'terraform output vnet_name'
  az deployment group create `
    --resource-group $ResourceGroup `
    --name $ApimDeploymentName `
    --template-file (Join-Path $apimDir 'main.bicep') `
    --parameters (Join-Path $apimDir 'stage1.bicepparam') `
    --parameters apimServiceName=$ApimServiceName location=$ApimLocation databricksVnetName=$dbxVnet `
    apimVnetCidr=$ApimVnetCidr integrationSubnetName=$ApimIntegrationSubnetName integrationSubnetCidr=$ApimIntegrationSubnetCidr `
    privateEndpointSubnetName=$PrivateEndpointSubnetName privateEndpointSubnetCidr=$PrivateEndpointSubnetCidr "tags=$tagsJson" `
    --subscription $SubscriptionId `
    --query properties.outputs -o json
  Assert-LastExit 'apim deployment'
}

if (& $run 'powerplatform') {
  Step-Header 'Power Platform VNets + enterprise policy'
  az deployment group create `
    --resource-group $ResourceGroup `
    --name $PowerPlatformDeploymentName `
    --template-file (Join-Path $ppDir 'main.bicep') `
    --parameters apimServiceName=$ApimServiceName primaryRegion=$PowerPlatformPrimaryRegion secondaryRegion=$PowerPlatformSecondaryRegion `
    primaryVnetName=$PowerPlatformPrimaryVnetName secondaryVnetName=$PowerPlatformSecondaryVnetName powerPlatformSubnetName=$PowerPlatformSubnetName `
    primaryVnetCidr=$PowerPlatformPrimaryVnetCidr primarySubnetCidr=$PowerPlatformPrimarySubnetCidr `
    secondaryVnetCidr=$PowerPlatformSecondaryVnetCidr secondarySubnetCidr=$PowerPlatformSecondarySubnetCidr `
    policyLocation=$PowerPlatformPolicyLocation enterprisePolicyName=$PowerPlatformEnterprisePolicyName "tags=$tagsJson" `
    --subscription $SubscriptionId `
    --query properties.outputs -o json
  Assert-LastExit 'power platform deployment'
}

if (& $run 'link') {
  Step-Header 'Link Power Platform environment'
  $policyId = az deployment group show `
    --resource-group $ResourceGroup `
    --name $PowerPlatformDeploymentName `
    --subscription $SubscriptionId `
    --query properties.outputs.enterprisePolicyResourceId.value -o tsv
  Assert-LastExit 'read enterprise policy id'
  & (Join-Path $PSScriptRoot 'link-power-platform-environment.ps1') `
    -ConfigPath $ConfigPath -EnvironmentId $PowerPlatformEnvironmentId -PolicyArmId $policyId
}

if (& $run 'lockdown') {
  Step-Header 'Stage 2 lockdown: disable public network access'
  terraform -chdir="$tf" apply -input=false -auto-approve @terraformVariables -var "lockdown=true"
  Assert-LastExit 'terraform lockdown apply'

  $dbxVnet = terraform -chdir="$tf" output -raw vnet_name
  az deployment group create `
    --resource-group $ResourceGroup `
    --name $ApimLockdownDeploymentName `
    --template-file (Join-Path $apimDir 'main.bicep') `
    --parameters (Join-Path $apimDir 'stage2.bicepparam') `
    --parameters apimServiceName=$ApimServiceName location=$ApimLocation databricksVnetName=$dbxVnet `
    apimVnetCidr=$ApimVnetCidr integrationSubnetName=$ApimIntegrationSubnetName integrationSubnetCidr=$ApimIntegrationSubnetCidr `
    privateEndpointSubnetName=$PrivateEndpointSubnetName privateEndpointSubnetCidr=$PrivateEndpointSubnetCidr "tags=$tagsJson" `
    --subscription $SubscriptionId `
    --query properties.outputs -o json
  Assert-LastExit 'apim lockdown deployment'
}

Write-Host "`nDone: step '$Step'." -ForegroundColor Green
