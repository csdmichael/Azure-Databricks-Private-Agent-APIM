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
  [string] $EnvironmentId = '52456fcd-1d20-ecdb-aa2e-8979e3f794f5',
  [string] $TenantId = '12a4b86b-e64c-43f9-af05-d9130a72dfd2',
  [string] $SubscriptionId = 'cf824570-a8ba-497a-a184-0a52f1830aa9',
  [string] $ResourceGroup = 'm365-myaacoub',
  [string] $EnterprisePolicyName = 'caldova-pp-network-injection-canada',
  [string] $PolicyArmId,
  [int] $TimeoutSeconds = 900,
  [switch] $ForceAuth
)

$ErrorActionPreference = 'Stop'

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
