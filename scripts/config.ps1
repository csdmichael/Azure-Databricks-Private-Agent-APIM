Set-StrictMode -Version Latest

function Get-DeploymentConfig {
    [CmdletBinding()]
    param(
        [string] $Path = (Join-Path (Split-Path -Parent $PSScriptRoot) 'config/deployment.json')
    )

    $resolvedPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    if (-not (Test-Path -LiteralPath $resolvedPath -PathType Leaf)) {
        throw "Deployment configuration file not found: $resolvedPath"
    }

    try {
        $config = Get-Content -LiteralPath $resolvedPath -Raw | ConvertFrom-Json
    }
    catch {
        throw "Deployment configuration file is not valid JSON: $resolvedPath. $($_.Exception.Message)"
    }

    foreach ($section in 'azure', 'databricks', 'apim', 'foundry', 'network') {
        if (-not $config.PSObject.Properties[$section]) {
            throw "Deployment configuration is missing the '$section' section: $resolvedPath"
        }
    }

    return $config
}

function Get-ConfigValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [object] $Config,
        [Parameter(Mandatory = $true)] [string] $Path,
        [object] $Override,
        [switch] $AllowEmpty
    )

    if ($null -ne $Override) {
        if ($Override -isnot [string] -or $AllowEmpty -or -not [string]::IsNullOrWhiteSpace($Override)) {
            return $Override
        }
    }

    $value = $Config
    foreach ($segment in $Path.Split('.')) {
        $property = $value.PSObject.Properties[$segment]
        if ($null -eq $property) {
            throw "Deployment configuration value '$Path' is missing."
        }
        $value = $property.Value
    }

    if (-not $AllowEmpty -and $value -is [string] -and [string]::IsNullOrWhiteSpace($value)) {
        throw "Deployment configuration value '$Path' cannot be empty."
    }

    return $value
}
