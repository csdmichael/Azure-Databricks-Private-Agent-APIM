# APIM diagnostics Terraform

This root module reproduces `bicep/apim-diagnostics/main.bicep` and its `main.bicepparam` values. It creates the Log Analytics workspace and attaches one diagnostic setting to an existing API Management service.

## Parity

| Surface | API version | Scope |
| --- | --- | --- |
| Existing API Management service | `Microsoft.ApiManagement/service@2024-05-01` | Configured resource group |
| Log Analytics workspace | `Microsoft.OperationalInsights/workspaces@2023-09-01` | Configured resource group |
| APIM diagnostic setting | `Microsoft.Insights/diagnosticSettings@2021-05-01-preview` | Existing API Management service |

The workspace keeps the Bicep SKU, retention, daily cap, public ingestion/query access, resource-only log access, and tags. The diagnostic setting keeps the Bicep name, sends `allLogs` and `AllMetrics`, and targets the created workspace.

All resource names come directly from the shared configuration or explicit variables. AzureCAF name generation is intentionally not used because normalizing a Bicep-supplied name would change the deployed resource identity. This surface has no storage resources, so the AzureRM `storage_use_azuread` provider option does not apply.

## Configuration

`config_path` defaults to `../../config/deployment.json`. Explicit variables override these defaults:

| Configuration path | Use |
| --- | --- |
| `azure.subscriptionId` | AzureRM and AzAPI subscription |
| `azure.tenantId` | Provider tenant |
| `azure.resourceGroup` | Resource group deployment scope |
| `apim.serviceName` | Existing API Management service |
| `network.apimLocation` | Workspace region |
| `observability.logAnalyticsWorkspaceName` | Workspace name |
| `observability.retentionInDays` | Workspace retention |
| `observability.dailyQuotaGb` | Daily ingestion cap |
| `tags` | Workspace tags |

`workspace_sku_name` reads `observability.logAnalyticsWorkspaceSkuName` when present and otherwise preserves the Bicep parameter value `PerGB2018`.

## Validate and deploy

Run from this directory:

```powershell
terraform fmt -recursive -check
terraform init -backend=false
terraform validate
terraform plan -var-file=main.tfvars.json
terraform apply -var-file=main.tfvars.json
```

If the Bicep deployment already created the workspace and diagnostic setting, import them before applying Terraform. Configure a durable backend before shared or production use.

## Outputs

The output names exactly match the Bicep template: `workspaceName`, `workspaceResourceId`, `workspaceCustomerId`, and `diagnosticSettingName`.