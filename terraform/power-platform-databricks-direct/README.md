# Direct Power Platform-to-Databricks networking Terraform

This root module reproduces `bicep/power-platform-databricks-direct/main.bicep` and its parameter file. It references the existing resource group, Databricks VNet, both Power Platform VNets, and the `privatelink.azuredatabricks.net` private DNS zone. It creates:

- Four bidirectional peerings between the two Power Platform VNets and the Databricks VNet.
- Databricks private DNS zone links for both Power Platform VNets.

The two writes to the Databricks VNet are deliberately serialized, matching the Bicep dependency. The Bicep source contains no VNet, subnet, NSG, route-table, or enterprise-policy creation in this layer, so this module references those resources rather than recreating them. Deterministic peering names retain the Bicep formulas and are validated in Azure CAF passthrough mode.

## Configuration

`config_path` defaults to `../../config/deployment.json`. The module reads provider, resource-group, Databricks VNet, Power Platform region/VNet, and tag defaults from that file. Every setting has an optional Terraform variable override.

`main.tfvars.json.example` contains only the config path and no secrets.

## Prerequisites and caveats

- Terraform 1.8 or later and Azure authentication with access to the configured subscription.
- The `Microsoft.Network` resource provider must be registered.
- The Databricks and both Power Platform VNets must already exist in the configured resource group.
- The `privatelink.azuredatabricks.net` zone must already exist in that resource group.
- AzAPI is configured consistently with the companion module but manages no resource here because AzureRM covers this Bicep template completely.
- If Bicep already deployed these peerings or DNS links, import them before applying Terraform to avoid create conflicts.

## Validate and deploy

Run from this directory:

```powershell
terraform fmt -recursive
terraform init -backend=false
terraform validate
terraform plan -var-file=main.tfvars.json
terraform apply -var-file=main.tfvars.json
```

Configure a durable backend before shared or production use. Apply `../power-platform-private` first when it owns the Power Platform VNets.

## Outputs

The output names match the Bicep template: `primaryPeeringId`, `secondaryPeeringId`, `primaryDnsLinkId`, and `secondaryDnsLinkId`. No secret values are accepted or exposed.