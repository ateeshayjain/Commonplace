// Free and Pro tiers: limits, models and the monthly period, in one place.
// Mirrored for display only in iOS Core/Models/Plan.swift; the server decides.
//
// Cost per article save measured 30 Oct 2026 (15 real saves): Sonnet 5.5 1.4¢,
// Haiku 5.5 0.07¢ (screenshot saves 4.0¢ / 0.2¢). Everything that doesn't call
// Claude (Library, search, quotes, PDFs, widget, Weekly Summary) has no limit.

import { CLAUDE_MODELS, type ClaudeModel } from './models.ts';

export type Tier = 'free' | 'pro';
export type UsageFeature = 'save' | 'compose';

// AI-processed saves per calendar month on the free tier; later saves are
// stored and wait for a credit (documents.ai_waiting)
export const FREE_SAVES_PER_MONTH = 20;
// Compose (synthesize-content) runs per calendar month on Pro; free has none
export const PRO_COMPOSE_PER_MONTH = 10;

// App Store product ids in the "Sangrah Pro" subscription group. Kept in step
// with iOS Plan.swift (SubscriptionProduct) and iOS/Sangrah.storekit.
export const PRO_PRODUCT_IDS = ['sangrah.pro.monthly', 'sangrah.pro.yearly'] as const;

export interface SubscriptionColumns {
  subscription_tier: string | null;
  subscription_expires_at: string | null;
}

// The users row says pro, creator or team, and access hasn't run out. A null
// expiry means a tier set by hand (support, staff), which doesn't lapse.
export function effectiveTier(row: SubscriptionColumns | null, now: Date = new Date()): Tier {
  if (!row || !row.subscription_tier || row.subscription_tier === 'free') return 'free';
  if (!['pro', 'creator', 'team'].includes(row.subscription_tier)) return 'free';
  if (row.subscription_expires_at && new Date(row.subscription_expires_at).getTime() <= now.getTime()) {
    return 'free';
  }
  return 'pro';
}

export function saveModel(tier: Tier): ClaudeModel {
  return tier === 'pro' ? CLAUDE_MODELS.saves : CLAUDE_MODELS.freeSaves;
}

// null = unlimited (still counted, for cost tracking)
export function usageLimit(tier: Tier, feature: UsageFeature): number | null {
  switch (feature) {
    case 'save':
      return tier === 'pro' ? null : FREE_SAVES_PER_MONTH;
    case 'compose':
      return tier === 'pro' ? PRO_COMPOSE_PER_MONTH : 0;
  }
}

// ai_usage.period: the first day of the calendar month, in UTC (matches
// claim_ai_usage in migration 010)
export function usagePeriod(now: Date = new Date()): string {
  const month = String(now.getUTCMonth() + 1).padStart(2, '0');
  return `${now.getUTCFullYear()}-${month}-01`;
}

// When this month's credits renew
export function nextPeriodStart(now: Date = new Date()): Date {
  return new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() + 1, 1));
}

// Why a request was turned away, as a stable code the app can branch on
export type LimitCode = 'pro_required' | 'monthly_limit_reached';

export interface LimitError {
  code: LimitCode;
  message: string;
}

// Compose before claiming: free readers are told it's a Pro feature rather
// than that they've used zero of zero
export function composeRefusal(tier: Tier): LimitError | null {
  if (tier === 'free') {
    return { code: 'pro_required', message: 'Compose is part of Sangrah Pro.' };
  }
  return null;
}

export function composeLimitReached(now: Date = new Date()): LimitError {
  const renews = nextPeriodStart(now).toLocaleDateString('en-GB', { day: 'numeric', month: 'long', timeZone: 'UTC' });
  return {
    code: 'monthly_limit_reached',
    message: `You've used all ${PRO_COMPOSE_PER_MONTH} Compose runs this month. More on ${renews}.`,
  };
}

// The plan as the app shows it (Profile, paywall, save counter)
export interface PlanSummary {
  tier: Tier;
  expiresAt: string | null;
  trialEndsAt: string | null;
  autoRenews: boolean | null;
  periodEnds: string;
  saves: { used: number; limit: number | null };
  compose: { used: number; limit: number };
}

export function planSummary(
  tier: Tier,
  used: Partial<Record<UsageFeature, number>>,
  subscription: { expiresAt: string | null; trialEndsAt: string | null; autoRenews: boolean | null },
  now: Date = new Date()
): PlanSummary {
  return {
    tier,
    expiresAt: subscription.expiresAt,
    trialEndsAt: subscription.trialEndsAt,
    autoRenews: subscription.autoRenews,
    periodEnds: nextPeriodStart(now).toISOString(),
    saves: { used: used.save ?? 0, limit: usageLimit(tier, 'save') },
    compose: { used: used.compose ?? 0, limit: usageLimit(tier, 'compose') ?? 0 },
  };
}
