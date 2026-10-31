import { assertEquals, assertRejects } from "jsr:@std/assert@1";
import { type Anthropic, CLAUDE_MODELS, generateJSON, generateText } from "./claude.ts";

// Records the request body and answers with a fixed message
function fakeClient(text: string, stopReason = "end_turn") {
  const requests: Record<string, unknown>[] = [];
  const client = {
    beta: {
      messages: {
        create: (body: Record<string, unknown>) => {
          requests.push(body);
          return Promise.resolve({
            stop_reason: stopReason,
            stop_details: stopReason === "refusal" ? { category: "cyber" } : null,
            content: [{ type: "thinking", thinking: "" }, { type: "text", text }],
          });
        },
      },
    },
  } as unknown as Anthropic;
  return { client, requests };
}

const schema = { type: "object", additionalProperties: false, required: ["ok"], properties: { ok: { type: "boolean" } } };

Deno.test("models: Pro saves on Sonnet 5.5; Compose, posts and voice analysis on Opus 5.5", () => {
  assertEquals(CLAUDE_MODELS, { saves: "claude-sonnet-5-5", standard: "claude-opus-5-5" });
});

Deno.test("generateJSON asks for the default server-side fallback", async () => {
  for (const model of [CLAUDE_MODELS.saves, CLAUDE_MODELS.standard]) {
    const { client, requests } = fakeClient('{"ok":true}');
    const result = await generateJSON<{ ok: boolean }>(client, { model, effort: "low", schema, prompt: "hi" });
    assertEquals(result, { ok: true });
    assertEquals(requests[0].model, model);
    assertEquals(requests[0].fallbacks, "default");
    assertEquals(requests[0].betas, ["server-side-fallback-2026-07-01"]);
  }
});

Deno.test("generateText reads text blocks past a thinking block", async () => {
  const { client, requests } = fakeClient("hello");
  assertEquals(await generateText(client, { model: CLAUDE_MODELS.standard, effort: "low", prompt: "hi" }), "hello");
  assertEquals(requests[0].fallbacks, "default");
});

Deno.test("a refusal throws so the caller can give the credit back", async () => {
  const { client } = fakeClient("", "refusal");
  await assertRejects(
    () => generateJSON(client, { model: CLAUDE_MODELS.saves, effort: "low", schema, prompt: "hi" }),
    Error,
    "Claude declined the request (cyber)",
  );
});
