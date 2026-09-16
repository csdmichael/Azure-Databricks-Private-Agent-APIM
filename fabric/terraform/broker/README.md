# Fabric-tenant broker Terraform

This root module decodes `../../config/deployment.json` by default and explicitly configures AzureRM/AzAPI for `azure.subscriptionId` and `azure.tenantId`. It targets `azure.resourceGroup`, references `broker.existingPlanName`, and uses the existing broker VNet/subnet resource IDs without managing them. AzureRM uses `storage_use_azuread=true`; AzureCAF generates deterministic, policy-compatible names from the broker name and a stable configuration hash.

The module creates blob, queue, and table storage private endpoints plus the private deployment-package container. It does not create a Fabric workspace Private Link or change any Fabric item. Its five private DNS zones link only to `network.brokerVnetResourceId`.

## Two-stage deployment

1. Create a working `terraform.tfvars.json` from `main.tfvars.json.example` and set `current_deployer_principal_id`. Keep `deploy_function=false` for the first plan/apply. This creates the UAMI, locked host storage, private deployment container, RBAC Key Vault, observability, DNS, and blob/queue/table/vault private endpoints. The deployer receives Key Vault Secrets Officer and Storage Blob Data Contributor at storage-account scope.
2. Put the OBO credential in the output vault using an approved secret-management process. Terraform accepts only `obo_client_secret_name`; it has no secret value variable, `azurerm_key_vault_secret` resource, or secret data source.
3. Build the package outside Terraform. A config-driven deployment script may temporarily enable storage public network access, allow only the deployer's current public `<IP>/32`, upload to `deployment_container_name`/`package_blob_name` with `az storage blob upload --auth-mode login`, remove the rule, and restore public network access to disabled in a `finally` block. Do not use account keys or connection strings. The package must exist before stage 2.
4. Complete Entra/APIM provisioning, then populate `entra_api_client_id`, `broker_audience`, `apim_principal_id`, `allowed_connector_client_ids`, and the user allowlist. By default the user list comes from `identity.allowedUserObjectIds`; a nonempty variable overrides it.
5. Set `deploy_function=true`. Lifecycle preconditions reject invalid/empty generated UUIDs, either empty allowlist, a non-Linux/non-B1 existing plan, Node other than 22, or disabled Always On.

The deployment container is created through the ARM management plane with AzAPI, so Terraform does not need storage data-plane or shared-key access. The Function uses its UAMI for identity-based host storage, the HTTPS `WEBSITE_RUN_FROM_PACKAGE` URL, `WEBSITE_RUN_FROM_PACKAGE_BLOB_MI_RESOURCE_ID`, and the versionless `OBO_CLIENT_SECRET` Key Vault reference. No credential or SAS token enters Terraform configuration or state. FTP and WebDeploy/SCM basic publishing are disabled, public Function access is disabled, and the sites private endpoint supplies both app and SCM private DNS records.

Key Vault intentionally keeps public network access enabled as required for this broker workflow while also exposing a private endpoint. Storage public network and shared-key access are disabled.

The Function App explicitly waits for the deployment container, UAMI storage roles, storage private DNS links, and blob/queue/table private endpoints. This prevents the Functions host from starting before its identity-based package and host-storage paths are available.

## Commands

```powershell
terraform fmt -check -recursive
terraform init -backend=false
terraform validate
terraform plan -var-file=terraform.tfvars.json
```

Review the plan before applying. It must create only broker resources and role assignments; it must not modify the existing plan, VNet, or subnets. Bicep and Terraform are alternative owners of the same logical stack and must not be applied concurrently.

Outputs include `deployment_container_id` and `package_blob_url`, the Function URL and sites private-endpoint IP when stage 2 is enabled, plus the vault, storage, Application Insights, Log Analytics, and UAMI principal/client identifiers.