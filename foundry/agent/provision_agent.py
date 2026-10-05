"""Create or update the Teams-facing Foundry prompt agent with delegated MCP auth."""

from __future__ import annotations

import argparse
import os
import sys

from azure.ai.projects import AIProjectClient
from azure.ai.projects.models import MCPTool, PromptAgentDefinition, StructuredInputDefinition
from azure.identity import DefaultAzureCredential


def required(name: str) -> str:
    value = os.getenv(name)
    if not value:
        raise RuntimeError(f"Required environment variable {name} is not set")
    return value


def instructions() -> str:
    return """You are an executive semiconductor sales and operations analyst.
Use the Databricks Genie MCP tools for every factual or numeric claim about company data.
The MCP service enforces the signed-in user's Databricks permissions. Never claim that
the user can see data that the tool did not return. Never invent, estimate, or extrapolate.

For a new question, start a Genie conversation, poll until it completes, and retrieve
the result. Reuse the returned conversation identifier for follow-up questions.
Summarize results concisely, include units and filters, and explain permission errors
without suggesting that the user bypass access controls.

When asked what you can do, offer these examples:
- 2025 revenue by region
- Compare yield by fab and process node
- Show the monthly revenue trend for 2025
- Which product families drive margin?
"""


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--test-token", help="Optional delegated token for a live smoke test.")
    parser.add_argument("--test-prompt", default="What can you help me analyze?")
    args = parser.parse_args()

    project = AIProjectClient(
        endpoint=required("FOUNDRY_PROJECT_ENDPOINT"),
        credential=DefaultAzureCredential(),
    )
    agent = project.agents.create_version(
        agent_name=required("FOUNDRY_AGENT_NAME"),
        definition=PromptAgentDefinition(
            model=required("FOUNDRY_MODEL_DEPLOYMENT_NAME"),
            instructions=instructions(),
            reasoning={"effort": "low"},
            structured_inputs={
                "oboToken": StructuredInputDefinition(
                    description="Short-lived delegated Entra token for the signed-in Teams user.",
                    required=True,
                    schema={"type": "string"},
                )
            },
            tools=[
                MCPTool(
                    server_label="databricks-genie-obo",
                    server_url=required("MCP_SERVER_URL"),
                    headers={"Authorization": "Bearer {{oboToken}}"},
                    allowed_tools=[],
                    require_approval="never",
                )
            ],
        ),
        description="Teams-facing Databricks Genie agent with per-user OBO authorization.",
    )
    print(f"Agent ready: {agent.name} version {agent.version}")

    portal_url = os.getenv("FOUNDRY_AGENT_PORTAL_URL")
    if portal_url:
        print(f"Published agent URL: {portal_url}")

    if args.test_token:
        openai = project.get_openai_client(agent_name=agent.name)
        conversation = openai.conversations.create()
        try:
            response = openai.responses.create(
                conversation=conversation.id,
                input=args.test_prompt,
                extra_body={"structured_inputs": {"oboToken": args.test_token}},
            )
            if not response.output_text:
                raise RuntimeError("Smoke test returned no text.")
            print(response.output_text)
        finally:
            openai.conversations.delete(conversation.id)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as error:
        print(f"ERROR: {error}", file=sys.stderr)
        raise
