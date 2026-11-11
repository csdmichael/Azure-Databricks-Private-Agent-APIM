# Terraform Foundry Agent Playbook

Generic, reusable Terraform playbook for deploying a **Foundry prompt agent version** from Git-backed configuration.

This playbook does not hard-code the agent implementation. You pass instructions, tools, knowledge sources, skills, and optional advanced definition properties as parameters.

Optional controls:

- Guardrails via `guardrails_enabled` + `rai_config_json`
- Evaluation gates via `evaluation_enabled`, `evaluation_cases_json`, and `evaluation_min_pass_rate`

## Files

- `main.tf`: Builds the agent definition payload, writes generated config, runs the provisioning script.
- `variables.tf`: Generic inputs for any prompt agent.
- `outputs.tf`: Generated config path and reproducible command output.
- `terraform.tfvars.example`: Example values using this repository's Databricks Genie MCP route.
- `../scripts/provision_agent.py`: Config-driven agent version creator used by Terraform and CI/CD.

## Usage

```powershell
Set-Location .\foundry\infra\agent-playbook\terraform
Copy-Item .\terraform.tfvars.example .\terraform.tfvars
# Edit terraform.tfvars with your environment values
terraform init
terraform apply
```

To generate config without creating a new agent version:

```powershell
terraform apply -var "deploy_agent=false"
```

Then run the command from `manual_provision_command` output in your pipeline stage.

## Evaluation case shape

`evaluation_cases_json` accepts:

```json
[
  {
    "name": "scope-check",
    "prompt": "What can you help me analyze?",
    "must_contain_any": ["analyze", "data", "query"],
    "must_not_contain_any": ["I cannot help", "unknown"]
  }
]
```
