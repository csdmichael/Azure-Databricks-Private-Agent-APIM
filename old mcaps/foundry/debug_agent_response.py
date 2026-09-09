"""Prints the raw shape of one agent response so the API can map it correctly."""

import json
import os
import sys

from azure.ai.projects import AIProjectClient
from azure.identity import DefaultAzureCredential

endpoint = os.getenv(
    "FOUNDRY_PROJECT_ENDPOINT",
    "https://002-ai-poc-private.services.ai.azure.com/api/projects/proj-default",
)
agent_name = sys.argv[1] if len(sys.argv) > 1 else "databricks-agent-mcp"
prompt = (
    sys.argv[2]
    if len(sys.argv) > 2
    else "Use the query tool to get total revenue in USD millions by region from product_sales, then summarize it in two sentences."
)

project = AIProjectClient(endpoint=endpoint, credential=DefaultAzureCredential())
client = project.get_openai_client(agent_name=agent_name)
conversation = client.conversations.create()
try:
    response = client.responses.create(conversation=conversation.id, input=prompt)
    print("status          :", getattr(response, "status", None))
    print("incomplete      :", getattr(response, "incomplete_details", None))
    print("error           :", getattr(response, "error", None))
    print("output_text len :", len(response.output_text or ""))
    print("output items    :")
    for item in response.output:
        item_type = getattr(item, "type", None)
        print("  -", item_type, "| name:", getattr(item, "name", None), "| status:", getattr(item, "status", None))
        if item_type == "message":
            for content in getattr(item, "content", []) or []:
                print("      content type:", getattr(content, "type", None))
                text = getattr(content, "text", None)
                if text:
                    print("      text[:300]:", str(text)[:300])
                for annotation in getattr(content, "annotations", []) or []:
                    print("      annotation:", json.dumps(annotation.as_dict() if hasattr(annotation, "as_dict") else str(annotation))[:300])
finally:
    client.conversations.delete(conversation.id)
