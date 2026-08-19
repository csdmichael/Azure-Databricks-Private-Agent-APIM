"""Databricks Agents API.

A small FastAPI service that lets the Angular/Ionic UI chat with the Microsoft
Foundry agents in this POC, download the PowerPoint files they generate, and
download Microsoft 365 declarative agent packages for each agent.

Interactive docs: /docs (Swagger UI) and /redoc.
"""

from __future__ import annotations

import logging
from urllib.parse import quote

from fastapi import FastAPI, HTTPException, Query, Response
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field

from .catalog import AGENTS, AGENTS_BY_ID
from .config import get_settings
from .foundry import foundry_chat
from .jobs import job_store
from .m365 import build_openapi, build_package, package_files

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

settings = get_settings()

DESCRIPTION = """
Chat with the Microsoft Foundry agents that read a **private Azure Databricks**
workspace through Azure API Management, and package those agents for Microsoft 365.

* `databricks-sql` runs governed read-only SQL through the APIM MCP server.
* `databricks-genie` asks AI/BI Genie business questions in natural language.

Both agents use Code Interpreter, so a chat turn can return a generated
PowerPoint or chart, downloadable via `/api/files/{container_id}/{file_id}`.

### Chatting

A turn can run for several minutes, which is longer than the Azure App Service
request limit. Chat is therefore asynchronous:

1. `POST /api/agents/{agent_id}/chat` returns **202** with a `jobId`.
2. Poll `GET /api/chat/jobs/{job_id}` until `status` is `completed` or `failed`.
"""

app = FastAPI(
    title="Databricks Agents API",
    description=DESCRIPTION,
    version="1.0.0",
    contact={
        "name": "Michael Yaacoub — Sr Solution Engineer, Microsoft",
        "url": settings.github_repo_url,
    },
    license_info={"name": "MIT", "url": f"{settings.github_repo_url}/blob/main/LICENSE"},
    docs_url="/docs",
    redoc_url="/redoc",
    openapi_url="/openapi.json",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_allow_origins,
    allow_origin_regex=settings.cors_allow_origin_regex,
    allow_credentials=False,
    allow_methods=["GET", "POST", "OPTIONS"],
    allow_headers=["Content-Type"],
)


# --------------------------------------------------------------------------- models
class ConversationStarter(BaseModel):
    title: str
    text: str


class AgentSummary(BaseModel):
    id: str = Field(..., examples=["databricks-genie"])
    foundryAgentName: str
    displayName: str
    shortName: str
    tagline: str
    description: str
    accentColor: str
    tools: list[str]
    conversationStarters: list[ConversationStarter]
    iconUrl: str
    m365PackageUrl: str


class ChatRequest(BaseModel):
    message: str = Field(
        ...,
        min_length=1,
        max_length=8000,
        description="The user's question. Plain text or Markdown.",
        examples=["Show total revenue in USD millions by region and chart it."],
    )
    conversationId: str | None = Field(
        default=None,
        description="Pass the id returned by a previous turn to continue the thread.",
    )


class GeneratedFileModel(BaseModel):
    fileId: str
    containerId: str
    filename: str
    downloadUrl: str
    previewUrl: str | None = None
    mediaType: str | None = None


class ChatResponse(BaseModel):
    agentId: str
    conversationId: str
    reply: str = Field(..., description="The agent's answer, in Markdown.")
    toolCalls: list[str]
    files: list[GeneratedFileModel]


class ChatJobAccepted(BaseModel):
    jobId: str
    agentId: str
    status: str = Field("running", examples=["running"])
    pollUrl: str


class ChatJobStatus(BaseModel):
    jobId: str
    agentId: str
    status: str = Field(..., description="running, completed or failed.")
    result: ChatResponse | None = None
    error: str | None = None


class M365PackageSummary(BaseModel):
    agentId: str
    displayName: str
    teamsAppId: str
    fileName: str
    downloadUrl: str
    contents: list[str]
    requiresApiKeyReferenceId: bool


class HealthResponse(BaseModel):
    status: str
    agents: list[str]


# --------------------------------------------------------------------------- helpers
def _agent_or_404(agent_id: str):
    agent = AGENTS_BY_ID.get(agent_id)
    if agent is None:
        raise HTTPException(status_code=404, detail=f"Unknown agent '{agent_id}'")
    return agent


def _base_url() -> str:
    return settings.public_api_url


PREVIEW_IMAGE_TYPES = {
    "gif": "image/gif",
    "jpeg": "image/jpeg",
    "jpg": "image/jpeg",
    "png": "image/png",
    "webp": "image/webp",
}


def _preview_media_type(filename: str) -> str | None:
    extension = filename.rsplit(".", 1)[-1].lower() if "." in filename else ""
    return PREVIEW_IMAGE_TYPES.get(extension)


def _summary(agent) -> AgentSummary:
    base = _base_url()
    return AgentSummary(
        id=agent.id,
        foundryAgentName=agent.foundry_agent_name,
        displayName=agent.display_name,
        shortName=agent.short_name,
        tagline=agent.tagline,
        description=agent.description,
        accentColor=agent.accent_color,
        tools=agent.tools,
        conversationStarters=[ConversationStarter(**s) for s in agent.conversation_starters],
        iconUrl=f"{base}/api/agents/{agent.id}/icon",
        m365PackageUrl=f"{base}/api/m365/packages/{agent.id}",
    )


# --------------------------------------------------------------------------- routes
@app.get("/health", response_model=HealthResponse, tags=["System"])
def health() -> HealthResponse:
    """Liveness probe used by App Service and the deployment workflows."""
    return HealthResponse(status="ok", agents=[agent.id for agent in AGENTS])


@app.get("/api/agents", response_model=list[AgentSummary], tags=["Agents"])
def list_agents() -> list[AgentSummary]:
    """Lists the agents available as chat tabs in the UI."""
    return [_summary(agent) for agent in AGENTS]


@app.get("/api/agents/{agent_id}", response_model=AgentSummary, tags=["Agents"])
def get_agent(agent_id: str) -> AgentSummary:
    return _summary(_agent_or_404(agent_id))


@app.get(
    "/api/agents/{agent_id}/icon",
    tags=["Agents"],
    response_class=Response,
    responses={200: {"content": {"image/png": {}}, "description": "Agent colour icon"}},
)
def get_agent_icon(agent_id: str) -> Response:
    """Returns the agent's 192x192 colour icon, the same one used in its M365 package."""
    agent = _agent_or_404(agent_id)
    icon = package_files(agent)["color.png"]
    return Response(
        content=icon,
        media_type="image/png",
        headers={"Cache-Control": "public, max-age=86400"},
    )


def _chat_response(agent, reply) -> ChatResponse:
    base = _base_url()
    generated_files = []
    for file in reply.files:
        encoded_filename = quote(file.filename, safe="")
        download_url = (
            f"{base}/api/files/{file.container_id}/{file.file_id}"
            f"?filename={encoded_filename}"
        )
        media_type = _preview_media_type(file.filename)
        generated_files.append(
            GeneratedFileModel(
                fileId=file.file_id,
                containerId=file.container_id,
                filename=file.filename,
                downloadUrl=download_url,
                previewUrl=f"{download_url}&inline=true" if media_type else None,
                mediaType=media_type,
            )
        )
    return ChatResponse(
        agentId=agent.id,
        conversationId=reply.conversation_id,
        reply=reply.text,
        toolCalls=reply.tool_calls,
        files=generated_files,
    )


@app.post(
    "/api/agents/{agent_id}/chat",
    response_model=ChatJobAccepted,
    status_code=202,
    tags=["Chat"],
)
def start_chat(agent_id: str, request: ChatRequest) -> ChatJobAccepted:
    """Starts a chat turn and returns a job to poll.

    The agent may call Databricks through APIM several times and then run Code
    Interpreter to build a chart or a PowerPoint file, so a turn can take
    minutes. Poll `/api/chat/jobs/{job_id}` for the answer.
    """
    agent = _agent_or_404(agent_id)
    job = job_store.submit(
        agent.id,
        lambda: foundry_chat.ask(
            agent.foundry_agent_name, request.message, request.conversationId
        ),
    )
    return ChatJobAccepted(
        jobId=job.id,
        agentId=agent.id,
        status=job.status,
        pollUrl=f"{_base_url()}/api/chat/jobs/{job.id}",
    )


@app.get("/api/chat/jobs/{job_id}", response_model=ChatJobStatus, tags=["Chat"])
def get_chat_job(job_id: str) -> ChatJobStatus:
    """Returns the state of a chat turn, and its answer once it has completed."""
    job = job_store.get(job_id)
    if job is None:
        raise HTTPException(status_code=404, detail="Unknown or expired job")
    result = None
    if job.status == "completed" and job.result is not None:
        result = _chat_response(AGENTS_BY_ID[job.agent_id], job.result)
    return ChatJobStatus(
        jobId=job.id,
        agentId=job.agent_id,
        status=job.status,
        result=result,
        error=job.error,
    )


@app.get(
    "/api/files/{container_id}/{file_id}",
    tags=["Chat"],
    response_class=Response,
    responses={200: {"content": {"application/octet-stream": {}}}},
)
def download_generated_file(
    container_id: str,
    file_id: str,
    filename: str = Query("download", description="Name to save the file as."),
    inline: bool = Query(False, description="Display supported chart images in the browser."),
) -> Response:
    """Downloads a file (usually a .pptx) produced by Code Interpreter."""
    safe_name = filename.replace("\\", "/").split("/")[-1] or "download"
    try:
        content = foundry_chat.download_file(container_id, file_id)
    except Exception as error:
        logger.exception("File download failed")
        raise HTTPException(status_code=404, detail=f"File not available: {error}") from error
    preview_media_type = _preview_media_type(safe_name)
    media_type = preview_media_type or (
        "application/vnd.openxmlformats-officedocument.presentationml.presentation"
        if safe_name.lower().endswith(".pptx")
        else "application/octet-stream"
    )
    disposition = "inline" if inline and preview_media_type else "attachment"
    header_name = safe_name.replace('"', "'").replace("\r", "").replace("\n", "")
    return Response(
        content=content,
        media_type=media_type,
        headers={
            "Content-Disposition": (
                f'{disposition}; filename="{header_name}"; '
                f"filename*=UTF-8''{quote(safe_name, safe='')}"
            )
        },
    )


@app.get("/api/m365/packages", response_model=list[M365PackageSummary], tags=["Microsoft 365"])
def list_m365_packages() -> list[M365PackageSummary]:
    """Lists the declarative agent packages that can be uploaded to the M365 developer portal."""
    base = _base_url()
    return [
        M365PackageSummary(
            agentId=agent.id,
            displayName=agent.display_name,
            teamsAppId=agent.teams_app_id,
            fileName=f"{agent.id}-m365-agent.zip",
            downloadUrl=f"{base}/api/m365/packages/{agent.id}",
            contents=sorted(package_files(agent).keys()),
            requiresApiKeyReferenceId=True,
        )
        for agent in AGENTS
    ]


@app.get(
    "/api/m365/packages/{agent_id}",
    tags=["Microsoft 365"],
    response_class=Response,
    responses={200: {"content": {"application/zip": {}}, "description": "App package"}},
)
def download_m365_package(
    agent_id: str,
    apiKeyReferenceId: str | None = Query(
        default=None,
        max_length=200,
        description=(
            "Optional API key auth config id from Teams Developer Portal → Tools → "
            "API key registration. When supplied, the plugin uses ApiKeyPluginVault so "
            "Copilot sends the APIM subscription key; otherwise auth is set to None."
        ),
    ),
) -> Response:
    """Builds and downloads the Microsoft 365 declarative agent package for an agent."""
    agent = _agent_or_404(agent_id)
    content = build_package(agent, apiKeyReferenceId)
    return Response(
        content=content,
        media_type="application/zip",
        headers={
            "Content-Disposition": f'attachment; filename="{agent.id}-m365-agent.zip"'
        },
    )


@app.get("/api/m365/packages/{agent_id}/openapi", tags=["Microsoft 365"])
def get_package_openapi(agent_id: str) -> JSONResponse:
    """Returns the OpenAPI description of the APIM operations the agent's plugin calls."""
    return JSONResponse(build_openapi(_agent_or_404(agent_id)))
