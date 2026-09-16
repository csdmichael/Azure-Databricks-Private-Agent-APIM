[CmdletBinding()]
param(
    [string] $ConfigPath = (Join-Path $PSScriptRoot '../config/deployment.json'),
    [switch] $DeploymentReady,
    [switch] $IncludeParity,
    [switch] $SkipTerraformInit
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'config.ps1')

$config = Get-FabricDeploymentConfig -Path $ConfigPath
$fabricRoot = Split-Path -Parent $PSScriptRoot
$repositoryRoot = Split-Path -Parent $fabricRoot
$defaultConfigPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath((Join-Path $fabricRoot 'config/deployment.json'))
$resolvedConfigPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ConfigPath)
if (-not [string]::Equals($defaultConfigPath, $resolvedConfigPath, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'validate.ps1 accepts only fabric/config/deployment.json because the APIM and network Bicep entry points load that exact file.'
}

foreach ($path in 'azure.tenantId', 'azure.subscriptionId', 'fabric.workspaceId', 'fabric.lakehouseId', 'fabric.sqlEndpointId', 'fabric.dataAgentId', 'apim.tenantId', 'apim.subscriptionId', 'identity.resourceTenantId', 'identity.callerTenantId') {
    $null = Assert-FabricGuid -Value (Get-FabricConfigValue -Config $config -Path $path) -Name $path
}
if ($config.azure.tenantId -ne $config.identity.resourceTenantId) {
    throw 'azure.tenantId must match identity.resourceTenantId.'
}
if ($config.apim.tenantId -ne $config.identity.callerTenantId -or $config.powerPlatform.tenantId -ne $config.identity.callerTenantId) {
    throw 'APIM and Power Platform tenant IDs must match identity.callerTenantId.'
}
if ([bool]$config.deployment.deployWorkspacePrivateLink) {
    throw 'deployment.deployWorkspacePrivateLink must remain false while unsupported semantic models or external Copilot integrations exist.'
}
if ($config.identity.fabricApiScope -ne 'https://api.fabric.microsoft.com/.default' -or $config.identity.powerBiApiScope -ne 'https://analysis.windows.net/powerbi/api/.default') {
    throw 'Fabric and Power BI downstream scopes must use the approved fixed values.'
}
if ($config.fabric.sqlEndpointHost -notmatch '^[a-z0-9-]+\.datawarehouse\.fabric\.microsoft\.com$') {
    throw 'fabric.sqlEndpointHost is not a Microsoft Fabric SQL endpoint host.'
}
if ($config.apim.gatewayUrl -notmatch '^https://[a-z0-9-]+\.azure-api\.net/?$') {
    throw 'apim.gatewayUrl must be an HTTPS azure-api.net origin.'
}
foreach ($path in 'network.brokerVnetResourceId', 'network.brokerPrivateEndpointSubnetResourceId', 'network.brokerIntegrationSubnetResourceId', 'network.apimVnetResourceId') {
    $resourceId = [string](Get-FabricConfigValue -Config $config -Path $path)
    if ($resourceId -notmatch '^/subscriptions/[0-9a-f-]+/resourceGroups/[^/]+/providers/Microsoft\.Network/virtualNetworks/[^/]+(?:/subnets/[^/]+)?$') {
        throw "$path is not a valid virtual network or subnet resource ID."
    }
}

if ($DeploymentReady) {
    $null = Assert-FabricGuid -Value $config.powerPlatform.environmentId -Name 'powerPlatform.environmentId'
    $null = Assert-FabricGuidList -Values @($config.identity.allowedUserObjectIds) -Name 'identity.allowedUserObjectIds'
}

Write-Host 'PASS configuration contract'

Push-Location $repositoryRoot
try {
    Invoke-FabricNative -FilePath 'npm' -ArgumentList @('run', 'build', '--prefix', 'fabric/functions/obo-broker') -Description 'Broker build'
    Invoke-FabricNative -FilePath 'npm' -ArgumentList @('test', '--prefix', 'fabric/functions/obo-broker') -Description 'Broker tests'
    Invoke-FabricNative -FilePath 'npm' -ArgumentList @('audit', '--prefix', 'fabric/functions/obo-broker', '--omit=dev') -Description 'Broker production dependency audit'

    foreach ($file in Get-ChildItem (Join-Path $fabricRoot 'apim/openapi/*.json')) {
        $null = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
    }
    foreach ($file in Get-ChildItem (Join-Path $fabricRoot 'apim/policies/*.xml')) {
        [xml]$policy = Get-Content -LiteralPath $file.FullName -Raw
        if ($policy.DocumentElement.Name -ne 'policies') {
            throw "Invalid APIM policy root in $($file.FullName)."
        }
    }
    Write-Host 'PASS APIM OpenAPI and policy syntax'

    $bicepFiles = @(
        'fabric/bicep/network-apim-side/main.bicep',
        'fabric/bicep/network-broker-side/main.bicep',
        'fabric/bicep/broker/main.bicep',
        'fabric/bicep/apim/main.bicep'
    )
    foreach ($file in $bicepFiles) {
        $compiled = az bicep build --file $file --stdout
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($compiled)) {
            throw "Bicep build failed: $file"
        }
        az bicep lint --file $file
        if ($LASTEXITCODE -ne 0) {
            throw "Bicep lint failed: $file"
        }
    }
    Write-Host 'PASS Bicep build and lint'

    $terraformModules = @(
        'fabric/terraform/network-apim-side',
        'fabric/terraform/network-broker-side',
        'fabric/terraform/broker',
        'fabric/terraform/apim'
    )
    if ($IncludeParity) {
        $terraformModules += @(Get-ChildItem (Join-Path $repositoryRoot 'terraform') -Directory | Where-Object { Test-Path (Join-Path $_.FullName 'versions.tf') } | ForEach-Object { "terraform/$($_.Name)" })
    }
    foreach ($module in $terraformModules) {
        Invoke-FabricNative -FilePath 'terraform' -ArgumentList @("-chdir=$module", 'fmt', '-check') -Description "Terraform formatting for $module"
        if (-not $SkipTerraformInit) {
            Invoke-FabricNative -FilePath 'terraform' -ArgumentList @("-chdir=$module", 'init', '-backend=false', '-input=false', '-no-color') -Description "Terraform initialization for $module"
        }
        Invoke-FabricNative -FilePath 'terraform' -ArgumentList @("-chdir=$module", 'validate', '-no-color') -Description "Terraform validation for $module"
    }
    Write-Host 'PASS Terraform formatting and validation'

    $parseFailures = @()
    foreach ($file in Get-ChildItem (Join-Path $fabricRoot 'scripts/*.ps1')) {
        $tokens = $null
        $parseErrors = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors)
        if ($parseErrors.Count -gt 0) {
            $parseFailures += "$($file.Name): $($parseErrors.Message -join '; ')"
        }
    }
    if ($parseFailures.Count -gt 0) {
        throw "PowerShell parse failures: $($parseFailures -join ' | ')"
    }
    Write-Host 'PASS PowerShell syntax'

    & (Join-Path $fabricRoot 'tests/scripts.test.ps1')
}
finally {
    Pop-Location
}

Write-Host 'Fabric local validation completed successfully.' -ForegroundColor Green