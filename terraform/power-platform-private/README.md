# Power Platform private networking Terraform

This root module reproduces `bicep/power-platform-private/main.bicep` and its parameter file. It references the existing resource group, API Management VNet, and `privatelink.azure-api.net` private DNS zone. It creates:

- Primary and secondary Power Platform VNets.
- One equally sized subnet in each VNet, delegated to `Microsoft.PowerPlatform/enterprisePolicies`.
- Four bidirectional peerings between the Power Platform VNets and the APIM VNet.
- APIM private DNS zone links for both Power Platform VNets.
- A `NetworkInjection` Power Platform enterprise policy containing both delegated subnets.

The Bicep source contains no NSGs or route tables, so this parity module does not introduce them. Existing names come from the shared config. Deterministic peering names retain the Bicep formulas and are validated in Azure CAF passthrough mode, so CAF does not add slugs or change deployed names.

## Configuration

`config_path` defaults to `../../config/deployment.json`. The module reads provider, resource-group, APIM, regional VNet/subnet, enterprise-policy, and tag defaults from that file. The policy geo is derived from the configured primary region using the same Canada and United States mapping as `scripts/deploy-infra.ps1`; set `policy_location` for another supported Power Platform geography.

`main.tfvars.json.example` contains no secrets. Every config-backed setting has an optional Terraform variable override.

## Prerequisites and caveats

- Terraform 1.8 or later and Azure authentication with access to the configured subscription.
- The `Microsoft.Network` and `Microsoft.PowerPlatform` resource providers must be registered.
- The existing APIM VNet and `privatelink.azure-api.net` zone must be in the configured resource group.
- `Microsoft.PowerPlatform/enterprisePolicies@2020-10-30-preview` is not modeled by AzureRM, so the module uses AzAPI 2.x with embedded schema validation disabled for that resource only.
- Both delegated subnets must have the same prefix length, belong to a supported Power Platform region pair, and remain dedicated to one enterprise policy.
- Linking the enterprise policy to a Power Platform environment is outside the Bicep template and remains a post-deployment operation.
- If Bicep already deployed these resources, import them before applying Terraform to avoid create conflicts.

## Validate and deploy

Run from this directory:

```powershell
terraform fmt -recursive
terraform init -backend=false
terraform validate
terraform plan -var-file=main.tfvars.json
terraform apply -var-file=main.tfvars.json
```

Configure a durable backend before shared or production use. Apply this module before `../power-platform-databricks-direct` when creating the Power Platform VNets for the first time.

## Outputs

The output names match the Bicep template: `primaryVnetResourceId`, `primarySubnetResourceId`, `secondaryVnetResourceId`, `secondarySubnetResourceId`, `enterprisePolicyName`, and `enterprisePolicyResourceId`. No secret values are accepted or exposed.