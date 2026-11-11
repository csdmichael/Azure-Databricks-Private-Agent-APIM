variable "environment_name" {
  description = "Environment label used in generated file names (for example dev, test, prod)."
  type        = string
  default     = "dev"
}

variable "project_endpoint" {
  description = "Microsoft Foundry project endpoint URL."
  type        = string
}

variable "agent_name" {
  description = "Foundry prompt agent name."
  type        = string
}

variable "version_description" {
  description = "Optional immutable description for the created agent version."
  type        = string
  default     = ""
}

variable "model_deployment_name" {
  description = "Model deployment name used by the prompt agent."
  type        = string
}

variable "instructions" {
  description = "Prompt-agent instructions."
  type        = string
}

variable "tools_json" {
  description = "JSON array for definition.tools (for example MCP tools, Azure AI Search, function tools)."
  type        = string
  default     = "[]"

  validation {
    condition     = can(jsondecode(var.tools_json))
    error_message = "tools_json must be valid JSON."
  }
}

variable "knowledge_sources_json" {
  description = "JSON array for definition.knowledge_sources."
  type        = string
  default     = "[]"

  validation {
    condition     = can(jsondecode(var.knowledge_sources_json))
    error_message = "knowledge_sources_json must be valid JSON."
  }
}

variable "skills_json" {
  description = "JSON array for definition.skills."
  type        = string
  default     = "[]"

  validation {
    condition     = can(jsondecode(var.skills_json))
    error_message = "skills_json must be valid JSON."
  }
}

variable "additional_definition_json" {
  description = "Optional JSON object merged into definition for advanced options (temperature, top_p, response_format, metadata, etc.)."
  type        = string
  default     = "{}"

  validation {
    condition     = can(jsondecode(var.additional_definition_json))
    error_message = "additional_definition_json must be valid JSON."
  }
}

variable "guardrails_enabled" {
  description = "When true, adds definition.rai_config from rai_config_json."
  type        = bool
  default     = false
}

variable "rai_config_json" {
  description = "JSON object for definition.rai_config (Responsible AI guardrails)."
  type        = string
  default     = "{}"

  validation {
    condition     = can(jsondecode(var.rai_config_json))
    error_message = "rai_config_json must be valid JSON."
  }
}

variable "evaluation_enabled" {
  description = "When true, runs post-deploy evaluation cases and enforces evaluation_min_pass_rate."
  type        = bool
  default     = false
}

variable "evaluation_cases_json" {
  description = "JSON array of evaluation cases: [{name,prompt,must_contain_any,must_not_contain_any}]."
  type        = string
  default     = "[]"

  validation {
    condition     = can(jsondecode(var.evaluation_cases_json))
    error_message = "evaluation_cases_json must be valid JSON."
  }
}

variable "evaluation_min_pass_rate" {
  description = "Minimum pass-rate threshold (0-1) required when evaluation_enabled is true."
  type        = number
  default     = 1.0
}

variable "evaluation_fail_on_error" {
  description = "When true, fails deployment if evaluation pass-rate is below threshold."
  type        = bool
  default     = true
}

variable "python_executable" {
  description = "Python executable used to run the provisioning script."
  type        = string
  default     = "python"
}

variable "deploy_agent" {
  description = "When true, executes the provisioning script and creates a new immutable agent version."
  type        = bool
  default     = true
}
