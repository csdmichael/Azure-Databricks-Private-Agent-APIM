# Foundry logging and agent tracing

This deployment enables observability for both Foundry projects:

| Account | Project |
| --- | --- |
| `foundry-myaacoub` | `proj-default` |
| `foundry-myaacoub-private` | `sales-poc` |

It reuses `caldova-genie-obo-insights` and its
`caldova-apim-logs-westus` Log Analytics workspace. Shared account-level
Application Insights connections activate server-side prompt-agent tracing for
both projects. Project diagnostic settings send `allLogs` and `AllMetrics` to
the same workspace. Each project identity receives Log Analytics Reader and
Privileged Monitoring Data Reader scoped only to the Application Insights
component.

The Python API also exports OpenTelemetry spans through the project connection.
It records operation metadata and propagates W3C trace context, but does not
record prompts, responses, tool arguments, baggage, or binary file data.

## Deploy

```powershell
az deployment group what-if `
  --subscription cf824570-a8ba-497a-a184-0a52f1830aa9 `
  --resource-group m365-myaacoub `
  --template-file bicep/foundry-observability/main.bicep

az deployment group create `
  --subscription cf824570-a8ba-497a-a184-0a52f1830aa9 `
  --resource-group m365-myaacoub `
  --name foundry-observability `
  --template-file bicep/foundry-observability/main.bicep
```

## Verify

The Foundry projects must each expose one `AppInsights` connection targeting
`caldova-genie-obo-insights`. Their project diagnostic settings must target
`caldova-apim-logs-westus` with `allLogs` and `AllMetrics` enabled.

After invoking an agent in each project, this Application Insights query should
return successful `invoke_agent` and `chat` spans:

```kql
dependencies
| where timestamp > ago(1h)
| where isnotempty(customDimensions["gen_ai.operation.name"])
| extend
    agentId = tostring(customDimensions["gen_ai.agent.id"]),
    operation = tostring(customDimensions["gen_ai.operation.name"])
| where agentId in ("test-agent:1", "semiconductor-sales:5")
| project timestamp, operation_Id, duration, success, agentId, operation
| order by timestamp desc
```

This Log Analytics query verifies account diagnostic ingestion:

```kql
AzureDiagnostics
| where TimeGenerated > ago(1h)
| extend foundryResourceId = tolower(_ResourceId)
| where foundryResourceId contains "/accounts/foundry-myaacoub"
| summarize count(), lastSeen=max(TimeGenerated), categories=make_set(Category)
  by foundryResourceId
```