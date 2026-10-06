# Copilot tools

## Databricks Genie MCP

Upload `Databricks-Genie-MCP.zip` in the Microsoft 365 admin center under
**Agents > Tools > Registry**.

![Databricks Genie MCP package contents](Screenshots/01.%20Package%20Contents.png)

The package registers this streamable HTTP MCP endpoint:

```text
https://caldova-apim-westus.azure-api.net/dbx-native-genie-mcp/api/2.0/mcp/genie/01f1abe9e51e19ddbb15297aee9a5850
```

The current package intentionally omits end-user `authorization`. The private
APIM route authenticates to Databricks with APIM's managed identity:

- The APIM service accepts private network traffic only.
- The native MCP API policy rate-limits requests, obtains a Databricks access
  token for APIM's managed identity, and replaces the inbound authorization
  header before forwarding to Databricks.
- All users share the backend identity and its Databricks permissions. Use this
  mode only for approved shared-identity scenarios; use the OBO design when
  Databricks must enforce each user's permissions.

Do not add client secrets or access tokens to this folder or ZIP package.

### Registry validation

1. Open the Microsoft 365 admin center.
2. Go to **Agents > Tools > Registry** and select **Upload**.
3. Upload `Databricks-Genie-MCP.zip`.

   ![Upload the Databricks Genie MCP package](Screenshots/02.%20Package%20Upload.png)

4. Review the detected `Databricks Genie MCP` connector and scope it only to
   test users until authentication and connectivity validation pass.

   ![Select test users for the Databricks Genie MCP tool](Screenshots/03.%20Select%20Users%20for%20Tool.png)

5. Review the package and selected users, then finish the upload.

   ![Review the Databricks Genie MCP registry upload](Screenshots/04.%20Review%20and%20finish.png)

6. Confirm the tool appears in the registry before opening Copilot Studio.

   ![Databricks Genie MCP tool uploaded to the registry](Screenshots/05.%20Tool%20uploaded.png)

### Caldova Private onboarding

1. Open Copilot Studio and select the **Caldova Private** Managed Environment.
2. Open the target agent and go to **Tools > Add a tool**.
3. Select the approved `Databricks Genie MCP` registry tool.
4. If the registry tool isn't available yet, use **New tool > Model Context
   Protocol** and enter the MCP endpoint shown above.

   ![Connect a Copilot agent to the native Genie MCP server through APIM](Screenshots/MCP-01.%20Connect%20in%20Copilot%20Studio.png)

5. Leave client authentication set to **None**. The environment reaches APIM
   privately, and APIM authenticates to Databricks with its managed identity.
6. Confirm that requests from the environment resolve and reach the private
   APIM endpoint, that MCP tools load, and that a grounded Genie prompt succeeds.

The APIM authentication and rate-limit configuration is maintained in
[`../apim/policies/dbx-native-genie-mcp-policy.xml`](../apim/policies/dbx-native-genie-mcp-policy.xml).
The tool should discover both the native query and polling operations:

![Native Genie MCP tools loaded in Copilot Studio](Screenshots/MCP-02.%20Native%20Genie%20MCP%20tools%20loaded.png)

### Live validation

The published `Dbx Agent - Native Genie MCP` agent was validated in the `Caldova
Private` environment with:

```text
What were total 2025 sales by region? Include units, filters, and the source.
```

The agent invoked the native query operation, polled the message to completion,
and returned grounded regional totals with the calendar-year filter, measure,
Unity Catalog table, and Databricks Genie source.

![Successful grounded query through the native Genie MCP server](Screenshots/MCP-03.%20Native%20Genie%20MCP%20successful%20query.png)

For per-user production authorization, create a dedicated Entra OAuth client, register
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
