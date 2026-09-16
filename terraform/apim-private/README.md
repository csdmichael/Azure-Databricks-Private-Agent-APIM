# Private API Management

Terraform parity implementation of `bicep/apim-private/main.bicep`. The module creates API Management, its dedicated virtual network and subnets, bidirectional Databricks peering, private DNS links, and the gateway private endpoint.

## Prerequisites

- Terraform 1.5 or later
- An authenticated Azure identity with permission to create the resources
- The resource group, Databricks virtual network, and `privatelink.azuredatabricks.net` private DNS zone already exist
- `config/deployment.json` contains the shared Azure, APIM, network, and tag values

## Inputs

Values already represented in `config/deployment.json` are loaded through `config_path` and may be overridden with Terraform variables. The publisher identity, APIM SKU, capacity, and staged public network state are supplied through a tfvars file; see `main.tfvars.json.example`.

## Staged Lockdown

Deploy stage 1 with `public_network_access` set to `Enabled`. Validate private gateway connectivity and DNS resolution, then run the same configuration with `public_network_access` set to `Disabled`. Terraform updates the existing APIM service while retaining the private endpoint and network resources.

## Validation

```powershell
terraform fmt -recursive
terraform init -backend=false
terraform validate
```

No secrets are required by this module.