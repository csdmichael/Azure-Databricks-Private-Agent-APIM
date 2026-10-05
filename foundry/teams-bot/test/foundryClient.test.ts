import assert from "node:assert/strict";
import test from "node:test";

import { FoundryClient } from "../src/foundryClient.js";

test("passes the delegated token only as a structured input", async () => {
  const calls: Array<{ url: string; body: unknown; authorization: string | null }> = [];
  const fetcher: typeof fetch = async (input, init) => {
    const url = String(input);
    const headers = new Headers(init?.headers);
    const body = JSON.parse(String(init?.body ?? "{}")) as unknown;
    calls.push({ url, body, authorization: headers.get("Authorization") });
    if (url.endsWith("/conversations")) {
      return new Response(JSON.stringify({ id: "conversation-1" }), { status: 200 });
    }
    return new Response(JSON.stringify({ output_text: "Grounded result" }), { status: 200 });
  };
  const credential = {
    getToken: async () => ({ token: "foundry-token", expiresOnTimestamp: Date.now() + 60_000 }),
  };
  const client = new FoundryClient(
    "https://example.services.ai.azure.com/api/projects/project",
    "agent",
    credential,
    fetcher,
  );

  const answer = await client.ask("teams-conversation", "Revenue by region", "user-token");

  assert.equal(answer, "Grounded result");
  assert.equal(calls.length, 2);
  assert.equal(calls[1].authorization, "Bearer foundry-token");
  assert.deepEqual(calls[1].body, {
    conversation: "conversation-1",
    input: "Revenue by region",
    agent_reference: { type: "agent_reference", name: "agent" },
    structured_inputs: { oboToken: "user-token" },
  });
  assert.doesNotMatch(JSON.stringify(calls[0]), /user-token/);
});
