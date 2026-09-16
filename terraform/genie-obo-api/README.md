# APIM Genie OBO API

Terraform parity module for `apim/obo.bicep`. It configures an existing Azure API Management service with the delegated-user Genie API, its named values and policies, an Application Insights logger and diagnostic, and the audit policy fragment.

## Prerequisites

- Terraform 1.5 or later
- Azure credentials available to the AzureRM and AzAPI providers
- The configured resource group, API Management service, and Application Insights component already exist
- The OBO API and connector registrations have been provisioned
- The caller can manage API Management child resources

## Configuration

Run Terraform from this directory. By default, the module reads `../../config/deployment.json`. Every value present in that file is used unless its corresponding nullable variable is set.

Two Bicep inputs are not stored in the deployment configuration and must be supplied:

- `genie_space_id`
- `api_description`

Create a local variable file from `main.tfvars.json.example` and replace the Genie space placeholder. Do not commit environment-specific variable files.

The broker URL uses `obo.brokerUrl` if that property exists; otherwise it is derived from `obo.functionName` using the same Azure Functions endpoint shape as the Bicep parameter file.

To use another configuration file, set `config_path`. Relative paths are resolved from the directory where Terraform is run.

## Validate and deploy

```powershell
terraform init
terraform fmt -check
terraform validate
terraform plan -var-file main.tfvars.json
terraform apply -var-file main.tfvars.json
```

The policy XML files are local to this module. APIM named-value placeholders such as `{{genie-obo-api-client-id}}` remain literal and are resolved by API Management.

## Resources

- 1 Application Insights logger
- 1 audit policy fragment
- 11 non-secret named values
- 1 delegated Genie API and API-level policy
- 1 API diagnostic with fixed sampling
- 4 operations and 4 operation-level policies

The module preserves the Bicep API version `2023-09-01-preview` through AzAPI resources. It does not create or modify the API Management service, Application Insights component, application registrations, or token broker.