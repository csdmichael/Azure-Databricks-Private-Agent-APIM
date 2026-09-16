# Broker-side VNet peering (Bicep)

This resource-group-scoped template creates only the broker-to-APIM peering. It loads `../../config/deployment.json` directly, uses `network.brokerVnetResourceId` as the local VNet, and uses `network.apimVnetResourceId` as the remote VNet.

Stable `fail()`-backed deployment preconditions require both values to be full `Microsoft.Network/virtualNetworks` resource IDs, require them to differ, and require the local ID and active deployment scope to match `azure.subscriptionId`, `azure.tenantId`, and `azure.resourceGroup`. The existing VNets are not managed. Gateway transit and remote gateways are disabled; virtual-network access and forwarded traffic are enabled.

## Validate

```powershell
az bicep build --file fabric/bicep/network-broker-side/main.bicep
az bicep lint --file fabric/bicep/network-broker-side/main.bicep
```

## Preview and deploy

Authenticate to the broker tenant and select only the broker subscription before running this deployment:

```powershell
az login --tenant b158173c-91f6-4f99-b5e9-aa9bcb463863
az account set --subscription 86b37969-9445-49cf-b03f-d8866235171c
az deployment group what-if --resource-group ai-myaacoub --template-file fabric/bicep/network-broker-side/main.bicep
az deployment group create --resource-group ai-myaacoub --template-file fabric/bicep/network-broker-side/main.bicep
```

Do not combine this deployment with the APIM-side deployment. Authenticate to the other tenant separately and deploy `fabric/bicep/network-apim-side` to create the reciprocal peering. Until that occurs, Azure can report the broker-side peering as `Initiated` rather than `Connected`.

Outputs include the peering ID and name plus the local resource group, local VNet name, remote VNet ID, and remote VNet name for state inspection or import workflows. The example parameter file is intentionally empty because all inputs come from the shared configuration.