from __future__ import annotations

import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from app.config import ConfigurationError, Settings


def _configuration() -> dict:
    return {
        "foundry": {
            "application": {"accountName": "foundry-test", "projectName": "project-test"},
            "maxMcpApprovalRounds": 6,
        },
        "apim": {"gatewayUrl": "https://gateway.example"},
        "databricks": {
            "workspaceUrl": "https://workspace.example",
            "catalog": "catalog_test",
            "schema": "schema_test",
        },
        "api": {
            "title": "Test API",
            "version": "1.2.3",
            "contactName": "Test Owner",
            "licenseName": "Test License",
            "githubRepoUrl": "https://example.test/repository",
            "teamsAppIdNamespace": "https://example.test/repository/m365/",
            "m365DeveloperName": "Test Developer",
            "m365AppVersion": "2.3.4",
            "m365NameSuffix": "(Test)",
            "agents": {
                "sqlFoundryName": "sql-agent",
                "genieFoundryName": "genie-agent",
            },
            "corsAllowOrigins": ["https://app.example"],
            "requestTimeoutSeconds": 120,
            "jobTtlSeconds": 600,
            "maxJobs": 50,
            "chatJobWorkers": 2,
            "teamsManifestVersion": "1.29",
            "declarativeAgentVersion": "v1.8",
            "pluginSchemaVersion": "v2.4",
        },
    }


class SettingsTests(unittest.TestCase):
    def _write_config(self, directory: str, value: dict) -> str:
        path = Path(directory) / "deployment.json"
        path.write_text(json.dumps(value), encoding="utf-8")
        return str(path)

    def test_reads_shared_config_when_environment_is_empty(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = self._write_config(directory, _configuration())
            with patch.dict(os.environ, {"DEPLOYMENT_CONFIG_PATH": path}, clear=True):
                settings = Settings()

        self.assertEqual(
            settings.foundry_project_endpoint,
            "https://foundry-test.services.ai.azure.com/api/projects/project-test",
        )
        self.assertEqual(settings.databricks_namespace, "catalog_test.schema_test")
        self.assertEqual(settings.sql_foundry_agent_name, "sql-agent")
        self.assertEqual(settings.api_title, "Test API")
        self.assertEqual(settings.chat_job_workers, 2)
        self.assertEqual(settings.cors_allow_origins, ["https://app.example"])

    def test_environment_overrides_shared_config(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = self._write_config(directory, _configuration())
            with patch.dict(
                os.environ,
                {
                    "DEPLOYMENT_CONFIG_PATH": path,
                    "APIM_BASE_URL": "https://override.example/",
                    "DATABRICKS_CATALOG": "override_catalog",
                    "CHAT_JOB_WORKERS": "7",
                    "CORS_ALLOW_ORIGINS": "https://one.example, https://two.example",
                },
                clear=True,
            ):
                settings = Settings()

        self.assertEqual(settings.apim_base_url, "https://override.example")
        self.assertEqual(settings.databricks_catalog, "override_catalog")
        self.assertEqual(settings.chat_job_workers, 7)
        self.assertEqual(
            settings.cors_allow_origins,
            ["https://one.example", "https://two.example"],
        )

    def test_missing_required_value_has_actionable_error(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = self._write_config(directory, {})
            with patch.dict(os.environ, {"DEPLOYMENT_CONFIG_PATH": path}, clear=True):
                with self.assertRaisesRegex(ConfigurationError, "FOUNDRY_ACCOUNT_NAME"):
                    Settings()

    def test_rejects_invalid_positive_integer(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = self._write_config(directory, _configuration())
            with patch.dict(
                os.environ,
                {"DEPLOYMENT_CONFIG_PATH": path, "MAX_JOBS": "0"},
                clear=True,
            ):
                with self.assertRaisesRegex(ConfigurationError, "MAX_JOBS"):
                    Settings()


if __name__ == "__main__":
    unittest.main()