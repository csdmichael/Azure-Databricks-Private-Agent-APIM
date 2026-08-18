"""Runtime configuration for the Databricks Agents API.

Every value can be overridden with an environment variable so the same image
runs locally and on Azure App Service.
"""

import os
from functools import lru_cache


def _split(value: str) -> list[str]:
    return [item.strip() for item in value.split(",") if item.strip()]


class Settings:
    def __init__(self) -> None:
        self.foundry_project_endpoint = os.getenv(
            "FOUNDRY_PROJECT_ENDPOINT",
            "https://002-ai-poc-private.services.ai.azure.com/api/projects/proj-default",
        )
        self.apim_base_url = os.getenv(
            "APIM_BASE_URL", "https://ai-gateway-apim-poc-my.azure-api.net"
        )
        self.databricks_workspace_url = os.getenv(
            "DATABRICKS_WORKSPACE_URL",
            "https://adb-7405608662655754.14.azuredatabricks.net",
        )
        self.github_repo_url = os.getenv(
            "GITHUB_REPO_URL",
            "https://github.com/csdmichael/Azure-Databricks-Private-Agent-APIM",
        )
        self.public_api_url = os.getenv("PUBLIC_API_URL", "").rstrip("/")
        self.request_timeout_seconds = int(os.getenv("REQUEST_TIMEOUT_SECONDS", "300"))
        self.cors_allow_origins = _split(
            os.getenv("CORS_ALLOW_ORIGINS", "http://localhost:8100,http://localhost:4200")
        )
        # Set to "*" only for local exploration; App Service should list real origins.
        self.cors_allow_origin_regex = os.getenv("CORS_ALLOW_ORIGIN_REGEX") or None


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    return Settings()
