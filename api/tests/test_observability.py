from __future__ import annotations

import os
import unittest
from types import SimpleNamespace
from unittest.mock import Mock, patch

from app.foundry import FoundryChat
from app import observability


class ObservabilityTests(unittest.TestCase):
    def setUp(self) -> None:
        observability._configured = False

    @patch("app.observability.AIProjectInstrumentor")
    @patch("app.observability.configure_azure_monitor")
    def test_configures_secure_foundry_tracing(self, configure_monitor, instrumentor_type) -> None:
        project = SimpleNamespace(
            telemetry=SimpleNamespace(
                get_application_insights_connection_string=Mock(
                    return_value="InstrumentationKey=test;IngestionEndpoint=https://example.invalid/"
                )
            )
        )

        with patch.dict(os.environ, {}, clear=True):
            self.assertTrue(observability.configure_observability(project))
            self.assertEqual(os.environ["AZURE_EXPERIMENTAL_ENABLE_GENAI_TRACING"], "true")
            self.assertEqual(
                os.environ["OTEL_INSTRUMENTATION_GENAI_CAPTURE_MESSAGE_CONTENT"], "false"
            )

        configure_monitor.assert_called_once()
        instrumentor_type.return_value.instrument.assert_called_once_with(
            enable_content_recording=False,
            enable_trace_context_propagation=True,
            enable_baggage_propagation=False,
        )

    def test_response_includes_agent_reference(self) -> None:
        response = SimpleNamespace(output_text="ok", output=[], status="completed")
        client = SimpleNamespace(
            conversations=SimpleNamespace(create=Mock(return_value=SimpleNamespace(id="conversation"))),
            responses=SimpleNamespace(create=Mock(return_value=response)),
        )
        chat = FoundryChat()
        chat._agent_clients["agent"] = client
        chat._agent_references["agent"] = {
            "name": "agent",
            "id": "agent-id",
            "type": "agent_reference",
        }

        reply = chat.ask("agent", "hello", None)

        self.assertEqual(reply.text, "ok")
        client.responses.create.assert_called_once_with(
            conversation="conversation",
            input="hello",
            extra_body={
                "agent_reference": {
                    "name": "agent",
                    "id": "agent-id",
                    "type": "agent_reference",
                }
            },
        )

    def test_agent_client_uses_latest_version_id(self) -> None:
        client = object()
        agent = SimpleNamespace(
            name="agent",
            versions=SimpleNamespace(latest=SimpleNamespace(id="agent:7")),
        )
        project = SimpleNamespace(
            agents=SimpleNamespace(get=Mock(return_value=agent)),
            get_openai_client=Mock(return_value=client),
        )
        chat = FoundryChat()
        chat._project = project

        self.assertIs(chat._agent_client("agent"), client)
        self.assertEqual(chat._agent_references["agent"]["id"], "agent:7")


if __name__ == "__main__":
    unittest.main()