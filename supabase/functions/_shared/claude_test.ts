import { assertEquals, assertRejects } from "jsr:@std/assert@1";
import { type Anthropic, CLAUDE_MODELS, generateJSON, generateText, supportsServerFallback } from "./claude.ts";

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

Deno.test("models: free saves on Haiku 5.5, Pro saves on Sonnet 5.5, Compose on Opus 5.5", () => {
  assertEquals(CLAUDE_MODELS.freeSaves, "claude-haiku-5-5");
  assertEquals(CLAUDE_MODELS.saves, "claude-sonnet-5-5");
  assertEquals(CLAUDE_MODELS.standard, "claude-opus-5-5");
});

Deno.test("supportsServerFallback is false only for Haiku 5.5", () => {
  assertEquals(supportsServerFallback(CLAUDE_MODELS.freeSaves), false);
  assertEquals(supportsServerFallback(CLAUDE_MODELS.saves), true);
  assertEquals(supportsServerFallback(CLAUDE_MODELS.standard), true);
});

Deno.test("generateJSON sends no fallbacks for Haiku 5.5", async () => {
  const { client, requests } = fakeClient('{"ok":true}');
  const result = await generateJSON<{ ok: boolean }>(client, {
    model: CLAUDE_MODELS.freeSaves, effort: "low", schema, prompt: "hi",
  });
  assertEquals(result, { ok: true });
  assertEquals("fallbacks" in requests[0], false);
  assertEquals("betas" in requests[0], false);
  assertEquals(requests[0].model, "claude-haiku-5-5");
});

Deno.test("generateJSON keeps the default fallback for Sonnet 5.5 and Opus 5.5", async () => {
  for (const model of [CLAUDE_MODELS.saves, CLAUDE_MODELS.standard]) {
    const { client, requests } = fakeClient('{"ok":true}');
    await generateJSON(client, { model, effort: "low", schema, prompt: "hi" });
    assertEquals(requests[0].fallbacks, "default");
    assertEquals(requests[0].betas, ["server-side-fallback-2026-07-01"]);
  }
});

Deno.test("generateText follows the same fallback rule", async () => {
  const haiku = fakeClient("hello");
  assertEquals(await generateText(haiku.client, { model: CLAUDE_MODELS.freeSaves, effort: "low", prompt: "hi" }), "hello");
  assertEquals("fallbacks" in haiku.requests[0], false);
  const opus = fakeClient("hello");
  await generateText(opus.client, { model: CLAUDE_MODELS.standard, effort: "low", prompt: "hi" });
  assertEquals(opus.requests[0].fallbacks, "default");
});

Deno.test("a Haiku refusal is final: generateJSON throws", async () => {
  const { client } = fakeClient("", "refusal");
  await assertRejects(
    () => generateJSON(client, { model: CLAUDE_MODELS.freeSaves, effort: "low", schema, prompt: "hi" }),
    Error,
    "Claude declined the request (cyber)",
  );
});
