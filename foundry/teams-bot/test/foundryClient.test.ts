import assert from "node:assert/strict";
import test from "node:test";

import { FoundryClient } from "../src/foundryClient.js";

test("invokes Foundry with the delegated user token", async () => {
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
  const client = new FoundryClient(
    "https://example.services.ai.azure.com/api/projects/project",
    "agent",
    fetcher,
  );

  const answer = await client.ask("teams-conversation", "Revenue by region", "user-token");

  assert.equal(answer, "Grounded result");
  assert.equal(calls.length, 2);
  assert.equal(calls[0].authorization, "Bearer user-token");
  assert.equal(calls[1].authorization, "Bearer user-token");
  assert.deepEqual(calls[1].body, {
    conversation: "conversation-1",
    input: "Revenue by region",
    agent_reference: { type: "agent_reference", name: "agent" },
  });

  test("surfaces OAuth consent and resumes the previous response", async () => {
    const responseBodies: unknown[] = [];
    let responseNumber = 0;
    const fetcher: typeof fetch = async (input, init) => {
      const url = String(input);
      if (url.endsWith("/conversations")) {
        return new Response(JSON.stringify({ id: "conversation-2" }), { status: 200 });
      }
      responseBodies.push(JSON.parse(String(init?.body ?? "{}")) as unknown);
      responseNumber += 1;
      if (responseNumber === 1) {
        return new Response(
          JSON.stringify({
            id: "response-1",
            output: [
              {
                type: "oauth_consent_request",
                consent_link: "https://consent.example.test/login",
              },
            ],
          }),
          { status: 200 },
        );
      }
      return new Response(JSON.stringify({ output_text: "Authorized result" }), { status: 200 });
    };
    const client = new FoundryClient(
      "https://example.services.ai.azure.com/api/projects/project",
      "agent",
      fetcher,
    );

    const consent = await client.ask("teams-oauth", "Revenue by region", "user-token");
    const result = await client.ask("teams-oauth", "continue", "user-token");

    assert.match(consent, /Authorize Databricks access/);
    assert.equal(result, "Authorized result");
    assert.deepEqual(responseBodies[1], {
      previous_response_id: "response-1",
      input: "Revenue by region",
      agent_reference: { type: "agent_reference", name: "agent" },
    });
  });
});
