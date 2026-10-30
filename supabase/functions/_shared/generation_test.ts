import { assert, assertEquals } from "https://deno.land/std@0.177.0/testing/asserts.ts";
import { HOOK_MAX_CHARS, fitHook } from "./generation.ts";

Deno.test("fitHook leaves a short Key Idea alone, tidying spaces", () => {
  assertEquals(fitHook("  Presence is   rebellion. "), "Presence is rebellion.");
});

Deno.test("fitHook shortens a long Key Idea at a word boundary with an ellipsis", () => {
  // 159 characters, from the model comparison on 30 Oct 2026
  const long = "The most trustworthy Super Intelligence system will not be the one with the model we trust most, but the one that enables us to trust the model the least.";
  const hook = fitHook(long);
  assert(hook.length <= HOOK_MAX_CHARS, `${hook.length} characters`);
  assert(hook.endsWith("…"));
  assert(long.startsWith(hook.slice(0, -1)), "cut mid-word");
  assert(!/[\s,]…$/.test(hook), "no space or comma before the ellipsis");
});

Deno.test("fitHook cuts a single unbroken run of text at the limit", () => {
  const hook = fitHook("x".repeat(400));
  assertEquals(hook.length, HOOK_MAX_CHARS);
});
