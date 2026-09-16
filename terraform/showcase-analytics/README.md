# Showcase analytics Terraform

This root module reproduces `bicep/showcase-analytics/main.bicep`. It uses AzureRM 4.x for resources with complete provider coverage and AzAPI 2.x where preserving the ARM shape matters.

## Resources

The module references the existing resource group, virtual network, private endpoint subnet, and showcase web app. It creates:

- The delegated App Service integration subnet.
- A serverless Cosmos DB account with public access and local authentication disabled, TLS 1.2, one write region, periodic backup, and the configured consistency policy.
- The SQL database and visit container, including `/day` partitioning, TTL, and the Bicep indexing policy.
- The web app managed identity's database-scoped Cosmos DB Built-in Data Contributor assignment.
- The `privatelink.documents.azure.com` private DNS zone and VNet link.
- The Cosmos DB private endpoint and its `default` DNS zone group with a `cosmos` zone configuration.
- The existing web app's `authsettingsV2` configuration.

The Cosmos account suffix uses AzAPI's ARM-compatible `unique_string` provider function. The SQL role assignment name uses ARM `guid()`'s UUIDv5 namespace and hyphen-delimited inputs, so both names match the Bicep deployment deterministically.

No tags are added because the Bicep template does not add tags.

## Configuration

`config_path` defaults to `../../config/deployment.json`. The module decodes that file with `jsondecode(file(var.config_path))` and reads these values directly:

| Configuration path | Use |
| --- | --- |
| `azure.subscriptionId` | AzureRM and AzAPI subscription |
| `azure.tenantId` | Provider tenant and Easy Auth issuer |
| `azure.resourceGroup` | Deployment scope and existing resources |
| `network.databricksLocation` | Cosmos DB and private endpoint region |
| `network.databricksVnetName` | Existing VNet |
| `network.privateEndpointSubnetName` | Existing private endpoint subnet |
| `network.genieOboIntegrationSubnetName` | Integration subnet name |
| `network.showcaseIntegrationSubnetCidr` | Integration subnet prefix |
| `showcase.appName` | Existing web app |
| `showcase.cosmosNamePrefix` | Cosmos DB account prefix |
| `showcase.cosmosDatabase` | SQL database and DNS link name |
| `showcase.cosmosContainer` | SQL container name |
| `showcase.analyticsTtlSeconds` | Container default TTL |
| `showcase.cosmosConsistencyLevel` | Default consistency |
| `showcase.cosmosZoneRedundant` | Write-region zone redundancy |
| `showcase.backupIntervalInMinutes` | Periodic backup interval |
| `showcase.backupRetentionInHours` | Periodic backup retention |
| `showcase.backupStorageRedundancy` | Backup storage redundancy |

Values absent from the shared configuration are supplied through a tfvars file:

| Variable | Purpose |
| --- | --- |
| `web_principal_id` | Principal ID returned when the existing web app's managed identity is assigned |
| `auth_client_id` | Client ID of the Microsoft Entra application used by Easy Auth |
| `cosmos_data_contributor_role_definition_guid` | Built-in Cosmos DB data-plane role GUID; parity uses `00000000-0000-0000-0000-000000000002` |
| `authentication_login_endpoint` | Optional sovereign-cloud authority override; defaults to public Azure |

The example contains no tenant, subscription, application, principal, resource, secret, or key values from a customer environment.

## Prerequisites

- Terraform 1.8 or later.
- An authenticated Azure session with permission to read the existing resources and manage the resources in this template.
- The existing resource group, VNet, private endpoint subnet, and web app named by `deployment.json`.
- A system-assigned identity already enabled on the web app; pass its principal ID as `web_principal_id`.
- The Microsoft Entra application already provisioned; pass its client ID as `auth_client_id`.
- The `SHOWCASE_AUTH_CLIENT_SECRET` app setting already populated on the web app. Terraform configures only the setting reference and never accepts or outputs the secret.

If these resources were previously deployed by Bicep, import them into this module's state before applying Terraform. The deterministic Cosmos account and SQL role assignment names are intentionally identical to Bicep and do not create parallel resources.

## Validate and deploy

Run from this directory:

```powershell
terraform init -backend=false
terraform fmt -recursive -check
terraform validate
terraform plan -var-file=main.tfvars.json
terraform apply -var-file=main.tfvars.json
```

Configure a durable backend before using this module for shared or production state. Do not commit `main.tfvars.json` if it contains environment identifiers.

## PowerShell script boundary

`scripts/deploy-showcase-analytics.ps1` performs operations that are outside `bicep/showcase-analytics/main.bicep`; this module intentionally does not absorb them:

- Checks the existing App Service plan tier.
- Enables the web app managed identity.
- Creates or finds the Entra application and service principal, creates a client credential, and sets `SHOWCASE_AUTH_CLIENT_SECRET`, `ENTRA_TENANT_ID`, `STATS_ADMIN_OBJECT_IDS`, and `WEBSITE_NODE_DEFAULT_VERSION`.
- Sets `COSMOS_ENDPOINT`, `COSMOS_DATABASE`, `COSMOS_CONTAINER`, Cosmos client tuning, Log Analytics query settings, and `ANALYTICS_TTL_SECONDS` after infrastructure deployment.
- Connects the web app to the integration subnet.
- Sets Always On, 64-bit workers, disabled FTPS, and minimum TLS 1.2 on the web app.
- Builds, packages, deploys, verifies, and rolls back the showcase application.

Those steps remain script responsibilities. In particular, this module does not manage app settings, site runtime settings, credentials, deployment packages, or VNet integration because the Bicep template does not manage them.

## Outputs

The output surface exactly matches the Bicep template:

| Output | Value |
| --- | --- |
| `cosmosEndpoint` | Cosmos DB document endpoint |
| `cosmosAccountName` | Deterministic Cosmos DB account name |
| `subnetId` | App Service integration subnet resource ID |

No connection strings, keys, credentials, or other secret outputs are exposed.