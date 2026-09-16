# APIM Databricks APIs

Terraform parity module for `apim/main.bicep`. It configures an existing Azure API Management service with the Databricks SQL and Genie APIs, their named values, operations, policies, product links, and subscription.

## Prerequisites

- Terraform 1.5 or later
- Azure credentials available to the AzureRM and AzAPI providers
- The configured resource group and API Management service already exist
- The caller can manage API Management child resources

## Configuration

Run Terraform from this directory. By default, the module reads `../../config/deployment.json`. Every value present in that file is used unless its corresponding nullable variable is set.

`genie_space_id` has no value in the deployment configuration and is required. Create a local variable file from `main.tfvars.json.example` and replace its placeholder. Do not commit environment-specific variable files.

To use another configuration file, set `config_path`. Relative paths are resolved from the directory where Terraform is run.

## Validate and deploy

```powershell
terraform init
terraform fmt -check
terraform validate
terraform plan -var-file main.tfvars.json
terraform apply -var-file main.tfvars.json
```

The policy XML files are local to this module. APIM named-value placeholders such as `{{databricks-workspace-url}}` remain literal and are resolved by API Management.

## Resources

- 10 non-secret named values
- 2 APIs and their API-level policies
- 6 operations and their operation-level policies
- 1 published product and 2 API links
- 1 active product subscription

The module preserves the Bicep API version `2023-09-01-preview` through AzAPI resources. It does not create or modify the API Management service itself.