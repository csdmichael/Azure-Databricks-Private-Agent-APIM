"""Creates or updates the Databricks Genie Foundry prompt agent.

The agent answers business questions in natural language by driving the AI/BI
Genie conversation API that APIM exposes as an MCP server, then turns the
grounded results into charts and PowerPoint decks with Code Interpreter.
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

INSTRUCTIONS = """You are a semiconductor business analytics agent for an Arrow-style
chip manufacturer. You answer questions using Databricks AI/BI Genie, which is
curated over the schema databricks_ws_ai_poc.arrow_semiconductor.

Genie is asynchronous. Follow this loop exactly for every business question:

1. Call the `ask` tool. Its only argument is `body`, a string. Set `body` to a
   compact JSON object string of the exact form {"content": "<question>"}.
   Never put a bare question in `body`; it must be JSON. The response contains
   `conversation_id` and `message_id`.
2. Call the `message` tool with `conversationId` and `messageId`. Repeat until
   `status` is COMPLETED. If `status` is FAILED, CANCELLED or
   QUERY_RESULT_EXPIRED, stop and report the failure. Do not poll more than
   15 times.
3. Read the natural-language answer from `attachments[].text.content` and the
   generated SQL from `attachments[].query.query`.
4. When an attachment contains a `query`, call the `result` tool with the same
   ids to get the rows. Column names are at
   `statement_response.manifest.schema.columns[].name` and rows at
   `statement_response.result.data_array` (arrays of strings, in column order).
5. For a follow-up question in the same thread, call `follow-up` with
   `conversationId` and `body` set to {"content": "<question>"}.

Grounding rules:
- Use Genie for every numeric or factual claim about company data. Never invent,
  estimate or extrapolate values.
- Always state the source table(s), filters, units and date range you used, and
  include the Genie-generated SQL when you present numbers.
- If Genie cannot answer or the data is unavailable, say so plainly.

Use Code Interpreter to build charts and PowerPoint files from the returned rows.
For PowerPoint requests, generate a valid .pptx with python-pptx, cite the
generated file in the response, and include a source-data slide listing the
tables, SQL and row values behind every chart. The sandbox has no internet
access, so build everything from the tool results in the conversation.
"""

SMOKE_TEST_PROMPT = (
    "Ask Genie for total revenue in USD millions by region across the whole "
    "dataset, poll until the message completes, and fetch the query result "
    "rows. Then use Code Interpreter to create a PowerPoint named "
    "genie-revenue-smoke-test.pptx with a title slide, a labeled regional "
    "revenue bar chart, and a source-data slide showing the Genie SQL and the "
    "returned rows. Return the generated .pptx file."
)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Create or update the Databricks Genie Foundry prompt agent."
    )
    parser.add_argument("--skip-test", action="store_true")
    parser.add_argument("--output-dir", default="artifacts")
    args = parser.parse_args()

    mcp_url = required_env("GENIE_MCP_SERVER_URL")
    credential = DefaultAzureCredential()
    connection_name = put_mcp_connection(
        credential, required_env("GENIE_MCP_CONNECTION_NAME"), mcp_url
    )
    project = AIProjectClient(
        endpoint=required_env("FOUNDRY_PROJECT_ENDPOINT"), credential=credential
    )

    agent_name = required_env("FOUNDRY_GENIE_AGENT_NAME")
    agent = project.agents.create_version(
        agent_name=agent_name,
        definition=PromptAgentDefinition(
            model=required_env("FOUNDRY_MODEL_DEPLOYMENT_NAME"),
            instructions=INSTRUCTIONS,
            tools=[
                MCPTool(
                    server_label="databricks_genie",
                    server_url=mcp_url,
                    project_connection_id=connection_name,
                    allowed_tools=["ask", "message", "result", "follow-up"],
                    require_approval="never",
                ),
                CodeInterpreterTool(container=AutoCodeInterpreterToolParam(file_ids=[])),
            ],
        ),
        description=(
            "Answers natural-language questions over private Azure Databricks data "
            "using AI/BI Genie through APIM, and builds charts and PowerPoint decks."
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
