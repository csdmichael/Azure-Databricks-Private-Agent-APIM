export interface BotConfig {
  microsoftAppId: string;
  microsoftAppPassword: string;
  microsoftAppTenantId: string;
  oauthConnectionName: string;
  foundryProjectEndpoint: string;
  foundryAgentName: string;
  port: number;
}

function required(name: string): string {
  const value = process.env[name];
  if (!value) {
    throw new Error(`Required environment variable ${name} is not set`);
  }
  return value;
}

export function loadConfig(): BotConfig {
  const port = Number(process.env.PORT ?? "3978");
  if (!Number.isInteger(port) || port < 1 || port > 65535) {
    throw new Error("PORT must be an integer from 1 through 65535");
  }

  return {
    microsoftAppId: required("MicrosoftAppId"),
    microsoftAppPassword: required("MicrosoftAppPassword"),
    microsoftAppTenantId: required("MicrosoftAppTenantId"),
    oauthConnectionName: required("OAUTH_CONNECTION_NAME"),
    foundryProjectEndpoint: required("FOUNDRY_PROJECT_ENDPOINT").replace(/\/+$/, ""),
    foundryAgentName: required("FOUNDRY_AGENT_NAME"),
    port,
  };
}
