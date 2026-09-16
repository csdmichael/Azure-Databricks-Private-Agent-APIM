# Private Microsoft Foundry Terraform parity

This root module is Terraform parity for `bicep/foundry-private/main.bicep` and
`main.bicepparam` only. It creates the Foundry account, project, model
deployment, network-injected agent subnet, private endpoint and DNS topology,
and project Agents capability host while referencing the two existing virtual
networks and the existing private endpoint subnet.

## Configuration

By default, the module reads `../../config/deployment.json`. Set `config_path`
to use another deployment configuration. Nullable variables provide explicit
overrides without requiring credentials or secrets in Terraform source.

The Bicep parameter values map as follows:

| Bicep parameter | Default source |
| --- | --- |
| `location` | `network.foundryLocation` |
| `foundryAccountName` | `foundry.private.accountName` |
| `publicNetworkAccess` | `foundry.private.publicNetworkAccess` |
| `projectName` | `foundry.private.projectName` |
| `projectCapabilityHostName` | `foundry.private.capabilityHostName` |
| Model name, version, deployment, SKU, capacity | `foundry.private.*` |
| Existing VNet names | `network.apimVnetName`, `network.databricksVnetName` |
| Subnet names and agent CIDR | `network.privateEndpointSubnetName`, `network.foundryAgentSubnet*` |
| Tags | `tags`, merged with `component=foundry-private` |

The account SKU (`S0`), project description, project display name, and model
upgrade policy retain the parameter-file values when the shared configuration
does not define them. Generated NSG, private endpoint, connection, and DNS-link
names use the `aztfmod/azurecaf` provider and resolve to the Bicep names.

## Usage

Authenticate Terraform to Azure without placing credentials in this directory,
then run:

```powershell
Set-Location terraform/foundry-private
terraform init -backend=false
terraform validate
terraform plan -var-file=main.tfvars.json.example
```

The `azurerm` and `azapi` providers both receive the explicit subscription ID
resolved from `subscription_id` or `azure.subscriptionId` in `config_path`.

## Parity notes

- The Foundry account and project use system-assigned identities. Their
  principal IDs are exported for downstream RBAC, matching the Bicep outputs.
- The source Bicep contains no role assignments. This module intentionally does
  not invent any; caller and workload RBAC remains external to this parity
  scope.
- `publicNetworkAccess` defaults to the Bicep value (`Enabled`). Consequently,
  the account ACL defaults to `Allow`; setting it to `Disabled` changes the ACL
  default action to `Deny`, exactly as the Bicep conditional does.
- The capability host uses the source preview API and disables AzAPI schema
  validation only for the undocumented `capabilityHostKind = "Agents"`
  property, corresponding to the Bicep `BCP037` suppression.
- The capability host waits for the private DNS zone group and all client-VNet
  DNS links. The Foundry account waits for the subnet-to-NSG association before
  network injection.
- If the Bicep deployment already owns these resources, import them into this
  module's state before planning. Terraform cannot automatically adopt Bicep-
  created resources.

## Outputs

Output names match the Bicep template: `foundryAccountId`,
`foundryAccountPrincipalId`, `foundryProjectId`,
`foundryProjectPrincipalId`, `foundryProjectEndpoint`, `agentSubnetId`,
`privateEndpointId`, `projectCapabilityHostId`, and `modelDeploymentName`.