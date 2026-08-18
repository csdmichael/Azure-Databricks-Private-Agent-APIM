"""Lists the tools advertised by an APIM MCP server (streamable HTTP transport).

Used to confirm the exact tool names and input schemas before writing agent
instructions. Reads the APIM subscription key from APIM_SUBSCRIPTION_KEY.
"""

import json
import os
import sys
import urllib.request

MCP_URL = sys.argv[1] if len(sys.argv) > 1 else "https://ai-gateway-apim-poc-my.azure-api.net/databricks-genie-mcp/mcp"
KEY = os.environ["APIM_SUBSCRIPTION_KEY"]

HEADERS = {
    "Content-Type": "application/json",
    "Accept": "application/json, text/event-stream",
    "Ocp-Apim-Subscription-Key": KEY,
}


def post(payload, session=None):
    headers = dict(HEADERS)
    if session:
        headers["Mcp-Session-Id"] = session
    request = urllib.request.Request(
        MCP_URL, data=json.dumps(payload).encode(), headers=headers, method="POST"
    )
    with urllib.request.urlopen(request) as response:
        return response.headers.get("Mcp-Session-Id"), response.read().decode()


def parse(raw):
    for line in raw.splitlines():
        if line.startswith("data:"):
            return json.loads(line[5:].strip())
    return json.loads(raw) if raw.strip() else {}


session, raw = post(
    {
        "jsonrpc": "2.0",
        "id": 1,
        "method": "initialize",
        "params": {
            "protocolVersion": "2024-11-05",
            "capabilities": {},
            "clientInfo": {"name": "apim-probe", "version": "1.0"},
        },
    }
)
print("initialize ->", json.dumps(parse(raw))[:400])

post({"jsonrpc": "2.0", "method": "notifications/initialized"}, session)
_, raw = post({"jsonrpc": "2.0", "id": 2, "method": "tools/list"}, session)
print(json.dumps(parse(raw), indent=2)[:6000])
