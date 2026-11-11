output "generated_agent_config_path" {
  description = "Generated agent configuration JSON consumed by the provisioning script."
  value       = local_file.agent_config.filename
}

output "provision_script_path" {
  description = "Provisioning script path used for create/update."
  value       = "${path.module}/../scripts/provision_agent.py"
}

output "manual_provision_command" {
  description = "Equivalent manual command for CI/CD or notebook steps."
  value       = "${var.python_executable} ${path.module}/../scripts/provision_agent.py --config ${local_file.agent_config.filename}"
}
