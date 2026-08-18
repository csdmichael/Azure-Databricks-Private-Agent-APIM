"""Builds the Microsoft 365 declarative agent packages and validates them.

Writes each package to artifacts/m365/ and runs the checks the Microsoft 365
developer portal applies on upload:

* required files present and cross-references between them resolve;
* manifest.json, declarativeAgent.json and ai-plugin.json validate against the
  published Microsoft JSON schemas they declare;
* the bundled OpenAPI document is a valid OpenAPI 3 description;
* icon dimensions and outline transparency.

`atk validate --package-file <zip>` performs the same manifest validation but
requires an interactive Microsoft 365 sign-in, so it is not used here.

    python scripts/build_m365_packages.py
"""

from __future__ import annotations

import json
import sys
import urllib.request
import zipfile
from io import BytesIO
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "api"))

from app.catalog import AGENTS  # noqa: E402
from app.m365 import build_package  # noqa: E402

OUTPUT_DIR = REPO_ROOT / "artifacts" / "m365"
SCHEMA_CACHE = REPO_ROOT / "artifacts" / ".schema-cache"

REQUIRED_ENTRIES = {
    "manifest.json",
    "declarativeAgent.json",
    "ai-plugin.json",
    "apiSpecificationFile/openapi.json",
    "color.png",
    "outline.png",
}

# Limits published in the Teams app manifest schema.
MANIFEST_LIMITS = {
    ("name", "short"): 30,
    ("name", "full"): 100,
    ("description", "short"): 80,
    ("description", "full"): 4000,
}


def fetch_schema(url: str) -> dict | None:
    """Downloads a published schema, caching it so repeat runs work offline."""
    SCHEMA_CACHE.mkdir(parents=True, exist_ok=True)
    cached = SCHEMA_CACHE / (url.rsplit("/json-schemas/", 1)[-1].replace("/", "_"))
    if cached.exists():
        return json.loads(cached.read_text(encoding="utf-8"))
    try:
        with urllib.request.urlopen(url, timeout=30) as response:
            body = response.read().decode("utf-8")
    except Exception as error:  # offline runs fall back to structural checks only
        print(f"       ! could not download {url}: {error}")
        return None
    cached.write_text(body, encoding="utf-8")
    return json.loads(body)


def validate_against_schema(document: dict, label: str) -> list[str]:
    try:
        from jsonschema import Draft7Validator
    except ImportError:
        print("       ! jsonschema not installed; skipping published-schema validation")
        return []

    schema = fetch_schema(document["$schema"])
    if schema is None:
        return []
    validator = Draft7Validator(schema)
    return [
        f"{label}: {'/'.join(str(part) for part in error.absolute_path) or '<root>'}: {error.message}"
        for error in sorted(validator.iter_errors(document), key=lambda e: list(e.absolute_path))
    ]


def validate_openapi(document: dict) -> list[str]:
    try:
        from openapi_spec_validator import validate as validate_spec
    except ImportError:
        print("       ! openapi-spec-validator not installed; skipping OpenAPI validation")
        return []
    try:
        validate_spec(document)
    except Exception as error:
        return [f"openapi.json: {error}"]
    return []


def _png_size(data: bytes) -> tuple[int, int]:
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise AssertionError("icon is not a PNG")
    width = int.from_bytes(data[16:20], "big")
    height = int.from_bytes(data[20:24], "big")
    return width, height


def _png_has_alpha(data: bytes) -> bool:
    # Colour type lives in byte 25 of the IHDR chunk; 4 and 6 include an alpha channel.
    return data[25] in (4, 6)


def check(package: bytes, agent) -> list[str]:
    problems: list[str] = []
    with zipfile.ZipFile(BytesIO(package)) as archive:
        names = set(archive.namelist())
        missing = REQUIRED_ENTRIES - names
        if missing:
            problems.append(f"missing entries: {sorted(missing)}")
            return problems

        manifest = json.loads(archive.read("manifest.json"))
        declarative = json.loads(archive.read("declarativeAgent.json"))
        plugin = json.loads(archive.read("ai-plugin.json"))
        spec = json.loads(archive.read("apiSpecificationFile/openapi.json"))

        for icon_name, expected in (("color.png", 192), ("outline.png", 32)):
            data = archive.read(icon_name)
            width, height = _png_size(data)
            if (width, height) != (expected, expected):
                problems.append(f"{icon_name} is {width}x{height}, expected {expected}x{expected}")
        if not _png_has_alpha(archive.read("outline.png")):
            problems.append("outline.png must have a transparent background")

    # Manifest -> declarative agent -> plugin -> OpenAPI must all resolve.
    declarative_files = [
        entry["file"] for entry in manifest.get("copilotAgents", {}).get("declarativeAgents", [])
    ]
    if declarative_files != ["declarativeAgent.json"]:
        problems.append(f"manifest declarativeAgents file mismatch: {declarative_files}")

    action_files = [action["file"] for action in declarative.get("actions", [])]
    if action_files != ["ai-plugin.json"]:
        problems.append(f"declarativeAgent actions file mismatch: {action_files}")

    spec_url = plugin["runtimes"][0]["spec"]["url"]
    if spec_url != "apiSpecificationFile/openapi.json":
        problems.append(f"plugin spec url mismatch: {spec_url}")

    for section, field in MANIFEST_LIMITS:
        value = manifest[section][field]
        limit = MANIFEST_LIMITS[(section, field)]
        if len(value) > limit:
            problems.append(f"manifest.{section}.{field} is {len(value)} chars (max {limit})")

    if manifest["id"] != agent.teams_app_id:
        problems.append("manifest id does not match the catalog app id")

    # Every declared function must exist as an operationId in the OpenAPI document.
    operation_ids = {
        operation["operationId"]
        for path in spec["paths"].values()
        for operation in path.values()
    }
    declared = {function["name"] for function in plugin["functions"]}
    if not declared <= operation_ids:
        problems.append(f"functions without an operationId: {sorted(declared - operation_ids)}")
    run_for = set(plugin["runtimes"][0]["run_for_functions"])
    if run_for != declared:
        problems.append("run_for_functions does not match the declared functions")

    auth_type = plugin["runtimes"][0]["auth"]["type"]
    if auth_type not in ("None", "ApiKeyPluginVault", "OAuthPluginVault"):
        problems.append(f"unsupported auth type {auth_type}")

    if not spec["servers"][0]["url"].startswith("https://"):
        problems.append("OpenAPI server URL must be https")

    problems += validate_against_schema(manifest, "manifest.json")
    problems += validate_against_schema(declarative, "declarativeAgent.json")
    problems += validate_against_schema(plugin, "ai-plugin.json")
    problems += validate_openapi(spec)

    return problems


def main() -> int:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    failed = False
    for agent in AGENTS:
        package = build_package(agent)
        target = OUTPUT_DIR / f"{agent.id}-m365-agent.zip"
        target.write_bytes(package)
        problems = check(package, agent)
        status = "FAIL" if problems else "ok"
        print(f"[{status}] {target.relative_to(REPO_ROOT)} ({len(package):,} bytes)")
        for problem in problems:
            failed = True
            print(f"       - {problem}")

        # The shipping configuration uses an API key auth config from the
        # developer portal, so validate that variant too.
        keyed = build_package(agent, "00000000-0000-0000-0000-000000000000")
        keyed_problems = check(keyed, agent)
        print(f"[{'FAIL' if keyed_problems else 'ok'}] {agent.id} with ApiKeyPluginVault auth")
        for problem in keyed_problems:
            failed = True
            print(f"       - {problem}")

    if failed:
        print("\nPackage checks failed.")
        return 1
    print("\nAll package checks passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
