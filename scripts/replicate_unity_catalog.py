"""Copy a managed Unity Catalog catalog between Databricks workspaces."""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import time
from pathlib import Path
from typing import Any

import requests

DATABRICKS_RESOURCE_ID = "2ff814a6-3304-4ab8-85cb-cd0e6f879c1d"
TERMINAL_STATES = {"CANCELED", "CLOSED", "FAILED", "SUCCEEDED"}


class DatabricksClient:
    def __init__(
        self,
        host: str,
        token: str,
        api_timeout_seconds: int,
        api_retry_attempts: int,
        api_retry_max_delay_seconds: int,
        sql_wait_timeout_seconds: int,
        sql_poll_interval_seconds: int,
        sql_row_limit: int,
        sql_byte_limit: int,
    ):
        self.host = host.rstrip("/")
        self.api_timeout_seconds = api_timeout_seconds
        self.api_retry_attempts = api_retry_attempts
        self.api_retry_max_delay_seconds = api_retry_max_delay_seconds
        self.sql_wait_timeout_seconds = sql_wait_timeout_seconds
        self.sql_poll_interval_seconds = sql_poll_interval_seconds
        self.sql_row_limit = sql_row_limit
        self.sql_byte_limit = sql_byte_limit
        self.session = requests.Session()
        self.session.headers.update(
            {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}
        )

    def request(
        self, method: str, path: str, body: dict[str, Any] | None = None
    ) -> dict[str, Any]:
        for attempt in range(self.api_retry_attempts):
            response = self.session.request(
                method,
                f"{self.host}{path}",
                json=body,
                timeout=self.api_timeout_seconds,
            )
            if (
                response.status_code in {429, 500, 502, 503, 504}
                and attempt < self.api_retry_attempts - 1
            ):
                time.sleep(min(2**attempt, self.api_retry_max_delay_seconds))
                continue
            if not response.ok:
                raise RuntimeError(
                    f"{method} {path} returned HTTP {response.status_code}: "
                    f"{response.text}"
                )
            return response.json() if response.content else {}
        raise AssertionError("unreachable")


def azure_cli_token() -> str:
    az = shutil.which("az")
    if not az:
        raise RuntimeError("Azure CLI was not found in PATH.")
    result = subprocess.run(
        [
            az,
            "account",
            "get-access-token",
            "--resource",
            DATABRICKS_RESOURCE_ID,
            "--query",
            "accessToken",
            "--output",
            "tsv",
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    token = result.stdout.strip()
    if not token:
        raise RuntimeError("Azure CLI returned an empty Databricks token.")
    return token


def quote_identifier(value: str) -> str:
    return f"`{value.replace('`', '``')}`"


def qualified(*parts: str) -> str:
    return ".".join(quote_identifier(part) for part in parts)


def sql_string(value: str) -> str:
    return "'" + value.replace("\\", "\\\\").replace("'", "''") + "'"


def page_all(
    client: DatabricksClient,
    path: str,
    key: str,
    parameters: dict[str, str] | None = None,
) -> list[dict[str, Any]]:
    parameters = dict(parameters or {})
    items: list[dict[str, Any]] = []
    while True:
        query = requests.compat.urlencode(parameters)
        response = client.request("GET", f"{path}?{query}" if query else path)
        items.extend(response.get(key) or [])
        token = response.get("next_page_token")
        if not token:
            return items
        parameters["page_token"] = token


def execute_sql(
    client: DatabricksClient, warehouse_id: str, statement: str
) -> list[list[str | None]]:
    response = client.request(
        "POST",
        "/api/2.0/sql/statements",
        {
            "warehouse_id": warehouse_id,
            "statement": statement,
            "wait_timeout": f"{client.sql_wait_timeout_seconds}s",
            "on_wait_timeout": "CONTINUE",
            "format": "JSON_ARRAY",
            "disposition": "INLINE",
            "row_limit": client.sql_row_limit,
            "byte_limit": client.sql_byte_limit,
        },
    )
    statement_id = response["statement_id"]
    while response.get("status", {}).get("state") not in TERMINAL_STATES:
        time.sleep(client.sql_poll_interval_seconds)
        response = client.request("GET", f"/api/2.0/sql/statements/{statement_id}")
    status = response.get("status", {})
    if status.get("state") != "SUCCEEDED":
        message = status.get("error", {}).get("message", "unknown SQL error")
        raise RuntimeError(f"Statement {statement_id} failed: {message}")

    result = response.get("result") or {}
    rows = list(result.get("data_array") or [])
    next_chunk = result.get("next_chunk_index")
    while next_chunk is not None:
        chunk = client.request(
            "GET", f"/api/2.0/sql/statements/{statement_id}/result/chunks/{next_chunk}"
        )
        chunk_result = chunk.get("result") or chunk
        rows.extend(chunk_result.get("data_array") or [])
        next_chunk = chunk_result.get("next_chunk_index")
    return rows


def inventory(client: DatabricksClient, catalog: str) -> list[dict[str, Any]]:
    schemas = page_all(
        client,
        "/api/2.1/unity-catalog/schemas",
        "schemas",
        {"catalog_name": catalog},
    )
    copied: list[dict[str, Any]] = []
    unsupported: list[str] = []
    for schema in schemas:
        if schema["name"] == "information_schema":
            continue
        parameters = {"catalog_name": catalog, "schema_name": schema["name"]}
        tables = page_all(
            client, "/api/2.1/unity-catalog/tables", "tables", parameters
        )
        volumes = page_all(
            client, "/api/2.1/unity-catalog/volumes", "volumes", parameters
        )
        functions = page_all(
            client, "/api/2.1/unity-catalog/functions", "functions", parameters
        )
        if volumes:
            unsupported.append(f"{schema['name']}: {len(volumes)} volume(s)")
        if functions:
            unsupported.append(f"{schema['name']}: {len(functions)} function(s)")
        for table in tables:
            if table.get("table_type") != "MANAGED":
                unsupported.append(
                    f"{schema['name']}.{table['name']}: {table.get('table_type')}"
                )
        copied.append({"schema": schema, "tables": tables})
    if unsupported:
        raise RuntimeError(
            "A complete copy cannot skip these unsupported objects:\n  - "
            + "\n  - ".join(unsupported)
        )
    return copied


def create_table_sql(catalog: str, schema: str, table: dict[str, Any]) -> str:
    definitions = []
    for column in sorted(table["columns"], key=lambda item: item["position"]):
        definition = f"{quote_identifier(column['name'])} {column['type_text']}"
        if not column.get("nullable", True):
            definition += " NOT NULL"
        if column.get("comment") is not None:
            definition += f" COMMENT {sql_string(column['comment'])}"
        definitions.append(definition)
    sql = (
        f"CREATE OR REPLACE TABLE {qualified(catalog, schema, table['name'])} (\n  "
        + ",\n  ".join(definitions)
        + "\n) USING DELTA"
    )
    if table.get("comment") is not None:
        sql += f" COMMENT {sql_string(table['comment'])}"
    return sql


def value_sql(value: str | None, column: dict[str, Any]) -> str:
    if value is None:
        return "NULL"
    type_name = column["type_name"].upper()
    if type_name in {"STRING", "CHAR", "VARCHAR"}:
        return sql_string(value)
    unsupported = {
        "ARRAY",
        "BINARY",
        "GEOGRAPHY",
        "GEOMETRY",
        "INTERVAL",
        "MAP",
        "OBJECT",
        "STRUCT",
        "VARIANT",
    }
    if type_name in unsupported:
        raise RuntimeError(
            f"Column {column['name']} uses unsupported type {column['type_text']}."
        )
    return f"CAST({sql_string(value)} AS {column['type_text']})"


def canonical(rows: list[list[str | None]]) -> list[str]:
    return sorted(json.dumps(row, separators=(",", ":")) for row in rows)


def copy_table(
    source: DatabricksClient,
    target: DatabricksClient,
    source_warehouse: str,
    target_warehouse: str,
    source_catalog: str,
    target_catalog: str,
    schema: str,
    table: dict[str, Any],
    batch_size: int,
) -> int:
    columns = sorted(table["columns"], key=lambda item: item["position"])
    column_names = ", ".join(quote_identifier(column["name"]) for column in columns)
    source_name = qualified(source_catalog, schema, table["name"])
    target_name = qualified(target_catalog, schema, table["name"])
    source_rows = execute_sql(
        source, source_warehouse, f"SELECT {column_names} FROM {source_name}"
    )
    execute_sql(target, target_warehouse, create_table_sql(target_catalog, schema, table))
    for offset in range(0, len(source_rows), batch_size):
        values = []
        for row in source_rows[offset : offset + batch_size]:
            values.append(
                "("
                + ", ".join(
                    value_sql(value, column)
                    for value, column in zip(row, columns, strict=True)
                )
                + ")"
            )
        execute_sql(
            target,
            target_warehouse,
            f"INSERT INTO {target_name} ({column_names}) VALUES\n" + ",\n".join(values),
        )
    target_rows = execute_sql(
        target, target_warehouse, f"SELECT {column_names} FROM {target_name}"
    )
    if canonical(source_rows) != canonical(target_rows):
        raise RuntimeError(f"Exact-row verification failed for {target_name}.")
    return len(source_rows)


def stop_if_previously_stopped(
    client: DatabricksClient, warehouse_id: str, initial_state: str
) -> None:
    if initial_state == "STOPPED":
        client.request("POST", f"/api/2.0/sql/warehouses/{warehouse_id}/stop")


def _load_config(path: str | None) -> dict[str, Any]:
    config_path = (
        Path(path).expanduser()
        if path
        else Path(__file__).resolve().parents[1] / "config" / "deployment.json"
    )
    try:
        value = json.loads(config_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ValueError(f"Cannot read deployment configuration {config_path}: {error}") from error
    if not isinstance(value, dict):
        raise ValueError(f"Deployment configuration root must be an object: {config_path}")
    return value


def _config_value(config: dict[str, Any], path: str) -> Any:
    value: Any = config
    for segment in path.split("."):
        if not isinstance(value, dict) or segment not in value:
            return None
        value = value[segment]
    return value


def _positive_setting(
    command_value: int | None,
    env_name: str,
    config: dict[str, Any],
    config_path: str,
) -> int:
    value: Any = command_value
    if value is None:
        value = os.getenv(env_name)
    if value is None:
        value = _config_value(config, config_path)
    try:
        parsed = int(value)
    except (TypeError, ValueError) as error:
        raise ValueError(
            f"Set --{env_name.lower().replace('_', '-')} or configure '{config_path}' as a positive integer."
        ) from error
    if parsed < 1:
        raise ValueError(f"{env_name} must be greater than zero.")
    return parsed


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config-path", default=os.getenv("DEPLOYMENT_CONFIG_PATH"))
    parser.add_argument("--source-host", required=True)
    parser.add_argument("--target-host", required=True)
    parser.add_argument("--source-catalog", required=True)
    parser.add_argument("--target-catalog", required=True)
    parser.add_argument("--source-warehouse-id", required=True)
    parser.add_argument("--target-warehouse-id", required=True)
    parser.add_argument("--batch-size", type=int)
    parser.add_argument("--api-timeout-seconds", type=int)
    parser.add_argument("--api-retry-attempts", type=int)
    parser.add_argument("--api-retry-max-delay-seconds", type=int)
    parser.add_argument("--sql-wait-timeout-seconds", type=int)
    parser.add_argument("--sql-poll-interval-seconds", type=int)
    parser.add_argument("--sql-row-limit", type=int)
    parser.add_argument("--sql-byte-limit", type=int)
    args = parser.parse_args()
    config = _load_config(args.config_path)
    settings = {
        "batch_size": ("DATABRICKS_REPLICATION_BATCH_SIZE", "databricks.replicationBatchSize"),
        "api_timeout_seconds": ("DATABRICKS_API_TIMEOUT_SECONDS", "databricks.apiTimeoutSeconds"),
        "api_retry_attempts": ("DATABRICKS_API_RETRY_ATTEMPTS", "databricks.apiRetryAttempts"),
        "api_retry_max_delay_seconds": ("DATABRICKS_API_RETRY_MAX_DELAY_SECONDS", "databricks.apiRetryMaxDelaySeconds"),
        "sql_wait_timeout_seconds": ("DATABRICKS_SQL_WAIT_TIMEOUT_SECONDS", "databricks.sqlWaitTimeoutSeconds"),
        "sql_poll_interval_seconds": ("DATABRICKS_SQL_POLL_INTERVAL_SECONDS", "databricks.sqlPollIntervalSeconds"),
        "sql_row_limit": ("DATABRICKS_SQL_ROW_LIMIT", "databricks.sqlRowLimit"),
        "sql_byte_limit": ("DATABRICKS_SQL_BYTE_LIMIT", "databricks.sqlByteLimit"),
    }
    for attribute, (env_name, config_path) in settings.items():
        setattr(
            args,
            attribute,
            _positive_setting(getattr(args, attribute), env_name, config, config_path),
        )
    return args


def main() -> None:
    args = parse_args()
    token = azure_cli_token()
    client_options = {
        "api_timeout_seconds": args.api_timeout_seconds,
        "api_retry_attempts": args.api_retry_attempts,
        "api_retry_max_delay_seconds": args.api_retry_max_delay_seconds,
        "sql_wait_timeout_seconds": args.sql_wait_timeout_seconds,
        "sql_poll_interval_seconds": args.sql_poll_interval_seconds,
        "sql_row_limit": args.sql_row_limit,
        "sql_byte_limit": args.sql_byte_limit,
    }
    source = DatabricksClient(args.source_host, token, **client_options)
    target = DatabricksClient(args.target_host, token, **client_options)
    source_state = source.request(
        "GET", f"/api/2.0/sql/warehouses/{args.source_warehouse_id}"
    )["state"]
    target_state = target.request(
        "GET", f"/api/2.0/sql/warehouses/{args.target_warehouse_id}"
    )["state"]
    source_catalogs = {
        item["name"]
        for item in page_all(source, "/api/2.1/unity-catalog/catalogs", "catalogs")
    }
    target_catalogs = {
        item["name"]
        for item in page_all(target, "/api/2.1/unity-catalog/catalogs", "catalogs")
    }
    if args.source_catalog not in source_catalogs:
        raise RuntimeError(f"Source catalog {args.source_catalog!r} does not exist.")
    if args.target_catalog not in target_catalogs:
        raise RuntimeError(f"Target catalog {args.target_catalog!r} does not exist.")

    objects = inventory(source, args.source_catalog)
    table_count = sum(len(item["tables"]) for item in objects)
    total_rows = 0
    print(f"Copying {len(objects)} schema(s) and {table_count} managed table(s).")
    try:
        for item in objects:
            schema = item["schema"]
            target_schema = qualified(args.target_catalog, schema["name"])
            execute_sql(
                target,
                args.target_warehouse_id,
                f"CREATE SCHEMA IF NOT EXISTS {target_schema}",
            )
            if schema.get("comment") is not None:
                execute_sql(
                    target,
                    args.target_warehouse_id,
                    f"COMMENT ON SCHEMA {target_schema} IS {sql_string(schema['comment'])}",
                )
            for table in item["tables"]:
                rows = copy_table(
                    source,
                    target,
                    args.source_warehouse_id,
                    args.target_warehouse_id,
                    args.source_catalog,
                    args.target_catalog,
                    schema["name"],
                    table,
                    args.batch_size,
                )
                total_rows += rows
                print(f"  {schema['name']}.{table['name']}: {rows} rows verified")
    finally:
        stop_if_previously_stopped(source, args.source_warehouse_id, source_state)
        stop_if_previously_stopped(target, args.target_warehouse_id, target_state)
    print(f"Replication complete: {table_count} table(s), {total_rows} row(s) verified.")


if __name__ == "__main__":
    main()