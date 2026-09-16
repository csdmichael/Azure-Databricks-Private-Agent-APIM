# Microsoft Fabric OBO agents through private API Management

This guide deploys a permission-trimmed Microsoft Fabric Lakehouse API and Fabric Data Agent MCP proxy through Azure API Management (APIM). Two Copilot Studio agents use OAuth custom connectors so every Fabric request runs under the signed-in user's permissions. The broker never falls back to an application identity for data access.

> **Reference status (2026-09-16):** The Fabric Lakehouse and Data Agent are live, and the Data Agent exposes a published MCP endpoint. Broker tests, Bicep compilation, Terraform validation, policy parsing, connector definition generation, and Copilot Studio solution packaging pass locally. Azure, Entra, APIM, connector, and agent deployment evidence is added to this guide only after each live gate passes.

## Architecture

```mermaid
flowchart LR
    User[Signed-in user] --> Agent[Copilot Studio agent]
    Agent -->|OAuth authorization code| EntraResource[Fabric tenant Entra ID]
    EntraResource -->|Delegated Fabric.Access token| APIM[Private APIM REST API]
    APIM -->|Managed identity app token| Broker[Private Azure Function broker]
    APIM -->|Original user assertion| Broker
    Broker -->|Entra OBO exchange| EntraResource
    EntraResource -->|Delegated Fabric or Power BI token| Fabric
    Fabric --> SQL[Lakehouse SQL endpoint]
    Fabric --> DataAgent[Published Data Agent MCP]
    SQL -->|Permission-trimmed result| Agent
    DataAgent -->|Permission-trimmed result| Agent
    Agent -->|Code interpreter| PPTX[Downloadable executive PPTX]
```

The token path is:

1. The user signs in to a Power Platform OAuth custom connector registered in the Fabric resource tenant.
2. The connector sends a delegated v2 token for `api://<resource-api-client-id>/Fabric.Access` to APIM.
3. APIM validates tenant, audience, scope, connector client ID, user object ID, and token type.
4. APIM acquires an application token for the broker with its system-assigned managed identity and forwards the original user assertion separately.
5. The broker independently validates both tokens, then performs Microsoft Entra OBO for the fixed downstream scope.
6. Fabric applies the user's workspace, item, table, row-level, and column-level permissions.

## Contents

- [Reference Fabric screenshots](#reference-fabric-screenshots)
- [Security boundaries](#security-boundaries)
- [Prerequisites](#prerequisites)
- [Configuration](#configuration)
- [Deployment paths](#deployment-paths)
- [Identity and consent](#identity-and-consent)
- [APIM APIs and MCP](#apim-apis-and-mcp)
- [Copilot Studio agents](#copilot-studio-agents)
- [Validation and acceptance](#validation-and-acceptance)
- [Screenshot evidence checklist](#screenshot-evidence-checklist)
- [Rollback](#rollback)

## Reference Fabric screenshots

These images are actual reference-tenant views captured on 2026-09-16. They contain no token, password, client secret, APIM subscription key, or query result.

### Lakehouse and SQL analytics endpoint

**Browser URL:** <https://app.powerbi.com/groups/2b2c447d-86e1-4982-a5b6-09d2e0f3482d/lakehouses/d487748c-006e-4945-a2ac-9ddb26c999f1?ctid=b158173c-91f6-4f99-b5e9-aa9bcb463863&experience=power-bi&selectedPath=Files>

The Lakehouse view confirms the configured `lh_part_shortages_v2` item, its schema-enabled tables, files, and SQL analytics endpoint.

![Microsoft Fabric Lakehouse showing lh_part_shortages_v2 schemas, files, and SQL analytics endpoint](docs/images/01-fabric-lakehouse.png)

### Fabric Data Agent

**Browser URL:** <https://app.fabric.microsoft.com/groups/2b2c447d-86e1-4982-a5b6-09d2e0f3482d/aiskills/2ec6cb5e-2f5c-44e7-9c0d-a113cb372741?ctid=b158173c-91f6-4f99-b5e9-aa9bcb463863>

The Data Agent view confirms `agent_part_shortages`, its bound Lakehouse, selected schemas, test surface, and publish controls.

![Microsoft Fabric Data Agent agent_part_shortages with Lakehouse schemas and test surface](docs/images/02-fabric-data-agent.png)

### Published Data Agent MCP endpoint

**Browser URL:** <https://app.fabric.microsoft.com/groups/2b2c447d-86e1-4982-a5b6-09d2e0f3482d/aiskills/2ec6cb5e-2f5c-44e7-9c0d-a113cb372741?ctid=b158173c-91f6-4f99-b5e9-aa9bcb463863>

Navigation: **Data Agent > Settings > Model Context Protocol**.

The MCP view confirms the server name, published endpoint, and single tool identifier. The endpoint is configuration, not a credential; every request still requires a valid Fabric bearer token.

![Microsoft Fabric Data Agent Model Context Protocol settings showing the published endpoint and tool](docs/images/03-fabric-data-agent-mcp.png)

## Security boundaries

- The broker accepts calls only from the configured APIM system-assigned identity and requires the `Fabric.Broker.Invoke` application role.
- User assertions must be v2 delegated tokens from the Fabric resource tenant with `Fabric.Access`, an approved connector `azp`, and an explicitly allowed user `oid`.
- OBO requests use only `https://api.fabric.microsoft.com/.default` or `https://analysis.windows.net/powerbi/api/.default`.
- The resource app requests only `DataAgent.Execute.All`, `Lakehouse.Read.All`, and `SQLEndpoint.Read.All` delegated permissions.
- Lakehouse SQL accepts one read-only `SELECT` or CTE, rejects multiple statements and write primitives, and caps input length and returned rows.
- Tokens and bodies are not logged. Responses are marked `no-store`.
- The OBO client secret is written directly to Key Vault and never to source, generated metadata, command output, Terraform state, or screenshots.
- Connector credentials are generated in memory and sent directly to Power Platform.

## Prerequisites

Use accounts with the following narrowly scoped privileges:

- Fabric workspace and item read/admin rights needed to inspect the Lakehouse, Data Agent, and user grants.
- Azure rights to validate deployments, create resources, peer the configured VNets, and assign the template's scoped roles.
- Microsoft Entra rights to manage app registrations, service principals, delegated consent, and the APIM managed-identity app-role assignment.
- Power Platform environment administration in a Managed Environment with Dataverse.
- Copilot Studio authoring, solution import, code interpreter, and publish privileges.

The configured Power Platform environment must be resolved by ID before connector or agent mutation. Do not create a replacement environment automatically.

### Workspace Private Link gate

Microsoft Fabric workspace-level Private Link is intentionally disabled in [config/deployment.json](config/deployment.json). This workspace contains Power BI semantic models, which are incompatible with that workspace restriction. Do not enable inbound restriction or delete/move those items automatically. The customer-owned APIM and broker VNets can still be peered; Fabric remains a multitenant downstream service reached with delegated HTTPS tokens.

## Configuration

All nonsecret customer inputs live in [config/deployment.json](config/deployment.json). Bicep reads that file where supported; PowerShell maps it to required parameters; Terraform exposes equivalent variables and example tfvars.

Before deployment, replace or resolve:

- tenant, subscription, resource group, location, and existing resource IDs;
- Fabric workspace, Lakehouse, SQL endpoint, and Data Agent IDs;
- APIM service, gateway, API paths, product, and VNet;
- existing App Service plan and broker subnets;
- Power Platform environment ID;
- allowed Fabric-tenant user object IDs.

Never add credentials to this file.

## Deployment paths

Bicep is the live reference deployment path. Terraform is an equivalent customer option; do not let both tools manage the same deployed resources.

### Bicep

Deploy in this order:

1. [bicep/network-apim-side/main.bicep](bicep/network-apim-side/main.bicep) in the APIM subscription.
2. [bicep/network-broker-side/main.bicep](bicep/network-broker-side/main.bicep) in the Fabric broker subscription.
3. [bicep/broker/main.bicep](bicep/broker/main.bicep) with `deployFunction=false`.
4. Run [scripts/provision-identity.ps1](scripts/provision-identity.ps1) and store the OBO credential directly in the emitted Key Vault.
5. Build and upload the Function package without storage keys or SAS tokens.
6. Re-run the broker template with generated IDs, nonempty allowlists, and `deployFunction=true`.
7. Deploy [bicep/apim/main.bicep](bicep/apim/main.bicep) in the APIM subscription.
8. Run [scripts/create-connectors.ps1](scripts/create-connectors.ps1).
9. Package, import, bind tools, and publish both agents with [scripts/package-agents.ps1](scripts/package-agents.ps1).

Run incremental deployments only. Review every `what-if` result and stop on an unexpected delete, replacement, VNet change, APIM service change, or App Service plan change.

### Terraform

Equivalent independent modules are under [terraform](terraform):

- `network-apim-side`
- `network-broker-side`
- `broker`
- `apim`

Run `terraform fmt -check`, `terraform init -backend=false`, and `terraform validate` before configuring a real backend. Keep state in customer-controlled remote storage; never commit state or tfvars.

## Identity and consent

[scripts/provision-identity.ps1](scripts/provision-identity.ps1) idempotently creates or reconciles:

- a Fabric-tenant resource API with delegated `Fabric.Access`;
- separate Lakehouse and Data Agent OAuth connector clients;
- least-privilege downstream Fabric delegated permissions;
- principal-scoped consent for explicitly allowed users;
- a caller-tenant broker API with `Fabric.Broker.Invoke`;
- the APIM managed-identity role assignment.

A Caldova user must exist as a redeemed guest in the Fabric resource tenant before it can receive principal-scoped consent or pass the broker allowlist. Do not replace that requirement with tenant-wide consent.

The script writes only nonsecret IDs to the ignored `.generated` directory. With `-KeyVaultName`, a new resource-API credential goes directly from Microsoft Graph to Key Vault and is cleared from process variables.

## APIM APIs and MCP

APIM deploys two REST APIs and two MCP projections:

| Surface | Path | Purpose |
| --- | --- | --- |
| Lakehouse REST | `/fabric-lakehouse` | List visible tables and run one read-only query |
| Lakehouse MCP | `/fabric-lakehouse-mcp/mcp` | MCP projection of the governed REST operations |
| Data Agent REST | `/fabric-data-agent` | Proxy one natural-language Data Agent request |
| Data Agent MCP | `/fabric-data-agent-mcp/mcp` | MCP projection of the governed REST operation |

Copilot Studio uses OAuth custom connectors for the private APIM path. Direct Copilot Studio MCP authoring is not assumed to have Power Platform VNet injection. The connector definitions use Swagger 2.0, typed request bodies, and generated redirect URIs.

## Copilot Studio agents

Source-controlled CLI-authored agent workspaces are under [agents](agents):

- `lakehouse`: uses the Lakehouse connector.
- `data-agent`: uses the Data Agent connector.

Both define the generalized [executive-deck-builder skill](skills/executive-deck-builder/SKILL.md) and the instructions that must govern the live code-interpreter prompt. Presentation requests must gather at least three complementary permission-trimmed result sets and then generate a real downloadable `.pptx`. Every number must trace to a Fabric result.

`package-agents.ps1` creates two Dataverse solution ZIPs locally and reports non-authoritative package evidence such as component-entry count and expected-name markers. PAC CLI currently packages the local baseline as one agent component; it does not include the loose knowledge file, connector tools, connection references, or code-interpreter prompt. The script performs no cloud mutation: `-Import` and `-Publish` deliberately stop.

Complete agent setup in two phases:

1. Create or import the baseline agents in the resolved environment through an explicitly reviewed Copilot Studio operation.
2. In Copilot Studio, add the correct OAuth custom connector to each agent, create the configured prompt tool with code interpreter enabled, paste the corresponding executive-deck instructions, create a user OAuth connection, and verify both tools.
3. Clone or pull each live agent with PAC CLI so its generated action, prompt, and connection-reference components are captured in the source workspace.
4. Repackage and inspect exact solution relationships and dependencies. The text markers reported by this script are diagnostic only and do not authorize import or publication.
5. Publish in Copilot Studio only after the connector and code-interpreter prompt show **Connected**, exact relationships are reviewed, and the delegated/denied-user tests pass.

## Validation and acceptance

Run local validation:

```powershell
pwsh fabric/scripts/validate.ps1 -IncludeParity
```

Add `-DeploymentReady` only after the Power Platform environment and user allowlist are resolved.

Live acceptance requires all of the following:

- Azure validation and `what-if` pass for both peerings, both broker stages, and APIM.
- The existing App Service plan and VNets are referenced, not modified or replaced.
- Public Function and SCM endpoints are denied; APIM resolves the private Function endpoint.
- Anonymous, wrong-tenant, wrong-audience, application-token, unapproved connector, and unapproved user requests fail closed.
- An approved user lists only visible Lakehouse tables and completes a read-only query.
- The Data Agent MCP handshake initializes, lists exactly the expected tool, and returns a permission-trimmed answer.
- The denied-user test returns `403` and no downstream data.
- Both Copilot Studio agents use user OAuth connections and publish successfully.
- Each agent creates a `.pptx` that contains `ppt/presentation.xml`, native evidence visuals, source notes, and no invented values.

## Screenshot evidence checklist

Capture screenshots only after the corresponding live check passes. Put sanitized PNG files in `fabric/docs/images`, add the browser URL above each image, and blur or exclude tokens, secrets, keys, private response rows, and unrelated tenant data.

- [x] Fabric Lakehouse item and schema view.
- [x] Fabric Data Agent and bound data view.
- [x] Fabric Data Agent MCP settings.
- [ ] Resource API overview, Expose an API, v2 token manifest, and least-privilege delegated permissions.
- [ ] Both connector app overviews, generated redirect URIs, and delegated `Fabric.Access` permissions.
- [ ] Broker Function plan, identity, Key Vault reference settings, VNet integration, and sites private endpoint.
- [ ] APIM Fabric REST APIs, generated MCP APIs, named values, policy, and diagnostics.
- [ ] Bidirectional APIM/broker VNet peerings and private DNS records.
- [ ] Power Platform environment, enterprise policy, connector General/Security/Definition/Test views.
- [ ] Both Copilot Studio agents with connector tools, OAuth connection, code-interpreter prompt, and published status.
- [ ] Successful delegated Lakehouse/Data Agent tests, denied-user result, and generated deck download.

## Rollback

1. Unpublish or remove the new Copilot Studio agent solutions without changing unrelated agents.
2. Remove the two new custom connectors and their connections; revoke their principal-scoped grants and credentials.
3. Remove the additive Fabric APIs/MCP projections and private DNS records from APIM.
4. Roll the Function package back to the previous package blob, or disable the Function app.
5. Remove the broker Function/private endpoints and then base resources only after confirming no shared resource uses them.
6. Remove each VNet peering from its owning subscription.
7. Remove the dedicated app registrations only after grants, assignments, redirects, and ownership are recorded.

Do not delete Fabric workspace items, semantic models, the Lakehouse, the Data Agent, the existing APIM service, the existing App Service plan, shared VNets, or unrelated private DNS zones as part of rollback.
