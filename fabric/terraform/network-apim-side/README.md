# APIM-side VNet peering (Terraform)

This root creates only the APIM-to-broker peering. It decodes `../../config/deployment.json` by default, parses `network.apimVnetResourceId` as the local VNet and `network.brokerVnetResourceId` as the remote VNet, and configures one AzureRM provider explicitly for `apim.tenantId` and `apim.subscriptionId`.

Lifecycle preconditions require both values to match the full `Microsoft.Network/virtualNetworks` resource ID shape, require them to differ, and require their parsed subscription and resource group values to match the corresponding `apim` and `azure` config sections. AzureCAF supplies the deterministic peering name. The existing VNets are not managed. Gateway transit and remote gateways are disabled; virtual-network access and forwarded traffic are enabled.

## Validate

```powershell
terraform -chdir=fabric/terraform/network-apim-side fmt -check
terraform -chdir=fabric/terraform/network-apim-side init -backend=false
terraform -chdir=fabric/terraform/network-apim-side validate
```

## Preview and apply

Create `main.tfvars.json` from `main.tfvars.json.example`, then authenticate only to the APIM tenant for this root:

```powershell
az login --tenant 12a4b86b-e64c-43f9-af05-d9130a72dfd2
az account set --subscription cf824570-a8ba-497a-a184-0a52f1830aa9
terraform -chdir=fabric/terraform/network-apim-side plan -var-file=main.tfvars.json
terraform -chdir=fabric/terraform/network-apim-side apply -var-file=main.tfvars.json
```

Do not add a broker-tenant provider or create the reciprocal peering from this state. Authenticate to the broker tenant separately and apply `fabric/terraform/network-broker-side`. Until that occurs, Azure can report this peering as `Initiated` rather than `Connected`.

Outputs include the peering ID and name plus the local resource group, local VNet name, remote VNet ID, and remote VNet name for `az network vnet peering show` or Terraform import/state workflows. Bicep and Terraform are alternative owners of this peering; do not apply both implementations unless the existing resource is first imported into the chosen Terraform state.