targetScope = 'resourceGroup'

@description('Azure region for the deployment script.')
param location string = resourceGroup().location

@description('Deployment script resource name.')
param deploymentScriptName string = 'foundry-agent-deploy'

@description('User-assigned managed identity resource ID used by the deployment script.')
param deploymentIdentityResourceId string

@description('Microsoft Foundry project endpoint URL.')
param projectEndpoint string

@description('Foundry prompt agent name.')
param agentName string

@description('Optional immutable description for the created agent version.')
param versionDescription string = ''

@description('Model deployment name used by the prompt agent.')
param modelDeploymentName string

@description('Prompt-agent instructions.')
param instructions string

@description('Tool definitions for definition.tools.')
param tools array = []

@description('Knowledge source definitions for definition.knowledge_sources.')
param knowledgeSources array = []

@description('Skill references for definition.skills.')
param skills array = []

@description('When true, adds definition.rai_config from raiConfig.')
param enableGuardrails bool = false

@description('Responsible AI guardrail configuration for definition.rai_config.')
param raiConfig object = {}

@description('Optional advanced definition properties to merge (for example temperature, top_p, response_format, metadata).')
param additionalDefinition object = {}

@description('When true, runs post-deploy evaluation cases and enforces evaluationMinPassRate.')
param enableEvaluation bool = false

@description('Evaluation cases: [{name,prompt,must_contain_any,must_not_contain_any}].')
param evaluationCases array = []

@minValue(0)
@maxValue(100)
@description('Minimum evaluation pass-rate threshold as integer percent (0-100).')
param evaluationMinPassRatePercent int = 100

@description('When true, fails deployment if evaluation pass-rate is below threshold.')
param evaluationFailOnError bool = true

@description('Script timeout in ISO-8601 duration format.')
param timeout string = 'PT30M'

@description('How long to keep deployment script resources after completion.')
param retentionInterval string = 'P1D'

@allowed([
  'Always'
  'OnSuccess'
  'OnExpiration'
])
@description('Cleanup behavior for deployment script resources.')
param cleanupPreference string = 'OnSuccess'

@description('Change this value to force a rerun without changing inputs.')
param forceUpdateTag string = utcNow('u')

var baseDefinition = {
  model: modelDeploymentName
  instructions: instructions
  tools: tools
  skills: skills
  knowledge_sources: knowledgeSources
}

var guardrailDefinition = enableGuardrails
  ? {
      rai_config: raiConfig
    }
  : {}

var mergedDefinition = union(baseDefinition, guardrailDefinition, additionalDefinition)

var agentConfig = {
  project_endpoint: projectEndpoint
  agent_name: agentName
  version_description: versionDescription
  definition: mergedDefinition
  evaluation: {
    enabled: enableEvaluation
    min_pass_rate_percent: evaluationMinPassRatePercent
    fail_on_error: evaluationFailOnError
    cases: evaluationCases
  }
}

resource deployAgent 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: deploymentScriptName
  location: location
  kind: 'AzureCLI'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${deploymentIdentityResourceId}': {}
    }
  }
  properties: {
    azCliVersion: '2.63.0'
    timeout: timeout
    retentionInterval: retentionInterval
    cleanupPreference: cleanupPreference
    forceUpdateTag: forceUpdateTag
    environmentVariables: [
      {
        name: 'AGENT_CONFIG_JSON'
        value: string(agentConfig)
      }
    ]
    scriptContent: '''
set -euo pipefail
python -m pip install --quiet --disable-pip-version-check "azure-ai-projects>=2.0.0b4,<3" "azure-identity>=1.25.1,<2"
python - <<'PY'
import json
import os

from azure.ai.projects import AIProjectClient
from azure.ai.projects.models import PromptAgentDefinition
from azure.identity import DefaultAzureCredential

config = json.loads(os.environ["AGENT_CONFIG_JSON"])
definition = PromptAgentDefinition(**config["definition"])
client = AIProjectClient(
    endpoint=config["project_endpoint"],
    credential=DefaultAzureCredential(),
)
kwargs = {}
if config.get("version_description"):
    kwargs["description"] = config["version_description"]
agent = client.agents.create_version(
    agent_name=config["agent_name"],
    definition=definition,
    **kwargs,
)

evaluation = config.get("evaluation") or {}
evaluation_result = None
if evaluation.get("enabled"):
    cases = evaluation.get("cases") or []
    if not isinstance(cases, list) or len(cases) == 0:
        raise ValueError("evaluation.cases must contain at least one case when evaluation is enabled.")

    if "min_pass_rate" in evaluation:
        min_pass_rate = float(evaluation.get("min_pass_rate", 1.0))
    else:
        min_pass_rate = float(evaluation.get("min_pass_rate_percent", 100)) / 100.0
    fail_on_error = bool(evaluation.get("fail_on_error", True))
    openai = client.get_openai_client(agent_name=agent.name)

    results = []
    passed = 0
    for index, case in enumerate(cases, start=1):
        if not isinstance(case, dict):
            raise ValueError(f"evaluation.cases[{index - 1}] must be an object.")
        prompt = (case.get("prompt") or "").strip()
        if not prompt:
            raise ValueError(f"evaluation.cases[{index - 1}].prompt must be a non-empty string.")
        case_name = (case.get("name") or f"case-{index}").strip()
        must_contain_any = case.get("must_contain_any") or []
        must_not_contain_any = case.get("must_not_contain_any") or []
        if not isinstance(must_contain_any, list) or not all(isinstance(x, str) for x in must_contain_any):
            raise ValueError(f"evaluation.cases[{index - 1}].must_contain_any must be a string array.")
        if not isinstance(must_not_contain_any, list) or not all(isinstance(x, str) for x in must_not_contain_any):
            raise ValueError(f"evaluation.cases[{index - 1}].must_not_contain_any must be a string array.")

        conversation = openai.conversations.create()
        try:
            response = openai.responses.create(
                conversation=conversation.id,
                input=prompt,
            )
            output_text = (response.output_text or "").strip()
        finally:
            openai.conversations.delete(conversation.id)

        lower_output = output_text.lower()
        has_required = True if not must_contain_any else any(token.lower() in lower_output for token in must_contain_any)
        has_forbidden = any(token.lower() in lower_output for token in must_not_contain_any)
        case_passed = has_required and not has_forbidden
        if case_passed:
            passed += 1
        results.append(
            {
                "name": case_name,
                "passed": case_passed,
                "prompt": prompt,
                "must_contain_any": must_contain_any,
                "must_not_contain_any": must_not_contain_any,
                "response_preview": output_text[:500],
            }
        )

    total = len(results)
    pass_rate = float(passed) / float(total)
    evaluation_result = {
        "enabled": True,
        "total_cases": total,
        "passed_cases": passed,
        "pass_rate": pass_rate,
        "min_pass_rate": min_pass_rate,
        "cases": results,
    }
    if fail_on_error and pass_rate < min_pass_rate:
        raise RuntimeError(f"Evaluation gate failed: pass_rate={pass_rate:.2f} required>={min_pass_rate:.2f}")

result = {
    "agent_name": agent.name,
    "agent_version": agent.version,
    "project_endpoint": config["project_endpoint"],
    "evaluation": evaluation_result,
}
with open(os.environ["AZ_SCRIPTS_OUTPUT_PATH"], "w", encoding="utf-8") as handle:
    json.dump(result, handle)
PY
'''
  }
}

output scriptResourceId string = deployAgent.id
output agentDeploymentResult object = deployAgent.properties.outputs
