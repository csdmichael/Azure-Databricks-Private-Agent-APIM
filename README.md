# Azure Databricks Private Agent + APIM

Private Azure Databricks fronted by API Management, surfaced to Copilot Studio and
Microsoft 365 Copilot over a fully private network path. A Copilot Studio agent asks
natural-language questions of Unity Catalog through AI/BI Genie and returns a
high-fidelity, downloadable PowerPoint deck.

Databricks and API Management both have **public network access disabled**. Nothing in
the data path traverses the public internet.

> **Live showcase:** <https://caldova-databricks-showcase.azurewebsites.net>
> — video series, business case, features, architecture, and a link into the demo app.
>
> **Business case:** $892.5K annual run-rate benefit, 243% year-one ROI, 2.4 month payback
> at 100 active users. Full model in [docs/Business Case](docs/Business%20Case).

![End-to-end architecture: Microsoft 365 Copilot and Teams, a Copilot Studio agent on the GitHub Copilot harness, a VNet-injected Power Platform managed environment, API Management with a private gateway endpoint, and a VNet-injected Azure Databricks workspace with Unity Catalog and Genie](docs/azure-databricks-private-agent-apim-architecture.png)

---

## Contents

- [How it works](#how-it-works)
- [Technologies used](#technologies-used)
- [Portals and URLs](#portals-and-urls)
- [Current environment](#current-environment)
- [Address plan](#address-plan)
- [Repository layout](#repository-layout)
- [Deploy](#deploy)
- [Setup walkthrough](#setup-walkthrough)
  - [1. Power Platform managed environment](#1-power-platform-managed-environment)
  - [2. Delegated virtual networks](#2-delegated-virtual-networks)
  - [3. Virtual network peerings](#3-virtual-network-peerings)
  - [4. Private DNS](#4-private-dns)
  - [5. Enterprise policy](#5-enterprise-policy)
  - [6. Lock down API Management](#6-lock-down-api-management)
  - [7. Publish the Databricks APIs](#7-publish-the-databricks-apis)
  - [8. Import the custom connector](#8-import-the-custom-connector)
  - [9. Build the Copilot Studio agent](#9-build-the-copilot-studio-agent)
  - [10. Generate the deck](#10-generate-the-deck)
  - [11. Final resource group](#11-final-resource-group)
- [Why a custom connector and not an MCP server](#why-a-custom-connector-and-not-an-mcp-server)
- [The deck skill](#the-deck-skill)
- [Observability](#observability)
- [Key design decisions](#key-design-decisions)
- [Setup guide](#setup-guide)
- [Archived environment](#archived-environment)

---

## How it works

The diagram above reads left to right, in eight numbered hops.

1. **A user asks for a deck** in Microsoft 365 Copilot or Teams, in plain language.
2. **The Copilot Studio agent** picks up the request. It runs on the **GitHub Copilot
   harness**, which gives it a governed sandbox and the `executive-deck-builder` skill.
3. **The agent calls its custom connector tools.** Because the Power Platform environment
   is VNet-injected, that call leaves through a **delegated subnet** rather than the
   public internet.
4. **Traffic crosses a VNet peering** into the API Management VNet. Peering is not
   transitive, so each Power Platform regional VNet peers *directly* with the APIM VNet.
5. **APIM receives the request on its private endpoint** at `10.191.1.4`. Its public
   gateway is disabled, so this is the only way in.
6. **APIM authenticates to Databricks with its managed identity** and crosses a global
   peering into the Databricks VNet. No Databricks token or key is ever stored in Power
   Platform.
7. **Databricks answers through AI/BI Genie**, which resolves the natural-language
   question against Unity Catalog using a serverless SQL warehouse, and returns grounded
   rows.
8. **The agent builds a real `.pptx`** from those rows in its sandbox and returns it as a
   download card in the chat.

The bands across the bottom of the diagram are the cross-cutting controls: **identity**
(managed identity into Databricks, Entra ID for users), **private networking** (private
endpoints, delegated subnets, peering, private DNS), **AI gateway controls** (APIM
policies, subscription keys, rate limiting), and **observability** (APIM diagnostics into
Log Analytics).

---

## Technologies used

| Technology | Role in this solution | Where to configure |
|---|---|---|
| **Azure Databricks** (Premium, VNet injected) | Hosts the data. Unity Catalog, a serverless SQL warehouse, and the AI/BI Genie space. Public access disabled. | [Azure portal](https://portal.azure.com/) |
| **Azure Databricks AI/BI Genie** | Turns natural-language questions into governed SQL over a curated schema. | Databricks workspace → **Genie** |
| **Unity Catalog** | Catalog, schema, tables, and the grants APIM's managed identity needs. | Databricks workspace → **Catalog** |
| **Azure API Management** (StandardV2) | The only proxy in front of Databricks. Publishes the SQL and Genie REST APIs, holds the policies, and authenticates to Databricks with a managed identity. Public access disabled. | [Azure portal](https://portal.azure.com/) |
| **Azure Private Link / Private Endpoints** | Private ingress to both APIM and Databricks. | Azure portal → each resource → **Networking** |
| **Azure Private DNS zones** | `privatelink.azure-api.net` and `privatelink.azuredatabricks.net`, linked to every VNet that must resolve them. | Azure portal → **Private DNS zones** |
| **Azure Virtual Network peering** | Connects the Power Platform, APIM, and Databricks VNets. | Azure portal → VNet → **Peerings** |
| **Power Platform managed environment** | The Dataverse-backed environment that gets subnet-injected. Must be a Managed Environment. | [Power Platform admin center](https://admin.powerplatform.microsoft.com/) |
| **Power Platform enterprise policy** (`NetworkInjection`) | Binds the delegated subnets to the environment. Its geo must match the environment geo. | Azure portal + `Microsoft.PowerPlatform.EnterprisePolicies` module |
| **Power Apps custom connector** | The supported way to reach a private endpoint from Copilot Studio. Exposes the four Genie operations. | [Power Apps → Custom connectors](https://make.powerapps.com/) |
| **Microsoft Copilot Studio** (GitHub Copilot harness) | Hosts the agent, its tools, and the deck skill. The harness supplies the sandbox that writes the `.pptx`. | [Copilot Studio](https://copilotstudio.microsoft.com/) |
| **Copilot Studio skills** | Portable `SKILL.md` carrying the deck specification. | Copilot Studio → agent → **Skills** |
| **Microsoft 365 Copilot / Teams** | Where users actually talk to the agent. | Copilot Studio → **Channels** |
| **Azure Monitor / Log Analytics** | APIM gateway diagnostics for tracing every call. | Azure portal → **Log Analytics workspaces** |
| **Terraform** | Deploys the Databricks workspace, NSGs, private endpoints, and DNS. | [terraform](terraform) |
| **Bicep** | Deploys APIM, the Power Platform VNets, the enterprise policy, and diagnostics. | [bicep](bicep) |

---

## Portals and URLs

Replace the identifiers with your own where they differ.

| What | URL |
|---|---|
| **Showcase site** | <https://caldova-databricks-showcase.azurewebsites.net> |
| Azure portal | <https://portal.azure.com/> |
| Power Platform admin center | <https://admin.powerplatform.microsoft.com/> |
| This environment in the admin center | <https://admin.powerplatform.microsoft.com/manage/environments/environment/52456fcd-1d20-ecdb-aa2e-8979e3f794f5/hub> |
| Power Apps maker portal | <https://make.powerapps.com/> |
| Power Apps custom connectors | <https://make.powerapps.com/environments/52456fcd-1d20-ecdb-aa2e-8979e3f794f5/customconnectors> |
| Power Apps connections | <https://make.powerapps.com/environments/52456fcd-1d20-ecdb-aa2e-8979e3f794f5/connections> |
| Copilot Studio | <https://copilotstudio.microsoft.com/> |
| Databricks workspace | <https://adb-7405616934814750.10.azuredatabricks.net> |
| APIM gateway (private only) | `https://caldova-apim-westus.azure-api.net` |

---

## Current environment

| Setting | Value |
|---|---|
| Subscription | `cf824570-a8ba-497a-a184-0a52f1830aa9` |
| Resource group | `m365-myaacoub` |
| Tenant | `12a4b86b-e64c-43f9-af05-d9130a72dfd2` |
| Databricks | `caldova-dbx-westus2` (West US 2), public access **disabled** |
| API Management | `caldova-apim-westus` (West US), StandardV2, public access **disabled** |
| Power Platform | `Caldova Private` (`52456fcd-1d20-ecdb-aa2e-8979e3f794f5`), canada geo |
| Catalog | `caldova_dbx_westus2.arrow_semiconductor` |
| SQL warehouse | `a3c7c9526aa58992` (serverless 2X-Small, auto-stop 5 min) |
| Genie space | `01f1abe9e51e19ddbb15297aee9a5850` |
| Log Analytics | `caldova-apim-logs-westus` |
| Copilot Studio agent | `Genie Deck Builder Pro` (`0b4034e0-53b9-4ae8-a506-11e3269fa451`) |

---

## Address plan

| Purpose | Region | VNet | Subnets |
|---|---|---|---|
| Databricks | West US 2 | `10.190.0.0/16` | host `10.190.1.0/24`, container `10.190.2.0/24`, private endpoints `10.190.3.0/24` |
| API Management | West US | `10.191.0.0/16` | integration `10.191.0.0/24`, private endpoints `10.191.1.0/24` |
| Power Platform | Canada Central | `10.194.0.0/16` | delegated `10.194.0.0/24` |
| Power Platform | Canada East | `10.195.0.0/16` | delegated `10.195.0.0/24` |

Both Power Platform subnets are `/24` because the enterprise policy requires each regional
subnet to expose the same usable address count. The region pair must match the environment
geo: environment `52456fcd-1d20-ecdb-aa2e-8979e3f794f5` is `canada`, so the VNets are
`canadacentral` and `canadaeast`.

---

## Repository layout

| Path | Purpose |
|---|---|
| [terraform](terraform) | VNet-injected Databricks workspace, NSGs, private DNS zone, private endpoints |
| [bicep/apim-private](bicep/apim-private) | APIM StandardV2, VNet, gateway private endpoint, peering to Databricks |
| [bicep/power-platform-private](bicep/power-platform-private) | Regional VNets, delegated subnets, peering, network-injection policy |
| [bicep/power-platform-databricks-direct](bicep/power-platform-databricks-direct) | Peerings and DNS links for the no-APIM path |
| [bicep/apim-diagnostics](bicep/apim-diagnostics) | Log Analytics workspace and APIM diagnostic settings |
| [connector](connector) | Power Platform custom connector definitions (Swagger 2.0) |
| [skills](skills) | Reusable Copilot Studio skills |
| [ui/src/app/showcase](ui/src/app/showcase) | Showcase page hosted on the B1 App Service |
| [docs/Videos](docs/Videos) | Showcase video series (placeholder) |
| [docs/Business Case](docs/Business%20Case) | Business case PDF, PPTX, and the financial model |
| [apim](apim) | Databricks SQL and Genie APIs, policies, MCP projection |
| [api](api) | FastAPI service that calls Databricks through APIM |
| [ui](ui) | Angular + Ionic front end |
| [databricks](databricks) | Sample dataset SQL and exploration notebook |
| [scripts](scripts) | Deployment, data-load, connector, and test helpers |
| [docs/setup-guide.md](docs/setup-guide.md) | Step-by-step guide for an existing Databricks + APIM estate |
| [old mcaps](old%20mcaps) | Archived MCAPS proof of concept and the Microsoft Foundry agents |

The SQL under [databricks/sql](databricks/sql) deliberately keeps the original catalog
token, because [scripts/load-catalog-data.ps1](scripts/load-catalog-data.ps1) rewrites it
to the target catalog at run time.

---

## Deploy

```powershell
az login --tenant Caldova37587778.onmicrosoft.com
./scripts/deploy-infra.ps1 -Step all
```

Individual steps run with `-Step <name>`:

| Step | What it does |
|---|---|
| `providers` | Registers the required resource providers |
| `databricks` | Terraform apply with `lockdown=false` |
| `data` | Creates the schema and loads the dataset over the public control plane |
| `apim` | APIM with `publicNetworkAccess=Enabled`, plus both peerings |
| `powerplatform` | Power Platform VNets, peerings, DNS links, enterprise policy |
| `link` | `Enable-SubnetInjection` against the managed environment |
| `lockdown` | Terraform `lockdown=true` and APIM `publicNetworkAccess=Disabled` |

**Lockdown must run last.** Data loading and private-endpoint validation both need the
control planes reachable from the deployment host. After `lockdown`, Databricks and APIM
are only reachable from inside the peered VNets, so any later data work must run from a
host in one of those VNets.

`NoAzureDatabricksRules` is only accepted by Azure after the back-end `databricks_ui_api`
private endpoint exists, which is another reason the lockdown flip is a separate apply.

---

## Setup walkthrough

The screenshots below follow the order you actually perform the setup.

### 1. Power Platform managed environment

Start here. The environment must be a **Managed Environment with Dataverse**, and its
**geo** determines every Azure region choice that follows. Adding Dataverse is
irreversible, so never use the tenant default environment.

Portal: <https://admin.powerplatform.microsoft.com/>

Confirm the environment's region, type, and that **Managed environments** is enabled.

![Power Platform admin center showing the Caldova Private managed environment with its region and managed environment state](docs/images/01.a-power-platform-environment.png)

Virtual network support is configured under **Security → Data and privacy**. The
**Azure Virtual Network policies** entry is the one that matters here — it protects items
made in Power Platform inside your virtual network without exposing them over the public
internet. This is the tenant-level surface that binds an enterprise policy to an
environment.

![Power Platform admin center Data protection and privacy page with Azure Virtual Network policies highlighted](docs/images/01.b-power-platform-environment-Data%20Protection.png)

Opening that entry lists every environment eligible for subnet injection and the policy
attached to it. Use this as the verification step after linking: the environment should
show **Dataverse: Yes**, **Managed: Yes**, the geo you expect, and the enterprise policy
name in the **Policy** column. An environment missing Dataverse or Managed status will not
appear as eligible.

![Virtual Network policies panel listing the Caldova Private environment with Dataverse Yes, Managed Yes, Canada region, and the attached enterprise policy](docs/images/01.c-power-platform-environment-VirtualNetworkPolicies.png)

### 2. Delegated virtual networks

Create one VNet per region in the environment's geo pair. Each needs a subnet delegated to
`Microsoft.PowerPlatform/enterprisePolicies`, and both subnets must expose the same usable
address count.

![Subnets blade for caldova-pp-vnet-canadacentral showing the delegated subnet](docs/images/02-pp-vnet-canadacentral-subnets.png)

![Subnets blade for caldova-pp-vnet-canadaeast showing the delegated subnet](docs/images/03-pp-vnet-canadaeast-subnets.png)

### 3. Virtual network peerings

Peer each Power Platform VNet **directly** with the APIM VNet, and the APIM VNet with the
Databricks VNet. Peering is not transitive, so a hub-and-spoke shortcut will not work.

![Peerings blade for the APIM virtual network](docs/images/04-vnet-peerings.png)

### 4. Private DNS

Link `privatelink.azure-api.net` to the APIM VNet and to both Power Platform VNets, and
`privatelink.azuredatabricks.net` to the APIM VNet. Without these links the private
endpoint names resolve to public addresses and the calls fail.

![Private DNS zone privatelink.azure-api.net showing the gateway A record and virtual network links](docs/images/05-private-dns-apim.png)

### 5. Enterprise policy

Create the `NetworkInjection` enterprise policy in the geo that matches the environment,
then link it to the environment. This is the step that actually injects the subnets.

![Azure portal enterprise policy overview showing the Canada location](docs/images/06-enterprise-policy.png)

### 6. Lock down API Management

Once the private endpoint exists and DNS resolves, disable public network access. From
this point APIM answers only on `10.191.1.4`.

![API Management networking blade showing public network access disabled and the gateway private endpoint](docs/images/07-apim-private-networking.png)

### 7. Publish the Databricks APIs

Import the SQL and Genie REST APIs, attach the policies, and grant APIM's managed identity
access to Databricks.

![API Management APIs blade listing the Databricks SQL and Genie APIs](docs/images/08-apim-apis.png)

Both APIs can also be projected as MCP servers. Those belong to the archived Microsoft
Foundry path in [old mcaps/foundry/README.md](old%20mcaps/foundry/README.md) — they are
**not** usable from Copilot Studio over the private network. See
[why](#why-a-custom-connector-and-not-an-mcp-server).

![API Management MCP Servers blade listing databricks-genie-mcp and databricks-mcp](docs/images/09-apim-mcp-servers.png)

### 8. Import the custom connector

Create the connector in the linked environment from the Swagger 2.0 definition in
[connector](connector).

Portal: <https://make.powerapps.com/environments/52456fcd-1d20-ecdb-aa2e-8979e3f794f5/customconnectors>

![Power Apps Custom connectors list showing Databricks-Genie-Private-APIM](docs/images/10-powerapps-custom-connector.png)

Point it at the APIM host with `/databricks-genie` as the base URL.

![Custom connector General tab showing host caldova-apim-westus.azure-api.net and base URL /databricks-genie](docs/images/11-connector-general.png)

Use API key authentication with the `Ocp-Apim-Subscription-Key` header. Only the parameter
name lives in the connector; the key value goes in the connection.

![Custom connector Security tab showing API Key authentication with parameter name Ocp-Apim-Subscription-Key in the Header](docs/images/12-connector-security.png)

Confirm the four actions and their path parameters.

![Custom connector Definition tab showing Actions (4) and the request URL with conversationId and messageId path parameters](docs/images/13-connector-definition.png)

| Tool | Operation |
|---|---|
| Ask Genie (start conversation) | `POST /genie/ask` |
| Ask Genie follow-up | `POST /genie/conversations/{conversationId}/messages` |
| Get Genie message status | `GET /genie/conversations/{conversationId}/messages/{messageId}` |
| Get Genie query result | `GET /genie/conversations/{conversationId}/messages/{messageId}/result` |

> **Typed request bodies matter.** The APIM export gives `POST` bodies only an `example`,
> which produces a single opaque `body` string input. Replace it with a typed schema so the
> agent gets a real `Question` input:
> `{"type":"object","required":["content"],"properties":{"content":{"type":"string"}}}`.

### 9. Build the Copilot Studio agent

Create the agent from the Copilot Studio home page with the **New experience** toggle on,
so it runs on the **GitHub Copilot harness**. That harness natively creates Word, Excel,
PowerPoint, and PDF files in a governed sandbox, which is what makes a real `.pptx`
download possible with no extra Azure compute.

An agent on the **standard** harness has no sandbox and will tell you it cannot create
files. Agents on the GitHub Copilot harness consume Copilot Credits.

Portal: <https://copilotstudio.microsoft.com/>

![Copilot Studio Build page for Genie Deck Builder Pro showing the instructions, the executive-deck-builder skill, and the four Genie connector tools](docs/images/14-agent-build.png)

### 10. Generate the deck

Ask for a deck. The agent runs several Genie queries, writes the file, verifies it, and
returns a download card.

![Copilot Studio preview showing the agent returning 2025_Revenue_by_Region_Executive_Deck.pptx as a downloadable file](docs/images/15-deck-delivered.png)

A representative run produced a nine-slide deck with four native PowerPoint charts, a data
table, a shapes-and-connectors diagram, KPI tiles, and speaker notes on every slide:

| Region | Revenue (USD) | Share | Units | Avg selling price |
|---|---|---|---|---|
| APAC | $101,848,716.61 | 37.5% | 7,634,265 | 13.342 |
| North America | $81,655,029.21 | 30.1% | 6,088,525 | 13.402 |
| EMEA | $59,341,485.76 | 21.9% | 4,374,350 | 13.326 |
| LATAM | $28,452,604.92 | 10.5% | 2,132,707 | 13.351 |
| **Total** | **$271,297,836.50** | 100.0% | 20,229,847 | 13.411 |

The agent queried for 2024 comparatives, found none, and stated that year-over-year growth
is not computable rather than inventing it.

> **Connection state gotcha.** Every new conversation starts `Stale`. Open the card's
> connection-manager link, choose **Review**, **Submit**, then **Retry in that same
> conversation**. Also confirm the connection manager shows a **single** row covering all
> four tools — if the tools are split across two connector registrations, authorizing one
> group leaves the other `Stale` permanently. Neither is a network or key problem; APIM
> returns `200` throughout.

### 11. Final resource group

Everything lands in one resource group.

![Azure resource group m365-myaacoub showing the Databricks workspace, API Management service, virtual networks, private endpoints, private DNS zones, and the enterprise policy](docs/images/16-resource-group.png)

---

## Why a custom connector and not an MCP server

Power Platform virtual network support covers Dataverse plugins and **connectors**,
including custom connectors. It does **not** cover MCP servers.

An MCP tool added to an agent in a VNet-injected environment fails in two distinct ways,
both reproduced here:

- Authoring time: `No tools available.`
- Runtime: `that tool is not available in this chat environment`

The custom connector is the supported path to a private endpoint, so the agent uses it.

---

## The deck skill

[skills/executive-deck-builder/SKILL.md](skills/executive-deck-builder/SKILL.md) is a
portable `SKILL.md` — YAML front matter plus Markdown — that can be uploaded to any agent
on this harness. It specifies:

- 16:9 canvas, explicit placement on the blank layout, margins, and overflow caps
- A Microsoft header band, horizontal rule, and footer with slide numbers
- Native chart objects only, with chart type per purpose, axis titles, data labels, and
  number formats per unit
- Table, KPI tile, and diagram construction rules
- Four core slides plus optional sections chosen from the data, and assertion-style slide
  titles
- A verification step that reopens the saved file and asserts its contents

> The header logo is drawn programmatically from four colored squares. Replace it with
> official brand artwork for anything customer-facing; the skill already accepts a supplied
> logo image.

---

## Observability

APIM diagnostics flow to the `caldova-apim-logs-westus` Log Analytics workspace.

This deployment writes to the legacy **`AzureDiagnostics`** table, not
`ApiManagementGatewayLogs`. Querying the resource-specific table returns zero rows and
looks like there is no traffic. Use:

```kusto
AzureDiagnostics
| where ResourceProvider == "MICROSOFT.APIMANAGEMENT"
| project TimeGenerated, Category, method_s, url_s, responseCode_d, backendResponseCode_d
| order by TimeGenerated desc
```

A full deck run produces 16 calls, 3 `POST` and 13 `GET`, all `200` at both APIM and the
Databricks backend.

---

## Key design decisions

- **Peering is not transitive.** Each Power Platform VNet peers directly with the APIM
  VNet, and separately with the Databricks VNet for the no-APIM path.
- **MCP servers are not covered by Power Platform VNet support.** Reaching a private
  endpoint from Copilot Studio requires a custom connector.
- **The enterprise policy geo must match the environment geo**, which fixes the Azure
  region pair for the delegated subnets.
- **APIM authenticates to Databricks with a managed identity**, so no Databricks token or
  key is stored in Power Platform.
- **The GitHub Copilot harness is required for file creation.** The standard harness has
  no sandbox.
- **There is no server-side PowerPoint Designer API.** Designer is client-side only,
  reachable through the PowerPoint JavaScript add-in API, VBA, or COM. High fidelity comes
  from slide masters, explicit layout, and native chart objects.

---

## Setup guide

[docs/setup-guide.md](docs/setup-guide.md) is the detailed, command-by-command version of
the walkthrough above, written for a customer who already has private Databricks and API
Management and needs to connect a Power Platform managed environment to them.

---

## Archived environment

[old mcaps](old%20mcaps) holds the original `infra`, `docs`, and README from the MCAPS
subscription. Those Azure resources have been deleted; the folder is retained for history
and is not wired into any deployment path.

It also holds the **Microsoft Foundry** prompt agents, which reach the same Databricks data
through the APIM MCP servers and Code Interpreter rather than through the private custom
connector. See [old mcaps/foundry/README.md](old%20mcaps/foundry/README.md). Its workflow
is manual dispatch only and does not run on commits.
