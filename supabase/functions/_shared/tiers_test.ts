import { assertEquals } from "jsr:@std/assert@1";
import {
  composeLimitReached,
  dailySaveLimitReached,
  effectiveTier,
  FREE_SAVES_PER_DAY,
  periodEnd,
  periodStart,
  planSummary,
  PRO_COMPOSE_PER_MONTH,
  PRO_SMART_SAVES_PER_MONTH,
  proRequired,
  USAGE_PERIOD,
  usageLimit,
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

Deno.test("usageLimit: 5 free saves a day, no smart summaries or Compose on free", () => {
  assertEquals(FREE_SAVES_PER_DAY, 5);
  assertEquals(usageLimit("free", "save"), 5);
  assertEquals(usageLimit("free", "smart_save"), 0);
  assertEquals(usageLimit("free", "compose"), 0);
});

Deno.test("usageLimit: Pro saves unlimited, 300 smart summaries and 10 Compose runs a month", () => {
  assertEquals(PRO_SMART_SAVES_PER_MONTH, 300);
  assertEquals(PRO_COMPOSE_PER_MONTH, 10);
  assertEquals(usageLimit("pro", "save"), null);
  assertEquals(usageLimit("pro", "smart_save"), 300);
  assertEquals(usageLimit("pro", "compose"), 10);
});

Deno.test("saves count per day, smart summaries and Compose per month", () => {
  assertEquals(USAGE_PERIOD, { save: "day", smart_save: "month", compose: "month" });
});

Deno.test("periodStart is the UTC day or the first of the UTC month (matches claim_usage)", () => {
  assertEquals(periodStart("day", now), "2026-10-30");
  assertEquals(periodStart("month", now), "2026-10-01");
  // 1 Nov 03:00 in India is still 31 Oct in UTC
  assertEquals(periodStart("day", new Date("2026-10-31T21:30:00Z")), "2026-10-31");
  assertEquals(periodStart("month", new Date("2026-10-31T21:30:00Z")), "2026-10-01");
  assertEquals(periodStart("day", new Date("2026-01-05T00:00:00Z")), "2026-01-05");
});

Deno.test("periodEnd rolls over days, months and years", () => {
  assertEquals(periodEnd("day", now).toISOString(), "2026-10-31T00:00:00.000Z");
  assertEquals(periodEnd("day", new Date("2026-10-31T23:00:00Z")).toISOString(), "2026-11-01T00:00:00.000Z");
  assertEquals(periodEnd("month", now).toISOString(), "2026-11-01T00:00:00.000Z");
  assertEquals(periodEnd("month", new Date("2026-12-31T23:59:59Z")).toISOString(), "2027-01-01T00:00:00.000Z");
});

Deno.test("refusals carry codes the app branches on", () => {
  assertEquals(proRequired("compose"), { code: "pro_required", message: "Compose is part of Sangrah Pro." });
  assertEquals(proRequired("screenshots").message, "Reading screenshots with AI is part of Sangrah Pro.");
  assertEquals(proRequired("posts").code, "pro_required");
  assertEquals(dailySaveLimitReached().code, "daily_limit_reached");
  assertEquals(
    dailySaveLimitReached().message,
    "You've saved 5 articles today, the free limit. Save more tomorrow, or go Pro for unlimited saves and smart summaries.",
  );
  const compose = composeLimitReached(now);
  assertEquals(compose.code, "monthly_limit_reached");
  assertEquals(compose.message, "You've used all 10 Compose runs this month. More on 1 November.");
});

Deno.test("planSummary: free shows today's saves; Pro shows the month's smart summaries", () => {
  const subscription = { expiresAt: null, trialEndsAt: null, autoRenews: null };
  assertEquals(planSummary("free", { save: 2 }, subscription, now), {
    tier: "free",
    expiresAt: null,
    trialEndsAt: null,
    autoRenews: null,
    saves: { used: 2, limit: 5, resetsAt: "2026-10-31T00:00:00.000Z" },
    smartSummaries: { used: 0, limit: 0, resetsAt: "2026-11-01T00:00:00.000Z" },
    compose: { used: 0, limit: 0, resetsAt: "2026-11-01T00:00:00.000Z" },
  });
  const pro = planSummary("pro", { save: 9, smart_save: 120, compose: 3 }, { ...subscription, autoRenews: true }, now);
  assertEquals(pro.saves.limit, null);
  assertEquals(pro.smartSummaries, { used: 120, limit: 300, resetsAt: "2026-11-01T00:00:00.000Z" });
  assertEquals(pro.compose.used, 3);
  assertEquals(pro.compose.limit, 10);
});
