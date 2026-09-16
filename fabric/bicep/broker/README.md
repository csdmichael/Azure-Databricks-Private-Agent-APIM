# Fabric-tenant broker Bicep

This resource-group deployment creates the Fabric-tenant OBO broker infrastructure. It references the existing App Service plan by `broker.existingPlanName` and the existing broker VNet/subnets by resource ID. It creates blob, queue, and table storage private endpoints plus the private deployment-package container. It does not create a Fabric workspace Private Link, change a Fabric item, or link private DNS to any VNet other than `network.brokerVnetResourceId`.

## Shared configuration contract

Bicep cannot read a local JSON file. The deployment script is responsible for reading `fabric/config/deployment.json`, selecting `azure.subscriptionId` in `azure.tenantId`, targeting `azure.resourceGroup`, and passing these values to `main.bicep`:

| Bicep parameter | Shared config path |
| --- | --- |
| `location` | `azure.location` |
| `functionAppName` | `broker.appName` |
| `existingPlanName` | `broker.existingPlanName` |
| `brokerVnetResourceId` | `network.brokerVnetResourceId` |
| `privateEndpointSubnetResourceId` | `network.brokerPrivateEndpointSubnetResourceId` |
| `integrationSubnetResourceId` | `network.brokerIntegrationSubnetResourceId` |
| `azureTenantId` | `azure.tenantId` |
| `resourceTenantId` | `identity.resourceTenantId` |
| `callerTenantId` | `identity.callerTenantId` |
| `brokerApplicationRole` | `identity.brokerApplicationRole` |
| `delegatedScope` | `identity.delegatedScope` |
| `fabricApiScope` | `identity.fabricApiScope` |
| `powerBiApiScope` | `identity.powerBiApiScope` |
| `fabricWorkspaceId` | `fabric.workspaceId` |
| `fabricLakehouseName` | `fabric.lakehouseName` |
| `fabricSqlEndpointHost` | `fabric.sqlEndpointHost` |
| `fabricDataAgentId` | `fabric.dataAgentId` |
| `runtime`, `alwaysOn`, timeout and limit parameters | matching `broker.*` properties |
| `allowedUserObjectIds` | `identity.allowedUserObjectIds` |
| `tags` | `tags` |

The deployment script must separately provide `currentDeployerPrincipalId` and the generated nonsecret values `entraApiClientId`, `brokerAudience`, `apimPrincipalId`, and `allowedConnectorClientIds`. `deploymentContainerName` and `packageBlobName` are script inputs with secure defaults of `deployments` and `fabric-obo-broker.zip`; they are not currently fields in `deployment.json`. No generated client ID is embedded in this directory. Start from `main.parameters.json.example`, replacing its config markers in memory or in a gitignored working file.

Before deployment, the script must verify that the active Azure CLI context reports the configured subscription and tenant. The deployment command contract is:

```powershell
$config = Get-Content -Raw ../../config/deployment.json | ConvertFrom-Json
az account set --subscription $config.azure.subscriptionId
$context = az account show | ConvertFrom-Json
if ($context.tenantId -ne $config.azure.tenantId) { throw 'Azure tenant does not match deployment.json' }
az deployment group create --subscription $config.azure.subscriptionId --resource-group $config.azure.resourceGroup --template-file ./main.bicep --parameters '@main.parameters.json'
```

The working parameter file is the deployment script's output and must not contain the OBO secret value.

## Two-stage deployment

1. Deploy with `deployFunction=false`. This creates the UAMI, storage account, private deployment container, Key Vault, Log Analytics workspace, Application Insights, RBAC, private DNS, and the blob/queue/table/vault private endpoints. The current deployer receives Key Vault Secrets Officer and Storage Blob Data Contributor at storage-account scope.
2. Put the OBO credential in the output vault using an approved secret-management process. The template never creates or reads a secret resource.
3. Build the package outside this template. A config-driven deployment script may temporarily enable storage public network access, allow only the deployer's current public `<IP>/32`, upload to the configured container/blob with `az storage blob upload --auth-mode login`, remove the rule, and restore public network access to `Disabled` in a `finally` block. Do not use account keys or connection strings. The package must exist before stage 2.
4. Complete the Entra/APIM identity provisioning and populate all generated ID parameters plus both nonempty allowlists.
5. Deploy with `deployFunction=true`. The `generated-input-guard.bicep` module rejects empty generated IDs or allowlists before the Function App is created.

`OBO_CLIENT_SECRET` is a versionless `@Microsoft.KeyVault(...)` reference. `keyVaultReferenceIdentity`, identity-based `AzureWebJobsStorage__*`, and `WEBSITE_RUN_FROM_PACKAGE_BLOB_MI_RESOURCE_ID` all use the UAMI. `WEBSITE_RUN_FROM_PACKAGE` is the HTTPS URL emitted as `packageBlobUrl`, without a SAS token. The UAMI has the repository-required storage and Key Vault roles; role-assignment names are deterministic ARM `guid()` values.

Key Vault intentionally keeps `publicNetworkAccess=Enabled` as required for this broker workflow while also exposing a private endpoint. Storage and the Function App have public network access disabled.

The Function App explicitly waits for the deployment container, UAMI storage roles, storage private DNS links, and blob/queue/table private endpoint DNS zone groups. This prevents the Functions host from starting before its identity-based package and host-storage paths are available.

## Validation

```powershell
az bicep build --file main.bicep
az bicep lint --file main.bicep
```

Use incremental mode only. Run `az deployment group what-if` before either stage and confirm the existing plan, VNet, and subnets are referenced rather than modified.

Outputs include `deploymentContainerId` and `packageBlobUrl`, the Function URL and sites private-endpoint IP when stage 2 is enabled, plus the vault, storage, Application Insights, Log Analytics, and UAMI principal/client identifiers.