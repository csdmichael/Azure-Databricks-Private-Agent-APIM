# APIM Sample Calls — Databricks & Genie over Private VNet

The private Databricks workspace is fronted by APIM (`ai-gateway-apim-poc-my`).
Agents call **APIM** with a subscription key; APIM authenticates to Databricks
with its **managed identity** and routes over the private connection. No
Databricks tokens are handled by the agent.

## Table of contents
- [One-time setup: grant the APIM managed identity access in Databricks](#one-time-setup-grant-the-apim-managed-identity-access-in-databricks)
- [Databricks SQL API](#databricks-sql-api)
- [Databricks Genie API](#databricks-genie-api)
- [MCP server (Foundry / Copilot Studio tools)](#mcp-server-foundry--copilot-studio-tools)
- [Agents API (this POC's own service)](#agents-api-this-pocs-own-service)
- [Understanding the response](#understanding-the-response)

---

## One-time setup: grant the APIM managed identity access in Databricks

APIM uses its **system-assigned managed identity** (SP object id shown in
APIM → Managed identities). Grant it access to the workspace and data:

```bash
# 1) APIM MI principal id + application id
APIM_MI=$(az apim show -g ai-myaacoub -n ai-gateway-apim-poc-my --query identity.principalId -o tsv)
APIM_APPID=$(az ad sp show --id "$APIM_MI" --query appId -o tsv)

# 2) Add the MI as a workspace service principal (Databricks SCIM API) and
#    grant CAN_USE on the warehouse + USE CATALOG / USE SCHEMA / SELECT.
#    Run these as a workspace admin (or via the SQL editor / Terraform databricks provider):
```
```sql
-- In a Databricks SQL editor as an admin:
GRANT USE CATALOG  ON CATALOG databricks_ws_ai_poc TO `<APIM_APPID>`;
GRANT USE SCHEMA   ON SCHEMA  databricks_ws_ai_poc.arrow_semiconductor TO `<APIM_APPID>`;
GRANT SELECT       ON SCHEMA  databricks_ws_ai_poc.arrow_semiconductor TO `<APIM_APPID>`;
-- Warehouse permission is set in the SQL Warehouse "Permissions" dialog:
--   add the service principal with "Can use".
```

> The service principal is added to the workspace via **Settings → Identity and
> access → Service principals → Add** using the managed identity's Application
> (client) ID, then given the grants above.

---

## Databricks SQL API

**Run any read query** — `POST /databricks/query`:

```bash
curl -X POST "https://ai-gateway-apim-poc-my.azure-api.net/databricks/query" \
  -H "Ocp-Apim-Subscription-Key: $APIM_KEY" \
  -H "Content-Type: application/json" \
  -d '{ "statement": "SELECT region, ROUND(SUM(revenue_usd)/1e6,2) AS revenue_musd FROM databricks_ws_ai_poc.arrow_semiconductor.product_sales GROUP BY region ORDER BY revenue_musd DESC" }'
```

PowerShell:
```powershell
$headers = @{ "Ocp-Apim-Subscription-Key" = $env:APIM_KEY; "Content-Type" = "application/json" }
$body = @{ statement = "SELECT process_node, ROUND(AVG(yield_pct)*100,2) AS yield_pct FROM databricks_ws_ai_poc.arrow_semiconductor.fab_production GROUP BY process_node ORDER BY process_node" } | ConvertTo-Json
Invoke-RestMethod -Method POST -Uri "https://ai-gateway-apim-poc-my.azure-api.net/databricks/query" -Headers $headers -Body $body
```

**List sample tables** — `GET /databricks/tables`:
```bash
curl "https://ai-gateway-apim-poc-my.azure-api.net/databricks/tables" \
  -H "Ocp-Apim-Subscription-Key: $APIM_KEY"
```

The consumer never sees the `warehouse_id` — APIM injects it from a named value.

### More example statements

| Goal | `statement` value |
|------|-------------------|
| Revenue by product family | `SELECT product_family, ROUND(SUM(revenue_usd)/1e6,2) m FROM databricks_ws_ai_poc.arrow_semiconductor.product_sales GROUP BY product_family ORDER BY m DESC` |
| Defect Pareto | `SELECT defect_category, SUM(defect_count) c FROM databricks_ws_ai_poc.arrow_semiconductor.defect_analysis GROUP BY defect_category ORDER BY c DESC` |
| Supplier risk | `SELECT supplier_name, risk_level, lead_time_days FROM databricks_ws_ai_poc.arrow_semiconductor.supply_chain ORDER BY lead_time_days DESC` |
| Executive KPIs | `SELECT (SELECT ROUND(SUM(revenue_usd)/1e6,1) FROM databricks_ws_ai_poc.arrow_semiconductor.product_sales) revenue_musd` |

---

## Databricks Genie API

Natural-language questions answered by AI/BI Genie over the same data. The Genie
space **`Arrow Semiconductor Analytics`** (id `01f19b3c346c1698910416cf7a4c830c`)
is curated over all six sample tables. The APIM managed identity has `CAN_RUN` on
it; without that grant every call returns `PERMISSION_DENIED`.

Genie is asynchronous — the flow is **ask → poll → result**.

**1. Ask** — `POST /databricks-genie/genie/ask`:
```bash
curl -X POST "https://ai-gateway-apim-poc-my.azure-api.net/databricks-genie/genie/ask" \
  -H "Ocp-Apim-Subscription-Key: $APIM_KEY" -H "Content-Type: application/json" \
  -d '{ "content": "What were the top 3 regions by revenue last quarter?" }'
# -> { "conversation_id": "01f1...", "message_id": "01f1..." }
```

**2. Poll the message** — `GET /databricks-genie/genie/conversations/{conversationId}/messages/{messageId}`:
```bash
curl "https://ai-gateway-apim-poc-my.azure-api.net/databricks-genie/genie/conversations/$CONV/messages/$MSG" \
  -H "Ocp-Apim-Subscription-Key: $APIM_KEY"
# status goes ASKING_AI -> PENDING_WAREHOUSE -> EXECUTING_QUERY -> COMPLETED
# the answer is in attachments[].text.content, the SQL in attachments[].query.query
```

**3. Get the result rows** — `GET /databricks-genie/genie/conversations/{conversationId}/messages/{messageId}/result`:
```bash
curl "https://ai-gateway-apim-poc-my.azure-api.net/databricks-genie/genie/conversations/$CONV/messages/$MSG/result" \
  -H "Ocp-Apim-Subscription-Key: $APIM_KEY"
# rows in statement_response.result.data_array
```

**Follow-up** — `POST /databricks-genie/genie/conversations/{conversationId}/messages`:
```bash
curl -X POST ".../databricks-genie/genie/conversations/$CONV/messages" \
  -H "Ocp-Apim-Subscription-Key: $APIM_KEY" -H "Content-Type: application/json" \
  -d '{ "content": "Now break that down by product family." }'
```

The whole flow is scripted in [`scripts/test-genie.ps1`](../scripts/test-genie.ps1).

---

## MCP server (Foundry / Copilot Studio tools)

APIM exposes both APIs as **MCP servers**, so agents call them as tools.

| MCP server | Endpoint | Tools |
|---|---|---|
| Databricks SQL | `https://ai-gateway-apim-poc-my.azure-api.net/databricks-mcp/mcp` | `query`, `tables` |
| Databricks Genie | `https://ai-gateway-apim-poc-my.azure-api.net/databricks-genie-mcp/mcp` | `ask`, `message`, `result`, `follow-up` |

- **Auth:** `Ocp-Apim-Subscription-Key` header (APIM subscription key)
- **Enable them:** run [`apim/enable-mcp.ps1`](../apim/enable-mcp.ps1) once per API,
  or use the portal (APIM → APIs → **MCP Servers** → *Expose an API as an MCP server*).
- **Inspect the generated tool schemas:**
  `python scripts/mcp_tools_probe.py <mcp-endpoint>` with `APIM_SUBSCRIPTION_KEY` set.

> Operations that take a request body are advertised with a single `body` **string**
> input. Agents must place JSON in it — `{"statement": "<SQL>"}` for `query`, and
> `{"content": "<question>"}` for `ask` and `follow-up`. A bare string makes the
> backend policy fail with HTTP 500.

**Add as a tool in Microsoft Foundry Agents:**
1. Agent → **Tools** → **Add tool** → **MCP server**.
2. URL: one of the endpoints above. Header: `Ocp-Apim-Subscription-Key = <key>`.
3. The tools appear and can be invoked by the agent.

**Add as a tool in Copilot Studio:**
1. Copilot Studio → **Tools** → **Add a tool** → **Model Context Protocol**.
2. Provide the MCP endpoint + subscription-key header.
3. Publish; the agent can now retrieve Databricks data to build PPT/diagrams.

---

## Agents API (this POC's own service)

The chat UI talks to a small FastAPI service that invokes the Foundry agents with
a managed identity. Interactive docs:
<https://databricks-agents-api-my.azurewebsites.net/docs>

Chat is asynchronous because a turn can outlive the App Service request limit:

```bash
BASE=https://databricks-agents-api-my.azurewebsites.net

# 1. start a turn -> 202 with a jobId
curl -X POST "$BASE/api/agents/databricks-genie/chat" -H "Content-Type: application/json" \
  -d '{ "message": "Total revenue in USD millions by region, as a bar chart in a PowerPoint." }'

# 2. poll until status is completed or failed
curl "$BASE/api/chat/jobs/$JOB_ID"

# 3. download any generated file cited in result.files[]
curl -o deck.pptx "$BASE/api/files/$CONTAINER_ID/$FILE_ID?filename=deck.pptx"

# Microsoft 365 declarative agent package
curl -o databricks-genie-m365-agent.zip "$BASE/api/m365/packages/databricks-genie"
```

Pass `conversationId` from a previous turn to continue the same thread.

---

## Understanding the response

The SQL API returns Statement Execution API JSON:
```json
{
  "statement_id": "01ef...",
  "status": { "state": "SUCCEEDED" },
  "manifest": { "schema": { "columns": [ { "name": "region" }, { "name": "revenue_musd" } ] } },
  "result": { "data_array": [ ["APAC","240.55"], ["North America","198.10"] ] }
}
```
- Column names → `manifest.schema.columns[].name`
- Rows → `result.data_array` (array of string arrays, column order matches schema)

Agents map `data_array` into a table/chart and then into PowerPoint.
