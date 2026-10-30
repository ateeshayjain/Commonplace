import { assertEquals, assertRejects } from "jsr:@std/assert@1";
import { claimUsage, loadTier, releaseUsage } from "./usage.ts";
import { ownerOf, SubscriptionOwnedElsewhere } from "./subscriptions.ts";
import type { SubscriptionState } from "./appstore.ts";

// Just enough of supabase-js for these helpers: rpc() and a select chain ending in maybeSingle()
function fakeSupabase(options: { rpc?: (name: string, args: Record<string, unknown>) => unknown; row?: unknown; error?: unknown }) {
  const calls: { name: string; args: Record<string, unknown> }[] = [];
  const chain = {
    select: () => chain,
    eq: () => chain,
    maybeSingle: () => Promise.resolve({ data: options.row ?? null, error: options.error ?? null }),
  };
  return {
    calls,
    client: {
      rpc: (name: string, args: Record<string, unknown>) => {
        calls.push({ name, args });
        return Promise.resolve({ data: options.rpc?.(name, args) ?? null, error: null });
      },
      from: () => chain,
    },
  };
}

Deno.test("claimUsage asks for the tier's limit and returns the claimed month", async () => {
  const { client, calls } = fakeSupabase({ rpc: () => [{ period: "2026-10-01", used: 20 }] });
  const claim = await claimUsage(client, "user-1", "save", "free");
  assertEquals(calls[0], { name: "claim_ai_usage", args: { p_user_id: "user-1", p_feature: "save", p_limit: 20 } });
  assertEquals(claim, { userId: "user-1", feature: "save", tier: "free", period: "2026-10-01", used: 20 });
});

Deno.test("claimUsage: Pro saves are unlimited but counted; an empty result means the limit is reached", async () => {
  const pro = fakeSupabase({ rpc: () => [{ period: "2026-10-01", used: 101 }] });
  await claimUsage(pro.client, "user-1", "save", "pro");
  assertEquals(pro.calls[0].args.p_limit, null);

  const full = fakeSupabase({ rpc: () => [] });
  assertEquals(await claimUsage(full.client, "user-1", "save", "free"), null);
});

Deno.test("releaseUsage gives the credit back to the month it came from", async () => {
  const { client, calls } = fakeSupabase({});
  await releaseUsage(client, { userId: "user-1", feature: "compose", tier: "pro", period: "2026-09-01", used: 4 });
  assertEquals(calls[0], { name: "release_ai_usage", args: { p_user_id: "user-1", p_feature: "compose", p_period: "2026-09-01" } });
});

Deno.test("loadTier falls back to free when the lookup fails", async () => {
  assertEquals(await loadTier(fakeSupabase({ error: { message: "boom" } }).client, "user-1"), "free");
  assertEquals(await loadTier(fakeSupabase({ row: { subscription_tier: "pro", subscription_expires_at: null } }).client, "u"), "pro");
});

const state = (appAccountToken: string | null): SubscriptionState => ({
  originalTransactionId: "2000000000001",
  productId: "sangrah.pro.monthly",
  status: 1,
  expiresAt: null,
  trialEndsAt: null,
  autoRenews: true,
  environment: "Sandbox",
  appAccountToken,
});

Deno.test("ownerOf: the stored owner wins, then Apple's appAccountToken, then the caller", async () => {
  assertEquals(await ownerOf(fakeSupabase({ row: { user_id: "a" } }).client, state("b"), null), "a");
  assertEquals(await ownerOf(fakeSupabase({}).client, state("b"), null), "b");
  assertEquals(await ownerOf(fakeSupabase({}).client, state(null), "c"), "c");
  assertEquals(await ownerOf(fakeSupabase({}).client, state(null), null), null);
  // Token case doesn't matter (Swift UUIDs are upper case, Postgres lower case)
  assertEquals(await ownerOf(fakeSupabase({}).client, state("abc"), "ABC"), "abc");
});

Deno.test("ownerOf: restoring someone else's subscription on another account is refused", async () => {
  await assertRejects(() => ownerOf(fakeSupabase({ row: { user_id: "a" } }).client, state(null), "b"), SubscriptionOwnedElsewhere);
  await assertRejects(() => ownerOf(fakeSupabase({}).client, state("a"), "b"), SubscriptionOwnedElsewhere);
});
