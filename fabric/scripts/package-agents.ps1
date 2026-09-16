[CmdletBinding()]
param(
    [string] $ConfigPath = (Join-Path $PSScriptRoot '../config/deployment.json'),
    [string] $OutputDirectory = (Join-Path $PSScriptRoot '../.generated/agents'),
    [switch] $Import,
    [switch] $Publish
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'config.ps1')

$config = Get-FabricDeploymentConfig -Path $ConfigPath
if ($Import -or $Publish) {
    throw 'Cloud agent mutation is intentionally disabled in package-agents.ps1. Use this script to build source artifacts, then create/import, bind tools, verify OAuth connections and code interpreter, and publish through Copilot Studio with captured evidence.'
}
$publisherPrefix = [string](Get-FabricConfigValue -Config $config -Path 'powerPlatform.publisherPrefix')
$fabricRoot = Split-Path -Parent $PSScriptRoot
$resolvedOutput = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputDirectory)

if (-not (Get-Command pac -ErrorAction SilentlyContinue)) {
    throw 'Power Platform CLI is required. Install Microsoft.PowerApps.CLI.Tool first.'
}

New-Item -ItemType Directory -Path $resolvedOutput -Force | Out-Null
$agents = @(
    [pscustomobject]@{
        ProjectDirectory = Join-Path $fabricRoot 'agents/lakehouse'
        SchemaName = [string]$config.powerPlatform.lakehouseAgentSchemaName
        SolutionName = [string]$config.powerPlatform.lakehouseAgentSolutionName
        ConnectorName = [string]$config.powerPlatform.lakehouseConnectorName
        PromptName = [string]$config.powerPlatform.lakehouseDeckPromptName
    },
    [pscustomobject]@{
        ProjectDirectory = Join-Path $fabricRoot 'agents/data-agent'
        SchemaName = [string]$config.powerPlatform.dataAgentAgentSchemaName
        SolutionName = [string]$config.powerPlatform.dataAgentAgentSolutionName
        ConnectorName = [string]$config.powerPlatform.dataAgentConnectorName
        PromptName = [string]$config.powerPlatform.dataAgentDeckPromptName
    }
)

foreach ($agent in $agents) {
    pac copilot pack --publisher-prefix $publisherPrefix --project-dir $agent.ProjectDirectory --solution-name $agent.SolutionName --output-path $resolvedOutput
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to package agent '$($agent.SchemaName)'."
    }
}

$packages = @()
foreach ($agent in $agents) {
    $candidatePackages = @(Get-ChildItem -Path $resolvedOutput -Filter "$($agent.SolutionName)*.zip" | Sort-Object LastWriteTimeUtc -Descending)
    if ($candidatePackages.Count -eq 0) {
        throw "Package output was not found for '$($agent.SolutionName)'."
    }
    $packages += [pscustomobject]@{ Agent = $agent; Package = $candidatePackages[0] }
}

$packageEvidence = @{}
foreach ($entry in $packages) {
    $packageEvidence[$entry.Agent.SchemaName] = Get-FabricAgentPackageEvidence `
        -PackagePath $entry.Package.FullName `
        -SchemaName $entry.Agent.SchemaName `
        -ConnectorName $entry.Agent.ConnectorName `
        -PromptName $entry.Agent.PromptName
}

$packages | ForEach-Object {
    $evidence = $packageEvidence[$_.Agent.SchemaName]
    [pscustomobject]@{
        SchemaName = $_.Agent.SchemaName
        SolutionName = $_.Agent.SolutionName
        PackagePath = $_.Package.FullName
        BoundComponentCount = $evidence.BoundComponentCount
        ContainsExpectedConnectorText = $evidence.HasExpectedConnector
        ContainsExpectedPromptText = $evidence.HasExpectedPrompt
        ContainsConnectionReferenceText = $evidence.HasConnectionReference
        CloudMutationPerformed = $false
    }
}