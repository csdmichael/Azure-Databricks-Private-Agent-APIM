"""Builds Microsoft 365 declarative agent packages (.zip) for each Foundry agent.

Each package contains the Teams app manifest, the declarative agent manifest, an
API plugin manifest, the OpenAPI description of the APIM operations the agent
uses, and the agent's own colour and outline icons.
"""

from __future__ import annotations

import io
import json
import zipfile
from pathlib import Path

from .catalog import DATABRICKS_GENIE_AGENT, DATABRICKS_SQL_AGENT, AgentDefinition
from .config import get_settings

ASSETS_DIR = Path(__file__).parent / "m365_assets"

TEAMS_MANIFEST_SCHEMA = (
    "https://developer.microsoft.com/en-us/json-schemas/teams/v1.29/MicrosoftTeams.schema.json"
)
TEAMS_MANIFEST_VERSION = "1.29"
DECLARATIVE_AGENT_SCHEMA = (
    "https://developer.microsoft.com/json-schemas/copilot/declarative-agent/v1.8/schema.json"
)
DECLARATIVE_AGENT_VERSION = "v1.8"
PLUGIN_SCHEMA = "https://developer.microsoft.com/json-schemas/copilot/plugin/v2.4/schema.json"
PLUGIN_SCHEMA_VERSION = "v2.4"

_SECURITY_SCHEMES = {
    "apiKeyHeader": {
        "type": "apiKey",
        "name": "Ocp-Apim-Subscription-Key",
        "in": "header",
        "description": "API Management subscription key for the Databricks Agents product.",
    }
}

_STATEMENT_RESPONSE_SCHEMA = {
    "type": "object",
    "properties": {
        "statement_id": {"type": "string"},
        "status": {
            "type": "object",
            "properties": {"state": {"type": "string"}},
        },
        "manifest": {
            "type": "object",
            "description": "Result metadata; column names are under schema.columns[].name.",
            "properties": {
                "schema": {
                    "type": "object",
                    "properties": {
                        "columns": {
                            "type": "array",
                            "items": {
                                "type": "object",
                                "properties": {
                                    "name": {"type": "string"},
                                    "type_text": {"type": "string"},
                                },
                            },
                        }
                    },
                }
            },
        },
        "result": {
            "type": "object",
            "properties": {
                "data_array": {
                    "type": "array",
                    "description": "Rows as arrays of strings, in column order.",
                    "items": {"type": "array", "items": {"type": "string"}},
                }
            },
        },
    },
}


def _databricks_openapi(base_url: str) -> dict:
    return {
        "openapi": "3.0.3",
        "info": {
            "title": "Databricks SQL",
            "description": (
                "Read-only access to the private Azure Databricks warehouse "
                "(databricks_ws_ai_poc.arrow_semiconductor) through Azure API Management."
            ),
            "version": "1.0.0",
        },
        "servers": [{"url": f"{base_url}/databricks", "description": "APIM gateway"}],
        "security": [{"apiKeyHeader": []}],
        "components": {"securitySchemes": _SECURITY_SCHEMES},
        "paths": {
            "/query": {
                "post": {
                    "operationId": "runQuery",
                    "summary": "Run a read-only SQL statement",
                    "description": (
                        "Executes one read-only SELECT or SHOW statement against the "
                        "semiconductor sample schema and returns the rows."
                    ),
                    "requestBody": {
                        "required": True,
                        "content": {
                            "application/json": {
                                "schema": {
                                    "type": "object",
                                    "required": ["statement"],
                                    "properties": {
                                        "statement": {
                                            "type": "string",
                                            "description": "A single read-only SQL statement.",
                                        }
                                    },
                                },
                                "example": {
                                    "statement": (
                                        "SELECT region, ROUND(SUM(revenue_usd)/1e6,2) AS revenue_musd "
                                        "FROM databricks_ws_ai_poc.arrow_semiconductor.product_sales "
                                        "GROUP BY region ORDER BY revenue_musd DESC"
                                    )
                                },
                            }
                        },
                    },
                    "responses": {
                        "200": {
                            "description": "Query result",
                            "content": {
                                "application/json": {"schema": _STATEMENT_RESPONSE_SCHEMA}
                            },
                        }
                    },
                }
            },
            "/tables": {
                "get": {
                    "operationId": "listTables",
                    "summary": "List the sample tables",
                    "description": (
                        "Lists the tables available in "
                        "databricks_ws_ai_poc.arrow_semiconductor."
                    ),
                    "responses": {
                        "200": {
                            "description": "Table list",
                            "content": {
                                "application/json": {"schema": _STATEMENT_RESPONSE_SCHEMA}
                            },
                        }
                    },
                }
            },
        },
    }


_GENIE_MESSAGE_SCHEMA = {
    "type": "object",
    "properties": {
        "id": {"type": "string"},
        "conversation_id": {"type": "string"},
        "status": {
            "type": "string",
            "description": "Poll until this is COMPLETED.",
        },
        "attachments": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "attachment_id": {"type": "string"},
                    "text": {
                        "type": "object",
                        "properties": {"content": {"type": "string"}},
                    },
                    "query": {
                        "type": "object",
                        "properties": {
                            "query": {"type": "string"},
                            "description": {"type": "string"},
                        },
                    },
                },
            },
        },
    },
}

_CONVERSATION_PARAM = {
    "name": "conversationId",
    "in": "path",
    "required": True,
    "description": "Conversation id returned by askGenie.",
    "schema": {"type": "string"},
}
_MESSAGE_PARAM = {
    "name": "messageId",
    "in": "path",
    "required": True,
    "description": "Message id returned by askGenie.",
    "schema": {"type": "string"},
}
_ASK_BODY = {
    "required": True,
    "content": {
        "application/json": {
            "schema": {
                "type": "object",
                "required": ["content"],
                "properties": {
                    "content": {
                        "type": "string",
                        "description": "The business question, in natural language.",
                    }
                },
            },
            "example": {"content": "What was total revenue by region last quarter?"},
        }
    },
}


def _genie_openapi(base_url: str) -> dict:
    return {
        "openapi": "3.0.3",
        "info": {
            "title": "Databricks Genie",
            "description": (
                "Natural-language analytics over the private Azure Databricks "
                "semiconductor dataset using AI/BI Genie, through Azure API Management. "
                "Genie is asynchronous: call askGenie, poll getGenieMessage until status "
                "is COMPLETED, then call getGenieResult for the rows."
            ),
            "version": "1.0.0",
        },
        "servers": [{"url": f"{base_url}/databricks-genie", "description": "APIM gateway"}],
        "security": [{"apiKeyHeader": []}],
        "components": {"securitySchemes": _SECURITY_SCHEMES},
        "paths": {
            "/genie/ask": {
                "post": {
                    "operationId": "askGenie",
                    "summary": "Start a Genie conversation",
                    "description": "Asks Genie a question and returns conversation and message ids.",
                    "requestBody": _ASK_BODY,
                    "responses": {
                        "200": {
                            "description": "Conversation and message ids",
                            "content": {
                                "application/json": {
                                    "schema": {
                                        "type": "object",
                                        "properties": {
                                            "conversation_id": {"type": "string"},
                                            "message_id": {"type": "string"},
                                        },
                                    }
                                }
                            },
                        }
                    },
                }
            },
            "/genie/conversations/{conversationId}/messages/{messageId}": {
                "get": {
                    "operationId": "getGenieMessage",
                    "summary": "Get Genie message status",
                    "description": (
                        "Returns the message status and, once COMPLETED, the natural-language "
                        "answer and the generated SQL in attachments."
                    ),
                    "parameters": [_CONVERSATION_PARAM, _MESSAGE_PARAM],
                    "responses": {
                        "200": {
                            "description": "Message status and attachments",
                            "content": {"application/json": {"schema": _GENIE_MESSAGE_SCHEMA}},
                        }
                    },
                }
            },
            "/genie/conversations/{conversationId}/messages/{messageId}/result": {
                "get": {
                    "operationId": "getGenieResult",
                    "summary": "Get Genie query result rows",
                    "description": "Returns the rows produced by the SQL Genie generated.",
                    "parameters": [_CONVERSATION_PARAM, _MESSAGE_PARAM],
                    "responses": {
                        "200": {
                            "description": "Query result",
                            "content": {
                                "application/json": {
                                    "schema": {
                                        "type": "object",
                                        "properties": {
                                            "statement_response": _STATEMENT_RESPONSE_SCHEMA
                                        },
                                    }
                                }
                            },
                        }
                    },
                }
            },
            "/genie/conversations/{conversationId}/messages": {
                "post": {
                    "operationId": "askGenieFollowUp",
                    "summary": "Ask a follow-up question",
                    "description": "Continues an existing Genie conversation.",
                    "parameters": [_CONVERSATION_PARAM],
                    "requestBody": _ASK_BODY,
                    "responses": {
                        "200": {
                            "description": "Message",
                            "content": {"application/json": {"schema": _GENIE_MESSAGE_SCHEMA}},
                        }
                    },
                }
            },
        },
    }


_OPENAPI_BUILDERS = {
    DATABRICKS_SQL_AGENT.id: _databricks_openapi,
    DATABRICKS_GENIE_AGENT.id: _genie_openapi,
}

_FUNCTION_DESCRIPTIONS = {
    "runQuery": "Run one read-only SQL statement against the semiconductor sample schema.",
    "listTables": "List the tables available in databricks_ws_ai_poc.arrow_semiconductor.",
    "askGenie": "Ask Databricks Genie a business question and get conversation and message ids.",
    "getGenieMessage": "Poll a Genie message until it is COMPLETED and read the answer and SQL.",
    "getGenieResult": "Fetch the result rows for a completed Genie message.",
    "askGenieFollowUp": "Ask a follow-up question in an existing Genie conversation.",
}


def build_openapi(agent: AgentDefinition) -> dict:
    return _OPENAPI_BUILDERS[agent.id](get_settings().apim_base_url)


def _plugin_manifest(agent: AgentDefinition, api_key_reference_id: str | None) -> dict:
    auth: dict[str, str] = (
        {"type": "ApiKeyPluginVault", "reference_id": api_key_reference_id}
        if api_key_reference_id
        else {"type": "None"}
    )
    return {
        "$schema": PLUGIN_SCHEMA,
        "schema_version": PLUGIN_SCHEMA_VERSION,
        "name_for_human": agent.plugin_name,
        "description_for_human": agent.plugin_description_human,
        "description_for_model": agent.plugin_description_model,
        "namespace": agent.id.replace("-", ""),
        "functions": [
            {"name": name, "description": _FUNCTION_DESCRIPTIONS[name]}
            for name in agent.openapi_operations
        ],
        "runtimes": [
            {
                "type": "OpenApi",
                "auth": auth,
                # progress_style is unique to the OpenAPI spec variant, which keeps the
                # schema's `oneOf` between OpenAPI and MCP specs unambiguous.
                "spec": {
                    "url": "apiSpecificationFile/openapi.json",
                    "progress_style": "ShowUsageWithInput",
                },
                "run_for_functions": list(agent.openapi_operations),
            }
        ],
    }


def _declarative_agent(agent: AgentDefinition) -> dict:
    return {
        "$schema": DECLARATIVE_AGENT_SCHEMA,
        "version": DECLARATIVE_AGENT_VERSION,
        "name": agent.display_name[:100],
        "description": agent.description[:1000],
        "instructions": agent.m365_instructions,
        "conversation_starters": [
            {"title": starter["title"], "text": starter["text"]}
            for starter in agent.conversation_starters
        ],
        "actions": [{"id": f"{agent.id}-plugin", "file": "ai-plugin.json"}],
    }


def _teams_manifest(agent: AgentDefinition) -> dict:
    settings = get_settings()
    apim_host = settings.apim_base_url.replace("https://", "").replace("http://", "")
    return {
        "$schema": TEAMS_MANIFEST_SCHEMA,
        "manifestVersion": TEAMS_MANIFEST_VERSION,
        "version": "1.0.0",
        "id": agent.teams_app_id,
        "developer": {
            "name": "Michael Yaacoub",
            "websiteUrl": settings.github_repo_url,
            "privacyUrl": f"{settings.github_repo_url}/blob/main/README.md",
            "termsOfUseUrl": f"{settings.github_repo_url}/blob/main/LICENSE",
        },
        "icons": {"color": "color.png", "outline": "outline.png"},
        "name": {"short": agent.display_name[:30], "full": f"{agent.display_name} (POC)"[:100]},
        "description": {"short": agent.tagline[:80], "full": agent.description[:4000]},
        "accentColor": agent.accent_color,
        "copilotAgents": {
            "declarativeAgents": [
                {"id": "declarativeAgent", "file": "declarativeAgent.json"}
            ]
        },
        "permissions": ["identity", "messageTeamMembers"],
        "validDomains": [apim_host],
    }


def package_files(agent: AgentDefinition, api_key_reference_id: str | None = None) -> dict[str, bytes]:
    """Returns the full set of package entries keyed by their path inside the zip."""

    def dumps(payload: dict) -> bytes:
        return json.dumps(payload, indent=2).encode("utf-8")

    files: dict[str, bytes] = {
        "manifest.json": dumps(_teams_manifest(agent)),
        "declarativeAgent.json": dumps(_declarative_agent(agent)),
        "ai-plugin.json": dumps(_plugin_manifest(agent, api_key_reference_id)),
        "apiSpecificationFile/openapi.json": dumps(build_openapi(agent)),
    }
    for icon in ("color.png", "outline.png"):
        files[icon] = (ASSETS_DIR / agent.id / icon).read_bytes()
    return files


def build_package(agent: AgentDefinition, api_key_reference_id: str | None = None) -> bytes:
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w", zipfile.ZIP_DEFLATED) as archive:
        for name, content in package_files(agent, api_key_reference_id).items():
            archive.writestr(name, content)
    return buffer.getvalue()
