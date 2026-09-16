# APIM-side VNet peering (Bicep)

This resource-group-scoped template creates only the APIM-to-broker peering. It loads `../../config/deployment.json` directly, uses `network.apimVnetResourceId` as the local VNet, and uses `network.brokerVnetResourceId` as the remote VNet.

Stable `fail()`-backed deployment preconditions require both values to be full `Microsoft.Network/virtualNetworks` resource IDs, require them to differ, and require the local ID and active deployment scope to match `apim.subscriptionId`, `apim.tenantId`, and `apim.resourceGroup`. The remote ID must match the configured `azure` subscription and resource group. The existing VNets are not managed. Gateway transit and remote gateways are disabled; virtual-network access and forwarded traffic are enabled.

## Validate

```powershell
az bicep build --file fabric/bicep/network-apim-side/main.bicep
az bicep lint --file fabric/bicep/network-apim-side/main.bicep
```

## Preview and deploy

Authenticate to the APIM tenant and select only the APIM subscription before running this deployment:

```powershell
az login --tenant 12a4b86b-e64c-43f9-af05-d9130a72dfd2
az account set --subscription cf824570-a8ba-497a-a184-0a52f1830aa9
az deployment group what-if --resource-group m365-myaacoub --template-file fabric/bicep/network-apim-side/main.bicep
az deployment group create --resource-group m365-myaacoub --template-file fabric/bicep/network-apim-side/main.bicep
```

Do not combine this deployment with the broker-side deployment. Authenticate to the other tenant separately and deploy `fabric/bicep/network-broker-side` to create the reciprocal peering. Until that occurs, Azure can report the APIM-side peering as `Initiated` rather than `Connected`.

Outputs include the peering ID and name plus the local resource group, local VNet name, remote VNet ID, and remote VNet name for state inspection or import workflows. The example parameter file is intentionally empty because all inputs come from the shared configuration.