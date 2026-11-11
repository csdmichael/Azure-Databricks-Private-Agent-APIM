# Bicep Foundry Agent Playbook

Generic, reusable Bicep playbook for deploying a **Foundry prompt agent version** from parameterized definition inputs.

This module is intentionally environment-agnostic. Pass instructions, tools, knowledge sources, skills, and optional advanced definition fields through parameters.

Optional controls:

- Guardrails via `enableGuardrails` + `raiConfig`
- Evaluation gates via `enableEvaluation`, `evaluationCases`, and `evaluationMinPassRate`

## Files

- `main.bicep`: Runs an Azure deployment script that creates a new immutable agent version.
- `main.bicepparam.example`: Example values using this repository's Databricks Genie MCP route.

## Prerequisites

- A user-assigned managed identity with access to the target Foundry project.
- The identity resource ID passed as `deploymentIdentityResourceId`.

## Usage

```powershell
Set-Location .\foundry\infra\agent-playbook\bicep
Copy-Item .\main.bicepparam.example .\main.bicepparam
# Edit main.bicepparam with your environment values
az deployment group create `
  --resource-group <resource-group> `
  --template-file .\main.bicep `
  --parameters .\main.bicepparam
```
