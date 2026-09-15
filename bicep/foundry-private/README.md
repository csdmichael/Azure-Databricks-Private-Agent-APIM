# Microsoft Foundry with private APIM egress

This deployment creates a side-by-side, network-injected Microsoft Foundry
account for the Databricks MCP agent. Foundry portal and data-plane ingress are
public for authenticated users, while agent tool traffic reaches API Management
through the private VNet path. It does not update the existing API Management
service, APIs, policies, products, subscriptions, private endpoint, or VNet
integration.

The original `foundry-myaacoub` account remains available as a rollback path.
Azure does not support adding outbound network injection to an existing Foundry
account, so the private deployment uses `foundry-myaacoub-private`.

## Deployed topology

| Component | Value |
| --- | --- |
| Foundry account | `foundry-myaacoub-private` |
| Foundry project | `sales-poc` |
| Project endpoint | `https://foundry-myaacoub-private.services.ai.azure.com/api/projects/sales-poc` |
| Foundry ingress | Public, authenticated with Entra ID and RBAC |
| Agent | `semiconductor-sales` |
| Model deployment | `gpt-6-astra`, version `2026-09-03`, `GlobalStandard`, capacity `500` |
| Agent subnet | `caldova-apim-westus-vnet/foundry-agent` (`10.191.2.0/24`) |
| Foundry private endpoint | `foundry-myaacoub-private-pe` (`10.191.1.5-7`) |
| APIM private endpoint | Existing `caldova-apim-westus-gateway-pe` (`10.191.1.4`) |
| MCP connection | `databricks-mcp` |

The Foundry account has `publicNetworkAccess: Enabled`, allow-by-default network
ACLs, local authentication disabled, and Agent Service network injection into the
dedicated subnet. Its private endpoint remains available for VNet clients. The
three Foundry private DNS zones are linked to both the APIM VNet and the peered
Databricks VNet that contains the validation jump VM.

## Deploy

Register the required providers, validate the exact change set, and deploy:

```powershell
az provider register --namespace Microsoft.App --wait
az provider register --namespace Microsoft.ContainerService --wait

az deployment group what-if `
  --resource-group m365-myaacoub `
  --template-file bicep/foundry-private/main.bicep `
  --parameters bicep/foundry-private/main.bicepparam

az deployment group create `
  --resource-group m365-myaacoub `
  --name foundry-private `
  --template-file bicep/foundry-private/main.bicep `
  --parameters bicep/foundry-private/main.bicepparam
```

Account provisioning can briefly remain in `Accepted`. If the private endpoint
reports `AccountProvisioningStateInvalid`, wait until the account reports
`Succeeded`, confirm the project capability host was not created, and rerun the
same idempotent deployment.

## Configure and test the agent

Create the project connection without printing or persisting the APIM key:

```powershell
./scripts/create-private-foundry-connection.ps1
```

Portal and SDK clients can access the Foundry endpoint publicly with Entra ID and
project RBAC. The reference deployment also uses the existing `caldova-jump` VM
with a system-assigned identity and the `Foundry User` role scoped to the project
to validate the private endpoint and private DNS path.

```powershell
az vm start -g m365-myaacoub -n caldova-jump

az vm run-command invoke `
  -g m365-myaacoub `
  -n caldova-jump `
  --command-id RunPowerShellScript `
  --scripts '@scripts/test-private-foundry-network.ps1'

az vm run-command invoke `
  -g m365-myaacoub `
  -n caldova-jump `
  --command-id RunPowerShellScript `
  --scripts '@scripts/provision-private-foundry-agent.ps1' `
  --parameters Mode=All

az vm deallocate -g m365-myaacoub -n caldova-jump
```

The test fails unless Foundry and APIM resolve to private IP addresses and the
agent response contains a completed, error-free MCP call.

## Verified state

On 2026-09-14:

- The Foundry account, project, capability host, model deployment, private
  endpoint, DNS links, and agent subnet all reported `Succeeded`.
- The Foundry private endpoint connection was `Approved`.
- An authenticated caller outside the linked VNets reached the agent data plane.
- From `caldova-jump`, Foundry resolved to `10.191.1.7` and APIM to `10.191.1.4`.
- Agent version 1 completed a `tables` MCP call with no error from both the
  private jump host and a public client.
- APIM remained `StandardV2`, `publicNetworkAccess: Disabled`, VNet integrated,
  and its existing `Gateway` private endpoint remained `Approved`.

## Rollback and cleanup

Cut back to the original `foundry-myaacoub` project without deleting it. To
remove the private deployment, delete the project capability host first, then
delete and purge `foundry-myaacoub-private`. Wait for the
`legionservicelink` association to clear before deleting or reusing the
`foundry-agent` subnet. Delete the Foundry private endpoint and its three private
DNS zones only after the account is purged. Do not delete the shared APIM private
endpoint or `privatelink.azure-api.net` zone.