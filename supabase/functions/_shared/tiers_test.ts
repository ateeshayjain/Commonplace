import { assertEquals } from "jsr:@std/assert@1";
import {
  composeLimitReached,
  composeRefusal,
  effectiveTier,
  FREE_SAVES_PER_MONTH,
  nextPeriodStart,
  planSummary,
  PRO_COMPOSE_PER_MONTH,
  saveModel,
  usageLimit,
  usagePeriod,
} from "./tiers.ts";

const now = new Date("2026-10-30T12:00:00Z");

Deno.test("effectiveTier: free unless a paid tier hasn't run out", () => {
  assertEquals(effectiveTier(null, now), "free");
  assertEquals(effectiveTier({ subscription_tier: "free", subscription_expires_at: null }, now), "free");
  assertEquals(effectiveTier({ subscription_tier: null, subscription_expires_at: null }, now), "free");
  assertEquals(effectiveTier({ subscription_tier: "pro", subscription_expires_at: "2026-11-30T00:00:00Z" }, now), "pro");
  // Lapsed: a missed renewal notification must not leave Pro on forever
  assertEquals(effectiveTier({ subscription_tier: "pro", subscription_expires_at: "2026-10-30T11:59:59Z" }, now), "free");
  // No expiry: set by hand, doesn't lapse
  assertEquals(effectiveTier({ subscription_tier: "team", subscription_expires_at: null }, now), "pro");
  assertEquals(effectiveTier({ subscription_tier: "creator", subscription_expires_at: null }, now), "pro");
  assertEquals(effectiveTier({ subscription_tier: "platinum", subscription_expires_at: null }, now), "free");
});

Deno.test("saveModel: Haiku 5.5 for free saves, Sonnet 5.5 for Pro", () => {
  assertEquals(saveModel("free"), "claude-haiku-5-5");
  assertEquals(saveModel("pro"), "claude-sonnet-5-5");
});

Deno.test("usageLimit: 20 free saves, unlimited Pro saves, Compose Pro only at 10", () => {
  assertEquals(FREE_SAVES_PER_MONTH, 20);
  assertEquals(PRO_COMPOSE_PER_MONTH, 10);
  assertEquals(usageLimit("free", "save"), 20);
  assertEquals(usageLimit("pro", "save"), null);
  assertEquals(usageLimit("free", "compose"), 0);
  assertEquals(usageLimit("pro", "compose"), 10);
});

Deno.test("usagePeriod is the first of the calendar month in UTC", () => {
  assertEquals(usagePeriod(now), "2026-10-01");
  // 1 Nov 03:00 in India is still 31 Oct in UTC
  assertEquals(usagePeriod(new Date("2026-10-31T21:30:00Z")), "2026-10-01");
  assertEquals(usagePeriod(new Date("2026-11-01T00:00:00Z")), "2026-11-01");
  assertEquals(usagePeriod(new Date("2026-01-15T00:00:00Z")), "2026-01-01");
});

Deno.test("nextPeriodStart rolls over months and years", () => {
  assertEquals(nextPeriodStart(now).toISOString(), "2026-11-01T00:00:00.000Z");
  assertEquals(nextPeriodStart(new Date("2026-12-31T23:59:59Z")).toISOString(), "2027-01-01T00:00:00.000Z");
});

Deno.test("Compose: free readers get pro_required, Pro readers past 10 get monthly_limit_reached", () => {
  assertEquals(composeRefusal("free")?.code, "pro_required");
  assertEquals(composeRefusal("pro"), null);
  const limit = composeLimitReached(now);
  assertEquals(limit.code, "monthly_limit_reached");
  assertEquals(limit.message, "You've used all 10 Compose runs this month. More on 1 November.");
});

Deno.test("planSummary reports limits for the tier and fills in missing usage", () => {
  const subscription = { expiresAt: null, trialEndsAt: null, autoRenews: null };
  assertEquals(planSummary("free", { save: 7 }, subscription, now), {
    tier: "free",
    expiresAt: null,
    trialEndsAt: null,
    autoRenews: null,
    periodEnds: "2026-11-01T00:00:00.000Z",
    saves: { used: 7, limit: 20 },
    compose: { used: 0, limit: 0 },
  });
  const pro = planSummary("pro", { save: 120, compose: 3 }, { ...subscription, autoRenews: true }, now);
  assertEquals(pro.saves, { used: 120, limit: null });
  assertEquals(pro.compose, { used: 3, limit: 10 });
});
