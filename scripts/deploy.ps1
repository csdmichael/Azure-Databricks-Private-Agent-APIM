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
  [switch] $PlanOnly,
  [switch] $LoadData,
  [string] $TerraformDir = "$PSScriptRoot/../infra/terraform"
)

$ErrorActionPreference = "Stop"
Push-Location $TerraformDir
try {
  Write-Host "== terraform init ==" -ForegroundColor Cyan
  terraform init -input=false

  Write-Host "== terraform validate ==" -ForegroundColor Cyan
  terraform validate

  Write-Host "== terraform plan ==" -ForegroundColor Cyan
  terraform plan -input=false -out=tfplan

  if ($PlanOnly) { Write-Host "Plan-only mode; stopping." -ForegroundColor Yellow; return }

  Write-Host "== terraform apply ==" -ForegroundColor Cyan
  terraform apply -input=false -auto-approve tfplan

  $workspaceUrl = terraform output -raw workspace_url
  Write-Host "`nWorkspace URL: $workspaceUrl" -ForegroundColor Green
}
finally { Pop-Location }

if ($LoadData) {
  Write-Host "`n== loading sample data ==" -ForegroundColor Cyan
  & "$PSScriptRoot/load-sample-data.ps1" -WorkspaceUrl $workspaceUrl -UseAzureCli
}
