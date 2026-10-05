import {
  CloudAdapter,
  ConfigurationBotFrameworkAuthentication,
  MemoryStorage,
  TurnContext,
} from "botbuilder";
import express from "express";

import { FoundryTeamsBot } from "./bot.js";
import { loadConfig } from "./config.js";
import { FoundryClient } from "./foundryClient.js";

const config = loadConfig();
const authentication = new ConfigurationBotFrameworkAuthentication({
  MicrosoftAppType: "SingleTenant",
  MicrosoftAppId: config.microsoftAppId,
  MicrosoftAppPassword: config.microsoftAppPassword,
  MicrosoftAppTenantId: config.microsoftAppTenantId,
});
const adapter = new CloudAdapter(authentication);
adapter.onTurnError = async (context: TurnContext, error: Error) => {
  console.error("Unhandled bot error", error);
  await context.sendActivity("The request failed. Try again or contact the service owner with the current time.");
};

const bot = new FoundryTeamsBot(
  new MemoryStorage(),
  config.oauthConnectionName,
  new FoundryClient(config.foundryProjectEndpoint, config.foundryAgentName),
);
const app = express();
app.use(express.json({ limit: "1mb" }));
app.get("/health", (_request, response) => response.status(200).json({ status: "ok" }));
app.post("/api/messages", (request, response) => {
  void adapter.process(request, response, (context) => bot.run(context));
});
app.listen(config.port, () => {
  console.log(`Foundry Teams bot listening on port ${config.port}`);
});
