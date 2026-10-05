import { DefaultAzureCredential, type TokenCredential } from "@azure/identity";

interface FoundryResponse {
  output_text?: string;
  output?: Array<{
    type?: string;
    content?: Array<{ type?: string; text?: string }>;
  }>;
}

export class FoundryClient {
  private readonly credential: TokenCredential;
  private readonly conversations = new Map<string, string>();

  constructor(
    private readonly projectEndpoint: string,
    private readonly agentName: string,
    credential: TokenCredential = new DefaultAzureCredential(),
    private readonly fetcher: typeof fetch = fetch,
  ) {
    this.credential = credential;
  }

  async ask(conversationKey: string, prompt: string, delegatedToken: string): Promise<string> {
    if (!prompt.trim()) {
      throw new Error("A non-empty prompt is required");
    }
    if (!delegatedToken.trim()) {
      throw new Error("A delegated user token is required");
    }

    let conversationId = this.conversations.get(conversationKey);
    if (!conversationId) {
      const created = await this.request<{ id: string }>("/openai/v1/conversations", {
        method: "POST",
        body: JSON.stringify({}),
      });
      conversationId = created.id;
      this.conversations.set(conversationKey, conversationId);
    }

    const response = await this.request<FoundryResponse>("/openai/v1/responses", {
      method: "POST",
      body: JSON.stringify({
        conversation: conversationId,
        input: prompt,
        agent_reference: { type: "agent_reference", name: this.agentName },
        structured_inputs: { oboToken: delegatedToken },
      }),
    });
    const text =
      response.output_text ??
      response.output
        ?.flatMap((item) => item.content ?? [])
        .find((content) => content.type === "output_text")
        ?.text;
    if (!text) {
      throw new Error("Foundry completed without a text response");
    }
    return text;
  }

  private async request<T>(path: string, init: RequestInit): Promise<T> {
    const accessToken = await this.credential.getToken("https://ai.azure.com/.default");
    if (!accessToken) {
      throw new Error("Unable to acquire a Microsoft Foundry access token");
    }
    const response = await this.fetcher(`${this.projectEndpoint}${path}`, {
      ...init,
      headers: {
        Authorization: `Bearer ${accessToken.token}`,
        "Content-Type": "application/json",
        ...init.headers,
      },
    });
    if (!response.ok) {
      const detail = (await response.text()).slice(0, 1000);
      throw new Error(`Foundry request failed with HTTP ${response.status}: ${detail}`);
    }
    return (await response.json()) as T;
  }
}
