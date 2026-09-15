"""Azure Monitor logging and OpenTelemetry tracing configuration."""

from __future__ import annotations

import logging
import os
import threading
from typing import TYPE_CHECKING

from azure.ai.projects.telemetry import AIProjectInstrumentor
from azure.core.settings import settings as azure_core_settings
from azure.monitor.opentelemetry import configure_azure_monitor

if TYPE_CHECKING:
    from azure.ai.projects import AIProjectClient

logger = logging.getLogger(__name__)

_lock = threading.Lock()
_configured = False


def configure_observability(project: AIProjectClient | None = None) -> bool:
    """Configure Azure Monitor once, resolving the connection from Foundry when needed."""
    global _configured

    if _configured:
        return True

    connection_string = os.getenv("APPLICATIONINSIGHTS_CONNECTION_STRING")
    if not connection_string and project is not None:
        try:
            connection_string = project.telemetry.get_application_insights_connection_string()
        except Exception:
            logger.exception("Application Insights is not connected to the Foundry project")
            return False
    if not connection_string:
        logger.info("Azure Monitor export will start when a Foundry project is initialized")
        return False

    with _lock:
        if _configured:
            return True

        os.environ["AZURE_EXPERIMENTAL_ENABLE_GENAI_TRACING"] = "true"
        os.environ["OTEL_INSTRUMENTATION_GENAI_CAPTURE_MESSAGE_CONTENT"] = "false"
        os.environ["AZURE_TRACING_GEN_AI_INCLUDE_BINARY_DATA"] = "false"
        azure_core_settings.tracing_implementation = "opentelemetry"
        configure_azure_monitor(connection_string=connection_string, logger_name="app")
        AIProjectInstrumentor().instrument(
            enable_content_recording=False,
            enable_trace_context_propagation=True,
            enable_baggage_propagation=False,
        )
        _configured = True
        logger.info("Azure Monitor logging and Foundry agent tracing configured")
        return True