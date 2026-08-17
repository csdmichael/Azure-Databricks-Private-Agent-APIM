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

Natural-language questions answered by AI/BI Genie over the same data.

**Ask** — `POST /databricks-genie/genie/ask`:
```bash
curl -X POST "https://ai-gateway-apim-poc-my.azure-api.net/databricks-genie/genie/ask" \
  -H "Ocp-Apim-Subscription-Key: $APIM_KEY" -H "Content-Type: application/json" \
  -d '{ "content": "What were the top 3 regions by revenue last quarter?" }'
# -> returns conversation_id + message_id
```

**Get the result** — `GET /databricks-genie/genie/conversations/{conversationId}/messages/{messageId}/result`:
```bash
curl "https://ai-gateway-apim-poc-my.azure-api.net/databricks-genie/genie/conversations/$CONV/messages/$MSG/result" \
  -H "Ocp-Apim-Subscription-Key: $APIM_KEY"
```

**Follow-up** — `POST /databricks-genie/genie/conversations/{conversationId}/messages`:
```bash
curl -X POST ".../databricks-genie/genie/conversations/$CONV/messages" \
  -H "Ocp-Apim-Subscription-Key: $APIM_KEY" -H "Content-Type: application/json" \
  -d '{ "content": "Now break that down by product family." }'
```

---

## MCP server (Foundry / Copilot Studio tools)

APIM exposes the Databricks operations as an **MCP server** (preview), so agents
can call them as tools.

- **MCP endpoint:** `https://ai-gateway-apim-poc-my.azure-api.net/databricks-mcp/mcp`
- **Auth:** `Ocp-Apim-Subscription-Key` header (APIM subscription key)
- **Enable it:** run [`apim/enable-mcp.ps1`](../apim/enable-mcp.ps1) or use the portal
  (APIM → APIs → **MCP Servers** → *Expose an API as an MCP server* → select
  `Databricks SQL` → operations `query`, `tables`).

**Add as a tool in Microsoft Foundry Agents:**
1. Agent → **Tools** → **Add tool** → **MCP server**.
2. URL: the MCP endpoint above. Header: `Ocp-Apim-Subscription-Key = <key>`.
3. The `query` and `tables` tools appear and can be invoked by the agent.

**Add as a tool in Copilot Studio:**
1. Copilot Studio → **Tools** → **Add a tool** → **Model Context Protocol**.
2. Provide the MCP endpoint + subscription-key header.
3. Publish; the agent can now retrieve Databricks data to build PPT/diagrams.

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
