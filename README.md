# Azure Databricks Private Agent + APIM

Private Azure Databricks fronted by API Management, surfaced to Copilot Studio
and Microsoft 365 Copilot over a fully private network path.

The live environment is **Caldova**. Everything under
[Caldova-Env](Caldova-Env) is the current, deployed system. The previous MCAPS
proof of concept is archived, unmodified, under [old mcaps](old%20mcaps).

## Current environment

| Setting | Value |
|---|---|
| Subscription | `cf824570-a8ba-497a-a184-0a52f1830aa9` |
| Resource group | `m365-myaacoub` |
| Tenant | `12a4b86b-e64c-43f9-af05-d9130a72dfd2` |
| Databricks | `caldova-dbx-westus2` (West US 2), public access **disabled** |
| API Management | `caldova-apim-westus` (West US), public access **disabled** |
| Power Platform | `Caldova Private` (`52456fcd-1d20-ecdb-aa2e-8979e3f794f5`), canada geo |
| Catalog | `caldova_dbx_westus2.arrow_semiconductor` |

Full topology, address plan, resource URLs, and connector setup are in
[Caldova-Env/README.md](Caldova-Env/README.md).

## Layout

| Path | Purpose |
|---|---|
| [Caldova-Env](Caldova-Env) | Terraform, Bicep, scripts, connectors, and docs for the live environment |
| [apim](apim) | Databricks SQL and Genie APIs, policies, and MCP projection deployed into APIM |
| [api](api) | FastAPI service that calls Databricks through APIM |
| [ui](ui) | Angular + Ionic front end |
| [foundry](foundry) | Microsoft Foundry agent provisioning |
| [databricks](databricks) | Sample dataset SQL and exploration notebook |
| [scripts](scripts) | Deployment, data-load, and test helpers |
| [old mcaps](old%20mcaps) | Archived MCAPS proof of concept, kept for reference only |

`apim`, `api`, `ui`, `foundry`, `databricks`, and `scripts` are shared and
point at Caldova. The SQL under [databricks/sql](databricks/sql) deliberately
keeps the original catalog token, because
[load-catalog-data.ps1](Caldova-Env/scripts/load-catalog-data.ps1) rewrites it
to the target catalog at run time.

## Deploy

```powershell
az login --tenant Caldova37587778.onmicrosoft.com
./Caldova-Env/scripts/deploy.ps1 -Step all
```

Steps run in order: `providers`, `databricks`, `data`, `apim`,
`powerplatform`, `link`, `lockdown`. The lockdown step must run last, because
loading data and validating the private endpoints both require the control
planes to be reachable from the deployment host.

## Key design decisions

- **Peering is not transitive.** Each Power Platform VNet peers directly with
  the APIM VNet, and separately with the Databricks VNet for the no-APIM path.
- **Copilot Studio MCP servers are not covered by Power Platform virtual
  network support.** Reaching a private endpoint requires a custom connector,
  which is covered. See the rationale in
  [Caldova-Env/README.md](Caldova-Env/README.md#why-a-custom-connector-and-not-an-mcp-server).
- **The enterprise policy geo must match the environment geo**, which fixes the
  Azure region pair for the delegated subnets.
- **APIM authenticates to Databricks with a managed identity**, so no Databricks
  token or key is stored in Power Platform.

## Archived environment

[old mcaps](old%20mcaps) holds the original `infra`, `docs`, and README from the
MCAPS subscription. Those Azure resources have been deleted; the folder is
retained for history and is not wired into any deployment path.
