<#
.SYNOPSIS
  Creates the least-privilege Entra app and federated credential that the GitHub
  Actions workflows use to sign in to Azure with OIDC, and sets the repository
  secrets.

.DESCRIPTION
  Idempotent. Creates (or reuses) an app registration and service principal,
  adds federated credentials for the repository's main branch and pull requests,
  grants only the roles the workflows need, and writes AZURE_CLIENT_ID,
  AZURE_TENANT_ID and AZURE_SUBSCRIPTION_ID with the GitHub CLI.

  Scopes granted:
    Website Contributor  -> the API web app only (deploy-api.yml)
    Foundry User         -> the Foundry project  (provision-foundry-agent.yml)
    Foundry Project Manager -> the Foundry project (create agent versions and
                               the APIM MCP project connections)

  provision-databricks.yml runs Terraform and needs broader rights; grant those
  separately if you want that workflow to run in CI.

.EXAMPLE
  ./scripts/setup-github-oidc.ps1
#>
[CmdletBinding()]
param(
    [string] $SubscriptionId = "86b37969-9445-49cf-b03f-d8866235171c",
    [string] $ResourceGroup = "ai-myaacoub",
    [string] $Repository = "csdmichael/Azure-Databricks-Private-Agent-APIM",
    [string] $AppName = "gh-databricks-agents-poc",
    [string] $ApiAppName = "databricks-agents-api-my",
    [string] $FoundryAccountName = "002-ai-poc-private",
    [string] $FoundryProjectName = "proj-default"
)

$ErrorActionPreference = "Stop"

function Get-AzValue {
    param([string[]] $Arguments)
    $previous = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try { $output = az @Arguments 2>&1 } finally { $ErrorActionPreference = $previous }
    if ($LASTEXITCODE -ne 0) { return $null }
    $value = (@($output) | Where-Object { $_ -is [string] }) -join ""
    if ([string]::IsNullOrWhiteSpace($value)) { return $null }
    return $value.Trim()
}

Write-Host "== App registration ==" -ForegroundColor Cyan
$appId = Get-AzValue @("ad", "app", "list", "--display-name", $AppName, "--query", "[0].appId", "-o", "tsv")
if (-not $appId) {
    $appId = Get-AzValue @("ad", "app", "create", "--display-name", $AppName, "--query", "appId", "-o", "tsv")
    if (-not $appId) { throw "Could not create the app registration '$AppName'." }
    Write-Host "  created $AppName ($appId)"
}
else {
    Write-Host "  reusing $AppName ($appId)"
}

$principalId = Get-AzValue @("ad", "sp", "list", "--filter", "appId eq '$appId'", "--query", "[0].id", "-o", "tsv")
if (-not $principalId) {
    $principalId = Get-AzValue @("ad", "sp", "create", "--id", $appId, "--query", "id", "-o", "tsv")
    Write-Host "  created service principal $principalId"
}
else {
    Write-Host "  reusing service principal $principalId"
}

Write-Host "== Federated credentials ==" -ForegroundColor Cyan
# GitHub issues ID-qualified subjects, e.g.
#   repo:<owner>@<ownerId>/<repo>@<repoId>:ref:refs/heads/main
# Older, unqualified subjects are still registered so either form is accepted.
$repoInfo = gh api "repos/$Repository" --jq "{id: .id, ownerId: .owner.id}" | ConvertFrom-Json
if (-not $repoInfo.id) { throw "Could not read repository ids for $Repository." }
$owner, $name = $Repository -split "/", 2
$qualified = "$owner@$($repoInfo.ownerId)/$name@$($repoInfo.id)"

$credentials = @(
    @{ name = "github-main";    subject = "repo:$($Repository):ref:refs/heads/main" }
    @{ name = "github-pr";      subject = "repo:$($Repository):pull_request" }
    @{ name = "github-main-id"; subject = "repo:$($qualified):ref:refs/heads/main" }
    @{ name = "github-pr-id";   subject = "repo:$($qualified):pull_request" }
)
$existingNames = Get-AzValue @("ad", "app", "federated-credential", "list", "--id", $appId, "--query", "[].name", "-o", "tsv")
foreach ($credential in $credentials) {
    if ($existingNames -and ($existingNames -split "\s+") -contains $credential.name) {
        Write-Host "  '$($credential.name)' already present"
        continue
    }
    $file = New-TemporaryFile
    @{
        name      = $credential.name
        issuer    = "https://token.actions.githubusercontent.com"
        subject   = $credential.subject
        audiences = @("api://AzureADTokenExchange")
    } | ConvertTo-Json -Depth 4 | Set-Content -Path $file -Encoding utf8
    $result = Get-AzValue @("ad", "app", "federated-credential", "create", "--id", $appId, "--parameters", "@$($file.FullName)", "-o", "none")
    Remove-Item $file -ErrorAction SilentlyContinue
    Write-Host "  added '$($credential.name)' -> $($credential.subject)"
}

Write-Host "== Role assignments ==" -ForegroundColor Cyan
$projectScope = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.CognitiveServices/accounts/$FoundryAccountName/projects/$FoundryProjectName"
$webAppScope = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.Web/sites/$ApiAppName"
$assignments = @(
    @{ role = "Website Contributor";     scope = $webAppScope }
    @{ role = "Foundry User";            scope = $projectScope }
    @{ role = "Foundry Project Manager"; scope = $projectScope }
)
foreach ($assignment in $assignments) {
    $existing = Get-AzValue @("role", "assignment", "list", "--assignee", $principalId, "--scope", $assignment.scope, "--role", $assignment.role, "--query", "[0].id", "-o", "tsv")
    if ($existing) {
        Write-Host "  '$($assignment.role)' already assigned"
        continue
    }
    $result = Get-AzValue @("role", "assignment", "create", "--assignee-object-id", $principalId,
        "--assignee-principal-type", "ServicePrincipal", "--role", $assignment.role, "--scope", $assignment.scope, "-o", "none")
    if ($LASTEXITCODE -eq 0) { Write-Host "  assigned '$($assignment.role)'" }
    else { Write-Warning "  could not assign '$($assignment.role)'" }
}

Write-Host "== GitHub repository secrets ==" -ForegroundColor Cyan
$tenantId = Get-AzValue @("account", "show", "--query", "tenantId", "-o", "tsv")
gh secret set AZURE_CLIENT_ID --repo $Repository --body $appId
gh secret set AZURE_TENANT_ID --repo $Repository --body $tenantId
gh secret set AZURE_SUBSCRIPTION_ID --repo $Repository --body $SubscriptionId

Write-Host ""
Write-Host "OIDC ready for $Repository" -ForegroundColor Green
Write-Host "  client id : $appId"
Write-Host "  tenant id : $tenantId"
