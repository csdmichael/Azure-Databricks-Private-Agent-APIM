# Copilot tools

## Databricks Genie MCP

Upload `Databricks-Genie-MCP.zip` in the Microsoft 365 admin center under
**Agents > Tools > Registry**.

The package registers this streamable HTTP MCP endpoint:

```text
https://caldova-apim-westus.azure-api.net/dbx-native-genie-mcp/api/2.0/mcp/genie/01f1abe9e51e19ddbb15297aee9a5850
```

The current package intentionally omits `authorization` so its manifest and
registry workflow can be validated before OAuth is provisioned. It is not ready
for tool execution:

- The MCP endpoint requires a delegated Databricks bearer token.
- The APIM service accepts private network traffic only.
- Before use, add an `OAuthPluginVault` authorization with the real Enterprise
  Token Store auth configuration ID and verify execution from the `Caldova
  Private` Power Platform Managed Environment.

Do not add client secrets or access tokens to this folder or ZIP package.

### Registry validation

1. Open the Microsoft 365 admin center.
2. Go to **Agents > Tools > Registry** and select **Upload**.
3. Upload `Databricks-Genie-MCP.zip`.
4. Review the detected `Databricks Genie MCP` connector and scope it only to
   test users until authentication and connectivity validation pass.

### Caldova Private onboarding

1. Open Copilot Studio and select the **Caldova Private** Managed Environment.
2. Open the target agent and go to **Tools > Add a tool**.
3. Select the approved `Databricks Genie MCP` registry tool.
4. If the registry tool isn't available yet, use **New tool > Model Context
   Protocol** and enter the MCP endpoint shown above.
5. For this pre-auth validation package, leave authentication unconfigured.
   The server can be registered, but tool discovery or execution can return
   `401 Unauthorized`.
6. Confirm that requests from the environment resolve and reach the private
   APIM endpoint before adding delegated OAuth.

For production use, create a dedicated Entra OAuth client, register
`https://teams.microsoft.com/api/platform/v1.0/oAuthRedirect`, create its
Microsoft Enterprise Token Store auth configuration, and add its generated ID
to `agentConnectors[0].toolSource.remoteMcpServer.authorization`:

```json
{
  "type": "OAuthPluginVault",
  "referenceId": "<enterprise-token-store-auth-config-id>"
}
```

The placeholder above is documentation only and is not present in the upload
package.
