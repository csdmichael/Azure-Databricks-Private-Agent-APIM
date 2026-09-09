# Screenshot capture list

Each image below is referenced by
[../genie-mcp-copilot-studio-setup.md](../genie-mcp-copilot-studio-setup.md).
Capture at 1920x1080 or wider, light theme, and redact tenant names, GUIDs,
subscription keys, and workspace IDs before committing.

| File | Where to capture | What must be visible |
|---|---|---|
| `01-environment-details.png` | Power Platform admin center → Environments → *environment* | Region, State, Type, and **Managed environments: Yes** |
| `02-subnet-delegation.png` | Azure portal → Power Platform VNet → Subnets → *subnet* | **Delegate subnet to a service** = `Microsoft.PowerPlatform/enterprisePolicies`, and the address range |
| `03-vnet-peerings.png` | Azure portal → APIM VNet → Peerings | All peerings showing **Connected** and **Fully in sync** |
| `04-private-dns.png` | Azure portal → `privatelink.azure-api.net` → Overview | Gateway A record with its private IP, and the Virtual network links count |
| `05-enterprise-policy.png` | Azure portal → enterprise policy → Overview | **Kind: NetworkInjection**, location, and both delegated subnets |
| `06-subnet-injection-history.png` | Power Platform admin center → Environments → *environment* → History | The subnet injection operation row with **Succeeded** |
| `07-apim-mcp-server.png` | Azure portal → APIM → APIs → MCP servers | The Genie MCP server row with its `/mcp` URL |
| `08-copilot-studio-add-mcp.png` | Copilot Studio → agent → Tools → Add a tool → New tool | **Model Context Protocol** option selected |
| `09-copilot-studio-connection.png` | Copilot Studio → MCP connection dialog | Server URL and **API key** auth with header `Ocp-Apim-Subscription-Key` (key blurred) |
| `10-agent-test-genie.png` | Copilot Studio → Test pane | A Genie answer with returned rows and the slide plan |
| `11-m365-copilot-result.png` | Microsoft 365 Copilot chat | The agent responding with Databricks-sourced analysis and the generated deck |

## Redaction checklist

- Subscription keys and any `Ocp-Apim-Subscription-Key` value
- Bearer tokens in developer-tools panes
- Tenant domain, subscription GUID, and Databricks workspace ID where not needed
- User principal names in the top-right account flyout
