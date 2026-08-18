"""Thin wrapper over the Foundry Agents responses API used by the chat endpoints."""

from __future__ import annotations

import logging
import threading
from dataclasses import dataclass

from azure.ai.projects import AIProjectClient
from azure.identity import DefaultAzureCredential

from .config import get_settings

logger = logging.getLogger(__name__)

# A turn can pause several times waiting for MCP tool approval.
MAX_APPROVAL_ROUNDS = 8


@dataclass
class GeneratedFile:
    file_id: str
    container_id: str
    filename: str


@dataclass
class AgentReply:
    text: str
    conversation_id: str
    tool_calls: list[str]
    files: list[GeneratedFile]


class FoundryChat:
    """Creates agent-scoped OpenAI clients lazily and caches them per agent."""

    def __init__(self) -> None:
        # Reentrant: _agent_client holds the lock while calling _ensure_project.
        self._lock = threading.RLock()
        self._credential: DefaultAzureCredential | None = None
        self._project: AIProjectClient | None = None
        self._agent_clients: dict[str, object] = {}
        self._files_client = None

    def _ensure_project(self) -> AIProjectClient:
        if self._project is None:
            with self._lock:
                if self._project is None:
                    self._credential = DefaultAzureCredential()
                    self._project = AIProjectClient(
                        endpoint=get_settings().foundry_project_endpoint,
                        credential=self._credential,
                    )
        return self._project

    def _agent_client(self, agent_name: str):
        client = self._agent_clients.get(agent_name)
        if client is None:
            with self._lock:
                client = self._agent_clients.get(agent_name)
                if client is None:
                    client = self._ensure_project().get_openai_client(agent_name=agent_name)
                    self._agent_clients[agent_name] = client
        return client

    def files_client(self):
        """Container files live on the project surface, not the agent-scoped one."""
        if self._files_client is None:
            with self._lock:
                if self._files_client is None:
                    self._files_client = self._ensure_project().get_openai_client()
        return self._files_client

    def create_conversation(self, agent_name: str) -> str:
        return self._agent_client(agent_name).conversations.create().id

    @staticmethod
    def _collect(response, tool_calls: list[str], files: list[GeneratedFile], texts: list[str]) -> None:
        text = response.output_text
        if text:
            texts.append(text)
        for item in response.output:
            item_type = getattr(item, "type", "") or ""
            if item_type.startswith("mcp_call") or item_type.startswith("code_interpreter"):
                tool_calls.append(str(getattr(item, "name", None) or item_type))
            if item_type != "message":
                continue
            for content in getattr(item, "content", []) or []:
                for annotation in getattr(content, "annotations", []) or []:
                    if getattr(annotation, "type", None) != "container_file_citation":
                        continue
                    files.append(
                        GeneratedFile(
                            file_id=annotation.file_id,
                            container_id=annotation.container_id,
                            filename=getattr(annotation, "filename", "download"),
                        )
                    )

    def ask(self, agent_name: str, message: str, conversation_id: str | None) -> AgentReply:
        client = self._agent_client(agent_name)
        if not conversation_id:
            conversation_id = client.conversations.create().id

        tool_calls: list[str] = []
        files: list[GeneratedFile] = []
        texts: list[str] = []
        payload: object = message

        for _ in range(MAX_APPROVAL_ROUNDS):
            response = client.responses.create(conversation=conversation_id, input=payload)
            self._collect(response, tool_calls, files, texts)

            # The agents are configured with require_approval="never", but the
            # service still asks on some turns; approve and let the run finish.
            approvals = [
                item
                for item in response.output
                if getattr(item, "type", None) == "mcp_approval_request"
            ]
            if not approvals:
                break
            logger.info("Auto-approving %d MCP tool call(s)", len(approvals))
            payload = [
                {
                    "type": "mcp_approval_response",
                    "approval_request_id": item.id,
                    "approve": True,
                }
                for item in approvals
            ]
        else:
            logger.warning("Stopped after %d approval rounds", MAX_APPROVAL_ROUNDS)

        # The same file is cited once per reference; keep the first of each id.
        unique_files = list({file.file_id: file for file in files}.values())
        return AgentReply(
            text="\n\n".join(texts).strip(),
            conversation_id=conversation_id,
            tool_calls=tool_calls,
            files=unique_files,
        )

    def download_file(self, container_id: str, file_id: str) -> bytes:
        content = self.files_client().containers.files.content.retrieve(
            file_id=file_id, container_id=container_id
        )
        return content.read()


foundry_chat = FoundryChat()
