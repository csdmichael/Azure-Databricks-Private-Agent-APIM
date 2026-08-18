"""Creates or updates the Databricks SQL Foundry prompt agent.

The agent queries the private Databricks warehouse through the APIM MCP server
and turns the results into charts and PowerPoint decks with Code Interpreter.
"""

import argparse
import sys
from pathlib import Path

from azure.ai.projects import AIProjectClient
from azure.ai.projects.models import (
    AutoCodeInterpreterToolParam,
    CodeInterpreterTool,
    MCPTool,
    PromptAgentDefinition,
)
from azure.identity import DefaultAzureCredential

from common import put_mcp_connection, required_env, run_pptx_smoke_test

INSTRUCTIONS = """You are a semiconductor business analytics agent.
Use the Databricks MCP tools for every numeric or factual claim about company data.
Use only read-only SELECT or SHOW statements and only the connected sample schema
databricks_ws_ai_poc.arrow_semiconductor.

The MCP `query` tool takes a single string argument named `body`. Always set `body`
to a compact JSON object string of the exact form {"statement": "<SQL>"} where <SQL>
is one read-only statement. Never put bare SQL in `body`; it must be JSON.

Use Code Interpreter to create charts and PowerPoint presentations when requested.
For PowerPoint requests, generate a valid .pptx file with python-pptx, cite the
generated file in the response, include a source-data slide, and do not invent or
extrapolate missing values. State the source table, filters, units, and date range.
"""


SMOKE_TEST_PROMPT = (
    "Use the Databricks MCP query tool to calculate total revenue in USD "
    "millions by region from product_sales. Then use Code Interpreter to "
    "create a concise PowerPoint named databricks-revenue-smoke-test.pptx "
    "with a title slide, a labeled regional revenue chart, and a source-data "
    "slide. Return the generated .pptx file."
)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Create or update the Databricks MCP Foundry prompt agent."
    )
    parser.add_argument("--skip-test", action="store_true")
    parser.add_argument("--output-dir", default="artifacts")
    args = parser.parse_args()

    mcp_url = required_env("MCP_SERVER_URL")
    credential = DefaultAzureCredential()
    connection_name = put_mcp_connection(
        credential, required_env("MCP_CONNECTION_NAME"), mcp_url
    )
    project = AIProjectClient(
        endpoint=required_env("FOUNDRY_PROJECT_ENDPOINT"),
        credential=credential,
    )

    agent_name = required_env("FOUNDRY_AGENT_NAME")
    agent = project.agents.create_version(
        agent_name=agent_name,
        definition=PromptAgentDefinition(
            model=required_env("FOUNDRY_MODEL_DEPLOYMENT_NAME"),
            instructions=INSTRUCTIONS,
            tools=[
                MCPTool(
                    server_label="databricks",
                    server_url=mcp_url,
                    project_connection_id=connection_name,
                    allowed_tools=["query", "tables"],
                    require_approval="never",
                ),
                CodeInterpreterTool(
                    container=AutoCodeInterpreterToolParam(file_ids=[])
                ),
            ],
        ),
        description=(
            "Queries private Azure Databricks data through APIM MCP and creates "
            "charts and PowerPoint presentations with Code Interpreter."
        ),
    )
    print(f"Agent ready: {agent.name} version {agent.version}")

    if not args.skip_test:
        run_pptx_smoke_test(project, agent.name, SMOKE_TEST_PROMPT, Path(args.output_dir))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as error:
        import traceback

        traceback.print_exc()
        print(f"ERROR: {error}", file=sys.stderr)
        sys.exit(1)