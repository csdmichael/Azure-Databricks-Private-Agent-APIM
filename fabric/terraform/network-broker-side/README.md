# Broker-side VNet peering (Terraform)

This root creates only the broker-to-APIM peering. It decodes `../../config/deployment.json` by default, parses `network.brokerVnetResourceId` as the local VNet and `network.apimVnetResourceId` as the remote VNet, and configures one AzureRM provider explicitly for `azure.tenantId` and `azure.subscriptionId`.

Lifecycle preconditions require both values to match the full `Microsoft.Network/virtualNetworks` resource ID shape, require them to differ, and require their parsed subscription and resource group values to match the corresponding `azure` and `apim` config sections. AzureCAF supplies the deterministic peering name. The existing VNets are not managed. Gateway transit and remote gateways are disabled; virtual-network access and forwarded traffic are enabled.

## Validate

```powershell
terraform -chdir=fabric/terraform/network-broker-side fmt -check
terraform -chdir=fabric/terraform/network-broker-side init -backend=false
terraform -chdir=fabric/terraform/network-broker-side validate
```

## Preview and apply

Create `main.tfvars.json` from `main.tfvars.json.example`, then authenticate only to the broker tenant for this root:

```powershell
az login --tenant b158173c-91f6-4f99-b5e9-aa9bcb463863
az account set --subscription 86b37969-9445-49cf-b03f-d8866235171c
terraform -chdir=fabric/terraform/network-broker-side plan -var-file=main.tfvars.json
terraform -chdir=fabric/terraform/network-broker-side apply -var-file=main.tfvars.json
```

Do not add an APIM-tenant provider or create the reciprocal peering from this state. Authenticate to the APIM tenant separately and apply `fabric/terraform/network-apim-side`. Until that occurs, Azure can report this peering as `Initiated` rather than `Connected`.

Outputs include the peering ID and name plus the local resource group, local VNet name, remote VNet ID, and remote VNet name for `az network vnet peering show` or Terraform import/state workflows. Bicep and Terraform are alternative owners of this peering; do not apply both implementations unless the existing resource is first imported into the chosen Terraform state.