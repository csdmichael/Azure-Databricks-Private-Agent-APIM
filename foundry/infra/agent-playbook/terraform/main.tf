locals {
  guardrail_definition = var.guardrails_enabled ? {
    rai_config = jsondecode(var.rai_config_json)
  } : {}

  agent_definition = merge(
    {
      model             = var.model_deployment_name
      instructions      = var.instructions
      tools             = jsondecode(var.tools_json)
      skills            = jsondecode(var.skills_json)
      knowledge_sources = jsondecode(var.knowledge_sources_json)
    },
    local.guardrail_definition,
    jsondecode(var.additional_definition_json),
  )

  agent_config = {
    project_endpoint    = var.project_endpoint
    agent_name          = var.agent_name
    version_description = var.version_description
    definition          = local.agent_definition
    evaluation = {
      enabled        = var.evaluation_enabled
      min_pass_rate  = var.evaluation_min_pass_rate
      fail_on_error  = var.evaluation_fail_on_error
      cases          = jsondecode(var.evaluation_cases_json)
    }
  }

  generated_dir = "${path.module}/.generated"
}

resource "local_file" "agent_config" {
  filename = "${local.generated_dir}/agent-config.${var.environment_name}.json"
  content  = jsonencode(local.agent_config)
}

resource "null_resource" "deploy_agent" {
  count = var.deploy_agent ? 1 : 0

  triggers = {
    config_sha = sha256(local_file.agent_config.content)
    script_sha = filesha256("${path.module}/../scripts/provision_agent.py")
  }

  provisioner "local-exec" {
    interpreter = ["PowerShell", "-NoProfile", "-Command"]
    command     = "& \"${var.python_executable}\" \"${replace("${path.module}/../scripts/provision_agent.py", "/", "\\")}\" --config \"${replace(local_file.agent_config.filename, "/", "\\")}\""
  }
}
