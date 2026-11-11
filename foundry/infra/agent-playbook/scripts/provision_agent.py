"""Create or update a Foundry prompt agent version from a JSON config file."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

from azure.ai.projects import AIProjectClient
from azure.ai.projects.models import PromptAgentDefinition
from azure.identity import DefaultAzureCredential


def _read_config(config_path: Path) -> dict[str, Any]:
    with config_path.open("r", encoding="utf-8") as handle:
        payload = json.load(handle)
    if not isinstance(payload, dict):
        raise ValueError("The agent configuration must be a JSON object.")
    return payload


def _required_string(payload: dict[str, Any], key: str) -> str:
    value = payload.get(key)
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"Required configuration field '{key}' must be a non-empty string.")
    return value.strip()


def _resolve_definition(payload: dict[str, Any]) -> dict[str, Any]:
    definition = payload.get("definition")
    if not isinstance(definition, dict):
        raise ValueError("Required configuration field 'definition' must be an object.")

    model = definition.get("model")
    instructions = definition.get("instructions")
    if not isinstance(model, str) or not model.strip():
        raise ValueError("definition.model must be a non-empty string.")
    if not isinstance(instructions, str) or not instructions.strip():
        raise ValueError("definition.instructions must be a non-empty string.")

    return definition


def _require_string_list(values: Any, field_name: str) -> list[str]:
    if not isinstance(values, list):
        raise ValueError(f"{field_name} must be a list of strings.")
    if not all(isinstance(item, str) for item in values):
        raise ValueError(f"{field_name} must contain only strings.")
    return values


def _resolve_evaluation(payload: dict[str, Any]) -> dict[str, Any]:
    evaluation = payload.get("evaluation", {})
    if evaluation is None:
        evaluation = {}
    if not isinstance(evaluation, dict):
        raise ValueError("evaluation must be an object when provided.")

    enabled = bool(evaluation.get("enabled", False))
    if "min_pass_rate" in evaluation:
        min_pass_rate = evaluation.get("min_pass_rate", 1.0)
        if not isinstance(min_pass_rate, (int, float)):
            raise ValueError("evaluation.min_pass_rate must be a number.")
        min_pass_rate = float(min_pass_rate)
    else:
        min_pass_rate_percent = evaluation.get("min_pass_rate_percent", 100)
        if not isinstance(min_pass_rate_percent, (int, float)):
            raise ValueError("evaluation.min_pass_rate_percent must be a number.")
        min_pass_rate = float(min_pass_rate_percent) / 100.0
    if min_pass_rate < 0 or min_pass_rate > 1:
        raise ValueError("evaluation.min_pass_rate must be between 0 and 1.")

    fail_on_error = bool(evaluation.get("fail_on_error", True))
    cases = evaluation.get("cases", [])
    if not isinstance(cases, list):
        raise ValueError("evaluation.cases must be a list.")
    if enabled and len(cases) == 0:
        raise ValueError("evaluation.cases must contain at least one test case when evaluation is enabled.")

    normalized_cases: list[dict[str, Any]] = []
    for index, case in enumerate(cases):
        if not isinstance(case, dict):
            raise ValueError(f"evaluation.cases[{index}] must be an object.")
        prompt = case.get("prompt")
        if not isinstance(prompt, str) or not prompt.strip():
            raise ValueError(f"evaluation.cases[{index}].prompt must be a non-empty string.")
        case_name = case.get("name")
        if case_name is not None and (not isinstance(case_name, str) or not case_name.strip()):
            raise ValueError(f"evaluation.cases[{index}].name must be a non-empty string when provided.")

        must_contain_any = _require_string_list(case.get("must_contain_any", []), f"evaluation.cases[{index}].must_contain_any")
        must_not_contain_any = _require_string_list(case.get("must_not_contain_any", []), f"evaluation.cases[{index}].must_not_contain_any")

        normalized_cases.append(
            {
                "name": case_name.strip() if isinstance(case_name, str) else f"case-{index + 1}",
                "prompt": prompt.strip(),
                "must_contain_any": must_contain_any,
                "must_not_contain_any": must_not_contain_any,
            }
        )

    return {
        "enabled": enabled,
        "min_pass_rate": min_pass_rate,
        "fail_on_error": fail_on_error,
        "cases": normalized_cases,
    }


def _run_evaluation(client: AIProjectClient, agent_name: str, evaluation: dict[str, Any]) -> dict[str, Any] | None:
    if not evaluation.get("enabled"):
        return None

    openai = client.get_openai_client(agent_name=agent_name)
    results: list[dict[str, Any]] = []
    passed = 0

    for case in evaluation["cases"]:
        conversation = openai.conversations.create()
        try:
            response = openai.responses.create(
                conversation=conversation.id,
                input=case["prompt"],
            )
            output_text = (response.output_text or "").strip()
        finally:
            openai.conversations.delete(conversation.id)

        has_required = True
        if case["must_contain_any"]:
            lower_output = output_text.lower()
            has_required = any(token.lower() in lower_output for token in case["must_contain_any"])

        has_forbidden = False
        if case["must_not_contain_any"]:
            lower_output = output_text.lower()
            has_forbidden = any(token.lower() in lower_output for token in case["must_not_contain_any"])

        case_passed = has_required and not has_forbidden
        if case_passed:
            passed += 1
        results.append(
            {
                "name": case["name"],
                "passed": case_passed,
                "prompt": case["prompt"],
                "must_contain_any": case["must_contain_any"],
                "must_not_contain_any": case["must_not_contain_any"],
                "response_preview": output_text[:500],
            }
        )

    total = len(results)
    pass_rate = float(passed) / float(total)
    summary = {
        "enabled": True,
        "total_cases": total,
        "passed_cases": passed,
        "pass_rate": pass_rate,
        "min_pass_rate": evaluation["min_pass_rate"],
        "cases": results,
    }

    if evaluation["fail_on_error"] and pass_rate < evaluation["min_pass_rate"]:
        raise RuntimeError(
            f"Evaluation gate failed: pass_rate={pass_rate:.2f} required>={evaluation['min_pass_rate']:.2f}"
        )
    return summary


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", required=True, help="Path to agent JSON configuration.")
    args = parser.parse_args()

    config = _read_config(Path(args.config))
    project_endpoint = _required_string(config, "project_endpoint")
    agent_name = _required_string(config, "agent_name")
    definition_payload = _resolve_definition(config)
    evaluation = _resolve_evaluation(config)
    version_description = config.get("version_description")
    if version_description is not None and not isinstance(version_description, str):
        raise ValueError("version_description must be a string when provided.")

    client = AIProjectClient(
        endpoint=project_endpoint,
        credential=DefaultAzureCredential(),
    )
    definition = PromptAgentDefinition(**definition_payload)

    create_kwargs: dict[str, Any] = {}
    if isinstance(version_description, str) and version_description.strip():
        create_kwargs["description"] = version_description.strip()

    agent = client.agents.create_version(
        agent_name=agent_name,
        definition=definition,
        **create_kwargs,
    )
    evaluation_result = _run_evaluation(client=client, agent_name=agent.name, evaluation=evaluation)

    print(
        json.dumps(
            {
                "agent_name": agent.name,
                "agent_version": agent.version,
                "project_endpoint": project_endpoint,
                "evaluation": evaluation_result,
            },
            separators=(",", ":"),
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
