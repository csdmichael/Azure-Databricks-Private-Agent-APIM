<#
.SYNOPSIS
  Associates the Power Platform managed environment with the network-injection
  enterprise policy created by bicep/power-platform-private/main.bicep.

.DESCRIPTION
  Requires Power Platform Administrator rights. The environment must already be
  a Managed Environment. Use -ForceAuth when the Power Platform administrator is
  a different account than the current Azure sign-in.
#>
[CmdletBinding()]
param(
  [string] $ConfigPath = (Join-Path $PSScriptRoot '../config/deployment.json'),
  [string] $EnvironmentId,
  [string] $TenantId,
  [string] $SubscriptionId,
  [string] $ResourceGroup,
  [string] $EnterprisePolicyName,
  [string] $PolicyArmId,
  [Nullable[int]] $TimeoutSeconds,
  [switch] $ForceAuth
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'config.ps1')

$config = Get-DeploymentConfig -Path $ConfigPath
$EnvironmentId = Get-ConfigValue -Config $config -Path 'powerPlatform.connectorEnvironmentId' -Override $EnvironmentId
$TenantId = Get-ConfigValue -Config $config -Path 'azure.tenantId' -Override $TenantId
$SubscriptionId = Get-ConfigValue -Config $config -Path 'azure.subscriptionId' -Override $SubscriptionId
$ResourceGroup = Get-ConfigValue -Config $config -Path 'azure.resourceGroup' -Override $ResourceGroup
$EnterprisePolicyName = Get-ConfigValue -Config $config -Path 'powerPlatform.enterprisePolicyName' -Override $EnterprisePolicyName
$TimeoutSeconds = [int](Get-ConfigValue -Config $config -Path 'powerPlatform.linkTimeoutSeconds' -Override $TimeoutSeconds)

if (-not $PolicyArmId) {
  $PolicyArmId = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.PowerPlatform/enterprisePolicies/$EnterprisePolicyName"
}

$exists = az resource show --ids $PolicyArmId --query id -o tsv 2>$null
if (-not $exists) { throw "Enterprise policy not found: $PolicyArmId" }
Write-Host "Enterprise policy: $PolicyArmId"

if (-not (Get-Module -ListAvailable -Name Microsoft.PowerPlatform.EnterprisePolicies)) {
  Write-Host 'Installing Microsoft.PowerPlatform.EnterprisePolicies...'
  Install-Module Microsoft.PowerPlatform.EnterprisePolicies -Scope CurrentUser -Force -AllowClobber
}
Import-Module Microsoft.PowerPlatform.EnterprisePolicies -Force

$injection = @{
  EnvironmentId  = $EnvironmentId
  PolicyArmId    = $PolicyArmId
  TenantId       = $TenantId
  TimeoutSeconds = $TimeoutSeconds
}
if ($ForceAuth) { $injection.ForceAuth = $true }

Enable-SubnetInjection @injection
