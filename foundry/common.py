"""Shared helpers for provisioning Foundry prompt agents in this POC.

Both agents (Databricks SQL/MCP and Databricks Genie) upsert an APIM-backed MCP
project connection, create an agent version, and run a PowerPoint smoke test.
"""

import json
import os
import time
import urllib.error
import urllib.request
import zipfile
from pathlib import Path

from azure.core.credentials import AccessToken
from azure.identity import DefaultAzureCredential


def required_env(name: str) -> str:
    value = os.getenv(name)
    if not value:
        raise RuntimeError(f"Required environment variable {name} is not set")
    return value


def put_mcp_connection(
    credential: DefaultAzureCredential, connection_name: str, mcp_url: str
) -> str:
    """Idempotently upserts a CustomKeys project connection holding the APIM key."""
    subscription_id = required_env("AZURE_SUBSCRIPTION_ID")
    resource_group = required_env("AZURE_RESOURCE_GROUP")
    account_name = required_env("FOUNDRY_ACCOUNT_NAME")
    project_name = required_env("FOUNDRY_PROJECT_NAME")
    apim_key = required_env("APIM_SUBSCRIPTION_KEY")

    resource_id = (
        f"/subscriptions/{subscription_id}/resourceGroups/{resource_group}"
        f"/providers/Microsoft.CognitiveServices/accounts/{account_name}"
        f"/projects/{project_name}/connections/{connection_name}"
    )
    url = f"https://management.azure.com{resource_id}?api-version=2025-06-01"
    payload = {
        "properties": {
            "category": "CustomKeys",
            "target": mcp_url,
            "authType": "CustomKeys",
            "credentials": {"keys": {"Ocp-Apim-Subscription-Key": apim_key}},
        }
    }
    token: AccessToken = credential.get_token("https://management.azure.com/.default")
    request = urllib.request.Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "Authorization": f"Bearer {token.token}",
            "Content-Type": "application/json",
        },
        method="PUT",
    )
    try:
        with urllib.request.urlopen(request) as response:
            if response.status not in (200, 201):
                raise RuntimeError(f"Connection upsert returned HTTP {response.status}")
    except urllib.error.HTTPError as error:
        detail = error.read().decode("utf-8", errors="replace")
        raise RuntimeError(
            f"Unable to upsert MCP project connection: HTTP {error.code}: {detail}"
        ) from error
    return connection_name


def response_annotations(response):
    for item in response.output:
        if getattr(item, "type", None) != "message":
            continue
        for content in getattr(item, "content", []) or []:
            for annotation in getattr(content, "annotations", []) or []:
                yield annotation


def validate_pptx(path: Path) -> None:
    if path.suffix.lower() != ".pptx":
        raise RuntimeError(f"Generated artifact is not a .pptx file: {path.name}")
    if path.stat().st_size < 1024:
        raise RuntimeError(
            f"Generated PowerPoint is unexpectedly small: {path.stat().st_size} bytes"
        )
    if not zipfile.is_zipfile(path):
        raise RuntimeError("Generated PowerPoint is not a valid Office Open XML package")
    with zipfile.ZipFile(path) as archive:
        if "ppt/presentation.xml" not in archive.namelist():
            raise RuntimeError("Generated package does not contain ppt/presentation.xml")


def invoke_agent(openai, prompt: str, attempts: int = 6):
    # A freshly created agent version can 404 briefly until it propagates.
    last_error = None
    for attempt in range(attempts):
        conversation = None
        try:
            conversation = openai.conversations.create()
            response = openai.responses.create(conversation=conversation.id, input=prompt)
            return conversation, response
        except Exception as error:
            if getattr(error, "status_code", None) != 404 and "404" not in str(error):
                raise
            last_error = error
            if conversation is not None:
                try:
                    openai.conversations.delete(conversation.id)
                except Exception:
                    pass
            time.sleep(5 * (attempt + 1))
    raise last_error


def run_pptx_smoke_test(project, agent_name: str, prompt: str, output_dir: Path) -> Path:
    """Invokes the agent, asserts it used an MCP tool, and saves the cited .pptx."""
    openai = project.get_openai_client(agent_name=agent_name)
    # Container files live on the project OpenAI surface, not the agent-scoped one.
    files_client = project.get_openai_client()
    conversation, response = invoke_agent(openai, prompt)
    try:
        output_types = {getattr(item, "type", "") for item in response.output}
        if not any(item_type.startswith("mcp") for item_type in output_types):
            raise RuntimeError(
                f"Smoke test did not call an MCP tool; response types: {sorted(output_types)}"
            )

        pptx_annotation = next(
            (
                annotation
                for annotation in response_annotations(response)
                if getattr(annotation, "type", None) == "container_file_citation"
                and getattr(annotation, "filename", "").lower().endswith(".pptx")
            ),
            None,
        )
        if pptx_annotation is None:
            raise RuntimeError(
                "Smoke test completed without a cited .pptx file. "
                f"Agent response: {response.output_text}"
            )

        output_dir.mkdir(parents=True, exist_ok=True)
        output_path = output_dir / Path(pptx_annotation.filename).name
        content = files_client.containers.files.content.retrieve(
            file_id=pptx_annotation.file_id,
            container_id=pptx_annotation.container_id,
        )
        output_path.write_bytes(content.read())
        validate_pptx(output_path)
        print(f"Smoke test passed; PowerPoint downloaded to {output_path}")
        return output_path
    finally:
        openai.conversations.delete(conversation.id)
