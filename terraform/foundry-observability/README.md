# Foundry observability Terraform

This root module reproduces `bicep/foundry-observability/main.bicep` and its `main.bicepparam` values. It references both existing Foundry accounts/projects and the existing Log Analytics and Application Insights resources, then creates the Bicep connections, role assignments, and project diagnostic settings.

## Parity

| Surface | API version | Scope |
| --- | --- | --- |
| Existing Log Analytics workspace | `Microsoft.OperationalInsights/workspaces@2023-09-01` | Configured resource group |
| Existing Application Insights component | `Microsoft.Insights/components@2020-02-02` | Configured resource group |
| Existing Foundry accounts | `Microsoft.CognitiveServices/accounts@2026-05-01` | Configured resource group |
| Existing Foundry projects | `Microsoft.CognitiveServices/accounts/projects@2025-06-01` | Respective Foundry account |
| Application Insights connections | `Microsoft.CognitiveServices/accounts/connections@2025-04-01-preview` | Respective Foundry account |
| Trace-reader role assignments | `Microsoft.Authorization/roleAssignments@2022-04-01` | Existing Application Insights component |
| Project diagnostic settings | `Microsoft.Insights/diagnosticSettings@2021-05-01-preview` | Respective Foundry project |

Both account connections retain `AppInsights`, `ApiKey`, shared-to-all behavior, target and metadata resource IDs, and the existing component connection string. The connection string is read at runtime through AzAPI and is never accepted as a variable, hardcoded, or output. Because it is sent in a managed resource body, use an encrypted remote backend and restrict access to Terraform state.

Each project identity receives Log Analytics Reader (`73c42c96-874c-492b-b04d-ab87d138a893`) and Privileged Monitoring Data Reader (`dbc9c667-e97f-4491-aee6-90b9cf960190`) at Application Insights scope. Assignment names reproduce ARM/Bicep `guid(applicationInsights.id, project.id, roleDefinitionId)` with Terraform `uuidv5`, ARM's `11fb06fb-712d-4ddd-98c7-e71bbd588830` namespace, and hyphen-delimited inputs.

Project diagnostics retain the Bicep names and send `allLogs` plus `AllMetrics` to the existing workspace. All resource names come directly from the shared configuration or explicit variables. AzureCAF name generation is intentionally not used because normalizing Bicep-supplied names would break resource identity parity. This surface has no storage resources, so the AzureRM `storage_use_azuread` provider option does not apply.

## Configuration

`config_path` defaults to `../../config/deployment.json`. Explicit variables override these defaults:

| Configuration path | Use |
| --- | --- |
| `azure.subscriptionId` | AzureRM and AzAPI subscription |
| `azure.tenantId` | Provider tenant |
| `azure.resourceGroup` | Resource group lookup scope |
| `foundry.original.accountName` | Original Foundry account |
| `foundry.original.projectName` | Original Foundry project |
| `foundry.private.accountName` | Private-egress Foundry account |
| `foundry.private.projectName` | Private-egress Foundry project |
| `observability.logAnalyticsWorkspaceName` | Existing workspace |
| `observability.applicationInsightsName` | Existing Application Insights component and connection name |

## Validate and deploy

Run from this directory:

```powershell
terraform fmt -recursive -check
terraform init -backend=false
terraform validate
terraform plan -var-file=main.tfvars.json
terraform apply -var-file=main.tfvars.json
```

If Bicep already created the connections, role assignments, or diagnostics, import them before applying Terraform. Configure a durable encrypted backend before shared or production use.

## Outputs

The output names exactly match the Bicep template: `logAnalyticsWorkspaceId`, `applicationInsightsId`, `originalProjectId`, and `privateProjectId`.