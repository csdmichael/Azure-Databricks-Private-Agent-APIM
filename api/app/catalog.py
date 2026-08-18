"""The catalog of Foundry agents this POC exposes to the UI and to Microsoft 365.

One entry drives everything: the chat tab, the agent icon, and the declarative
agent package that can be uploaded to the Microsoft 365 developer portal.
"""

from dataclasses import dataclass, field
from uuid import NAMESPACE_URL, uuid5

# Stable per-agent Teams app ids, derived so they never change between builds.
_APP_ID_NAMESPACE = "https://github.com/csdmichael/Azure-Databricks-Private-Agent-APIM/m365/"


@dataclass(frozen=True)
class AgentDefinition:
    id: str
    foundry_agent_name: str
    display_name: str
    short_name: str
    tagline: str
    description: str
    accent_color: str
    apim_api_path: str
    conversation_starters: list[dict[str, str]]
    tools: list[str]
    m365_instructions: str
    plugin_name: str
    plugin_description_human: str
    plugin_description_model: str
    openapi_operations: list[str] = field(default_factory=list)

    @property
    def teams_app_id(self) -> str:
        return str(uuid5(NAMESPACE_URL, _APP_ID_NAMESPACE + self.id))


DATABRICKS_SQL_AGENT = AgentDefinition(
    id="databricks-sql",
    foundry_agent_name="databricks-agent-mcp",
    display_name="Databricks SQL Agent",
    short_name="Databricks SQL",
    tagline="Deterministic SQL over the private warehouse",
    description=(
        "Runs read-only SQL against the private Azure Databricks warehouse through "
        "API Management and builds charts and PowerPoint decks from the results."
    ),
    accent_color="#FF3621",
    apim_api_path="databricks",
    conversation_starters=[
        {
            "title": "Revenue by region",
            "text": "Show total revenue in USD millions by region and build a labeled bar chart.",
        },
        {
            "title": "Yield trend",
            "text": "Plot monthly average wafer yield percent by process node as a line chart.",
        },
        {
            "title": "Defect Pareto",
            "text": "Build a Pareto chart of defect counts by category and mark the 80 percent line.",
        },
        {
            "title": "Executive deck",
            "text": "Create a one-slide executive PowerPoint with revenue, yield and supplier risk KPIs.",
        },
    ],
    tools=["Databricks MCP (query, tables)", "Code Interpreter"],
    m365_instructions=(
        "You are a semiconductor business analytics agent for an Arrow-style chip "
        "manufacturer. Use the Databricks actions for every numeric or factual claim "
        "about company data, and only issue read-only SELECT or SHOW statements against "
        "the schema databricks_ws_ai_poc.arrow_semiconductor.\n\n"
        "Tables available: product_sales (revenue, units, gross margin by region, fiscal "
        "quarter, product family), fab_production (wafer starts, good dies, yield by fab "
        "and process node), wafer_yield (actual versus target yield by month and node), "
        "defect_analysis (defect counts by category and severity), inventory (on-hand "
        "units, days of supply, stock status) and supply_chain (supplier lead time, "
        "on-time delivery, quality score, risk level).\n\n"
        "Always state the source table, filters, units and date range behind every number. "
        "Never invent, estimate or extrapolate values. When asked for a chart or a "
        "presentation, return the supporting result table alongside it."
    ),
    plugin_name="Databricks SQL",
    plugin_description_human="Query the private Azure Databricks semiconductor dataset.",
    plugin_description_model=(
        "Runs read-only SQL statements against the Azure Databricks warehouse and lists "
        "the available tables in databricks_ws_ai_poc.arrow_semiconductor."
    ),
    openapi_operations=["runQuery", "listTables"],
)

DATABRICKS_GENIE_AGENT = AgentDefinition(
    id="databricks-genie",
    foundry_agent_name="databricks-genie-agent",
    display_name="Databricks Genie Agent",
    short_name="Genie",
    tagline="Natural-language analytics with AI/BI Genie",
    description=(
        "Asks Databricks AI/BI Genie business questions in plain language, waits for the "
        "curated answer and generated SQL, then turns the grounded rows into charts and "
        "PowerPoint decks."
    ),
    accent_color="#0089D6",
    apim_api_path="databricks-genie",
    conversation_starters=[
        {
            "title": "Ask Genie",
            "text": "What were the top regions by revenue, and how does that compare across product families?",
        },
        {
            "title": "Yield question",
            "text": "Which process node has the biggest gap between actual and target yield?",
        },
        {
            "title": "Supplier risk",
            "text": "Which suppliers are highest risk, and what is driving that?",
        },
        {
            "title": "Genie deck",
            "text": "Ask Genie for quarterly revenue by region and build a PowerPoint with the Genie SQL on a source slide.",
        },
    ],
    tools=["Databricks Genie MCP (ask, message, result, follow-up)", "Code Interpreter"],
    m365_instructions=(
        "You are a semiconductor business analytics agent that answers questions using "
        "Databricks AI/BI Genie, curated over the schema "
        "databricks_ws_ai_poc.arrow_semiconductor.\n\n"
        "Genie is asynchronous, so always follow this loop: call the ask action with the "
        "user's question, then poll the message action with the returned conversationId and "
        "messageId until status is COMPLETED. Read the answer from attachments[].text.content "
        "and the generated SQL from attachments[].query.query. When an attachment contains a "
        "query, call the result action with the same ids to get the rows; column names are in "
        "statement_response.manifest.schema.columns[].name and rows in "
        "statement_response.result.data_array. Use the follow-up action to continue an "
        "existing conversation.\n\n"
        "Use Genie for every numeric or factual claim. Never invent, estimate or extrapolate "
        "values. Always show the Genie-generated SQL and the source rows when you present "
        "numbers or charts."
    ),
    plugin_name="Databricks Genie",
    plugin_description_human="Ask the private Databricks dataset questions in natural language.",
    plugin_description_model=(
        "Starts and continues Databricks AI/BI Genie conversations over the semiconductor "
        "dataset, polls message status, and retrieves the generated SQL result rows."
    ),
    openapi_operations=["askGenie", "getGenieMessage", "getGenieResult", "askGenieFollowUp"],
)

AGENTS: list[AgentDefinition] = [DATABRICKS_SQL_AGENT, DATABRICKS_GENIE_AGENT]
AGENTS_BY_ID: dict[str, AgentDefinition] = {agent.id: agent for agent in AGENTS}
