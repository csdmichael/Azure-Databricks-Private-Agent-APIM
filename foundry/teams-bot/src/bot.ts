import {
  MemoryStorage,
  StatePropertyAccessor,
  TeamsActivityHandler,
  TurnContext,
  UserState,
} from "botbuilder";
import {
  ComponentDialog,
  DialogSet,
  DialogState,
  DialogTurnStatus,
  OAuthPrompt,
  WaterfallDialog,
  WaterfallStepContext,
} from "botbuilder-dialogs";

import { FoundryClient } from "./foundryClient.js";

const OAUTH_PROMPT = "OAuthPrompt";
const MAIN_FLOW = "MainFlow";

class MainDialog extends ComponentDialog {
  constructor(connectionName: string, private readonly foundry: FoundryClient) {
    super("MainDialog");
    this.addDialog(
      new OAuthPrompt(OAUTH_PROMPT, {
        connectionName,
        text: "Sign in with Microsoft Entra ID to use your Databricks permissions.",
        title: "Sign in",
        timeout: 300_000,
      }),
    );
    this.addDialog(
      new WaterfallDialog(MAIN_FLOW, [
        async (step: WaterfallStepContext) => step.beginDialog(OAUTH_PROMPT),
        async (step: WaterfallStepContext) => {
          const token = step.result?.token as string | undefined;
          if (!token) {
            await step.context.sendActivity("Sign-in did not complete. Send your question again to retry.");
            return step.endDialog();
          }
          const prompt = step.context.activity.text?.trim();
          if (!prompt) {
            await step.context.sendActivity("Send a data question after signing in.");
            return step.endDialog();
          }
          await step.context.sendActivity({ type: "typing" });
          const answer = await this.foundry.ask(
            step.context.activity.conversation.id,
            prompt,
            token,
          );
          await step.context.sendActivity(answer);
          return step.endDialog();
        },
      ]),
    );
    this.initialDialogId = MAIN_FLOW;
  }
}

export class FoundryTeamsBot extends TeamsActivityHandler {
  private readonly dialogs: DialogSet;
  private readonly dialogState: StatePropertyAccessor<DialogState>;
  private readonly userState: UserState;

  constructor(
    storage: MemoryStorage,
    connectionName: string,
    foundry: FoundryClient,
  ) {
    super();
    this.userState = new UserState(storage);
    this.dialogState = this.userState.createProperty<DialogState>("DialogState");
    this.dialogs = new DialogSet(this.dialogState);
    this.dialogs.add(new MainDialog(connectionName, foundry));

    this.onMessage(async (context, next) => {
      await this.runDialog(context);
      await next();
    });
    this.onTokenResponseEvent(async (context, next) => {
      await this.runDialog(context);
      await next();
    });
  }

  protected override async handleTeamsSigninVerifyState(context: TurnContext): Promise<void> {
    await this.runDialog(context);
  }

  protected override async handleTeamsSigninTokenExchange(context: TurnContext): Promise<void> {
    await this.runDialog(context);
  }

  private async runDialog(context: TurnContext): Promise<void> {
    const dialogContext = await this.dialogs.createContext(context);
    const result = await dialogContext.continueDialog();
    if (result.status === DialogTurnStatus.empty) {
      await dialogContext.beginDialog("MainDialog");
    }
    await this.userState.saveChanges(context);
  }
}
