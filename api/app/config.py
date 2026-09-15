"""Runtime configuration for the Databricks Agents API."""

from __future__ import annotations

import json
import os
from functools import lru_cache
from pathlib import Path
from typing import Any


class ConfigurationError(RuntimeError):
    """Raised when required runtime configuration is missing or invalid."""


def _split(value: str) -> list[str]:
    return [item.strip() for item in value.split(",") if item.strip()]


def _load_deployment_config() -> dict[str, Any]:
    configured_path = os.getenv("DEPLOYMENT_CONFIG_PATH")
    path = (
        Path(configured_path).expanduser()
        if configured_path
        else Path(__file__).resolve().parents[2] / "config" / "deployment.json"
    )
    if not path.is_file():
        if configured_path:
            raise ConfigurationError(f"Deployment configuration file not found: {path}")
        return {}

    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ConfigurationError(
            f"Deployment configuration file is not valid JSON: {path}. {error}"
        ) from error
    if not isinstance(value, dict):
        raise ConfigurationError(f"Deployment configuration root must be an object: {path}")
    return value


def _config_value(config: dict[str, Any], path: str) -> Any:
    value: Any = config
    for segment in path.split("."):
        if not isinstance(value, dict) or segment not in value:
            return None
        value = value[segment]
    return value


def _required_string(config: dict[str, Any], env_name: str, config_path: str) -> str:
    value = os.getenv(env_name)
    if value is None:
        value = _config_value(config, config_path)
    if not isinstance(value, str) or not value.strip():
        raise ConfigurationError(
            f"Set {env_name} or provide '{config_path}' in the deployment configuration."
        )
    return value.strip()


def _positive_int(config: dict[str, Any], env_name: str, config_path: str) -> int:
    value = os.getenv(env_name)
    if value is None:
        value = _config_value(config, config_path)
    try:
        parsed = int(value)
    except (TypeError, ValueError) as error:
        raise ConfigurationError(
            f"{env_name} or '{config_path}' must be a positive integer."
        ) from error
    if parsed < 1:
        raise ConfigurationError(
            f"{env_name} or '{config_path}' must be a positive integer."
        )
    return parsed


class Settings:
    def __init__(self) -> None:
        config = _load_deployment_config()

        foundry_endpoint = os.getenv("FOUNDRY_PROJECT_ENDPOINT")
        if foundry_endpoint is None:
            account_name = _required_string(
                config, "FOUNDRY_ACCOUNT_NAME", "foundry.application.accountName"
            )
            project_name = _required_string(
                config, "FOUNDRY_PROJECT_NAME", "foundry.application.projectName"
            )
            foundry_endpoint = (
                f"https://{account_name}.services.ai.azure.com/api/projects/{project_name}"
            )
        if not foundry_endpoint.strip():
            raise ConfigurationError("FOUNDRY_PROJECT_ENDPOINT cannot be empty.")

        self.foundry_project_endpoint = foundry_endpoint.rstrip("/")
        self.apim_base_url = _required_string(
            config, "APIM_BASE_URL", "apim.gatewayUrl"
        ).rstrip("/")
        self.databricks_workspace_url = _required_string(
            config, "DATABRICKS_WORKSPACE_URL", "databricks.workspaceUrl"
        ).rstrip("/")
        self.github_repo_url = _required_string(
            config, "GITHUB_REPO_URL", "api.githubRepoUrl"
        ).rstrip("/")
        self.teams_app_id_namespace = _required_string(
            config, "TEAMS_APP_ID_NAMESPACE", "api.teamsAppIdNamespace"
        )
        self.databricks_catalog = _required_string(
            config, "DATABRICKS_CATALOG", "databricks.catalog"
        )
        self.databricks_schema = _required_string(
            config, "DATABRICKS_SCHEMA", "databricks.schema"
        )
        self.sql_foundry_agent_name = _required_string(
            config, "DATABRICKS_SQL_FOUNDRY_AGENT_NAME", "api.agents.sqlFoundryName"
        )
        self.genie_foundry_agent_name = _required_string(
            config, "DATABRICKS_GENIE_FOUNDRY_AGENT_NAME", "api.agents.genieFoundryName"
        )

        self.api_title = _required_string(config, "API_TITLE", "api.title")
        self.api_version = _required_string(config, "API_VERSION", "api.version")
        self.api_contact_name = _required_string(
            config, "API_CONTACT_NAME", "api.contactName"
        )
        self.api_license_name = _required_string(
            config, "API_LICENSE_NAME", "api.licenseName"
        )

        self.public_api_url = (os.getenv("PUBLIC_API_URL") or "").rstrip("/")
        self.request_timeout_seconds = _positive_int(
            config, "REQUEST_TIMEOUT_SECONDS", "api.requestTimeoutSeconds"
        )
        self.job_ttl_seconds = _positive_int(
            config, "JOB_TTL_SECONDS", "api.jobTtlSeconds"
        )
        self.max_jobs = _positive_int(config, "MAX_JOBS", "api.maxJobs")
        self.chat_job_workers = _positive_int(
            config, "CHAT_JOB_WORKERS", "api.chatJobWorkers"
        )
        self.max_mcp_approval_rounds = _positive_int(
            config, "MAX_MCP_APPROVAL_ROUNDS", "foundry.maxMcpApprovalRounds"
        )

        cors_value = os.getenv("CORS_ALLOW_ORIGINS")
        if cors_value is not None:
            self.cors_allow_origins = _split(cors_value)
        else:
            configured_origins = _config_value(config, "api.corsAllowOrigins")
            if not isinstance(configured_origins, list) or not all(
                isinstance(origin, str) and origin.strip() for origin in configured_origins
            ):
                raise ConfigurationError(
                    "Set CORS_ALLOW_ORIGINS or provide 'api.corsAllowOrigins' as a string array."
                )
            self.cors_allow_origins = [origin.strip() for origin in configured_origins]
        self.cors_allow_origin_regex = os.getenv("CORS_ALLOW_ORIGIN_REGEX") or None

        self.teams_manifest_version = _required_string(
            config, "TEAMS_MANIFEST_VERSION", "api.teamsManifestVersion"
        )
        self.declarative_agent_version = _required_string(
            config, "DECLARATIVE_AGENT_VERSION", "api.declarativeAgentVersion"
        )
        self.plugin_schema_version = _required_string(
            config, "PLUGIN_SCHEMA_VERSION", "api.pluginSchemaVersion"
        )
        self.m365_developer_name = _required_string(
            config, "M365_DEVELOPER_NAME", "api.m365DeveloperName"
        )
        self.m365_app_version = _required_string(
            config, "M365_APP_VERSION", "api.m365AppVersion"
        )
        self.m365_name_suffix = _required_string(
            config, "M365_NAME_SUFFIX", "api.m365NameSuffix"
        )

    @property
    def databricks_namespace(self) -> str:
        return f"{self.databricks_catalog}.{self.databricks_schema}"


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    return Settings()
