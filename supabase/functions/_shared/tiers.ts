// Free and Pro tiers: limits and periods, in one place.
// Mirrored for display only in iOS Core/Models/Plan.swift; the server decides.
//
// Free: up to FREE_SAVES_PER_DAY saves a day, with no Claude call (clean text,
// PDF, Listen, search, manual categories, notes, widget). Pro: the smart
// summary on every save (Key Idea, summaries, key points, quotes, tags,
// auto-categories; about 1.4¢ an article, 4¢ a screenshot save on Sonnet 5.5,
// measured 30 Oct 2026), screenshots read by Claude, Compose and post generation.

export type Tier = 'free' | 'pro';
export type UsageFeature = 'save' | 'smart_save' | 'compose';
export type UsagePeriod = 'day' | 'month';

// Saves per UTC day on the free tier (Pro saves aren't limited)
export const FREE_SAVES_PER_DAY = 5;
// Smart summaries per UTC calendar month on Pro (fair use); later saves are
// kept and wait for next month (documents.ai_waiting)
export const PRO_SMART_SAVES_PER_MONTH = 300;
// Compose (synthesize-content) runs per UTC calendar month on Pro
export const PRO_COMPOSE_PER_MONTH = 10;

export const USAGE_PERIOD: Record<UsageFeature, UsagePeriod> = {
  save: 'day',
  smart_save: 'month',
  compose: 'month',
};

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

// null = unlimited (still counted, for cost tracking); 0 = not included
export function usageLimit(tier: Tier, feature: UsageFeature): number | null {
  switch (feature) {
    case 'save':
      return tier === 'pro' ? null : FREE_SAVES_PER_DAY;
    case 'smart_save':
      return tier === 'pro' ? PRO_SMART_SAVES_PER_MONTH : 0;
    case 'compose':
      return tier === 'pro' ? PRO_COMPOSE_PER_MONTH : 0;
  }
}

// usage_counts.period: the UTC day, or the first day of the UTC month
// (matches claim_usage in migration 010)
export function periodStart(period: UsagePeriod, now: Date = new Date()): string {
  const day = period === 'day' ? now.getUTCDate() : 1;
  return `${now.getUTCFullYear()}-${String(now.getUTCMonth() + 1).padStart(2, '0')}-${String(day).padStart(2, '0')}`;
}

// When the current day's or month's allowance renews
export function periodEnd(period: UsagePeriod, now: Date = new Date()): Date {
  return period === 'day'
    ? new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate() + 1))
    : new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() + 1, 1));
}

// Why a request was turned away, as a stable code the app can branch on
export type LimitCode = 'pro_required' | 'daily_limit_reached' | 'monthly_limit_reached';

export interface LimitError {
  code: LimitCode;
  message: string;
}

export function proRequired(feature: 'compose' | 'posts' | 'summary' | 'screenshots'): LimitError {
  const what = {
    compose: 'Compose is',
    posts: 'Writing posts is',
    summary: 'The smart summary is',
    screenshots: 'Reading screenshots with AI is',
  }[feature];
  return { code: 'pro_required', message: `${what} part of Sangrah Pro.` };
}

export function dailySaveLimitReached(): LimitError {
  return {
    code: 'daily_limit_reached',
    message: `You've saved ${FREE_SAVES_PER_DAY} articles today, the free limit. Save more tomorrow, or go Pro for unlimited saves and smart summaries.`,
  };
}

export function composeLimitReached(now: Date = new Date()): LimitError {
  const renews = periodEnd('month', now).toLocaleDateString('en-GB', { day: 'numeric', month: 'long', timeZone: 'UTC' });
  return {
    code: 'monthly_limit_reached',
    message: `You've used all ${PRO_COMPOSE_PER_MONTH} Compose runs this month. More on ${renews}.`,
  };
}

export interface UsageSummary {
  used: number;
  // null = unlimited
  limit: number | null;
  resetsAt: string;
}

// The plan as the app shows it (Profile, paywall, save counter)
export interface PlanSummary {
  tier: Tier;
  expiresAt: string | null;
  trialEndsAt: string | null;
  autoRenews: boolean | null;
  saves: UsageSummary;
  smartSummaries: UsageSummary;
  compose: UsageSummary;
}

export function planSummary(
  tier: Tier,
  used: Partial<Record<UsageFeature, number>>,
  subscription: { expiresAt: string | null; trialEndsAt: string | null; autoRenews: boolean | null },
  now: Date = new Date()
): PlanSummary {
  const usage = (feature: UsageFeature): UsageSummary => ({
    used: used[feature] ?? 0,
    limit: usageLimit(tier, feature),
    resetsAt: periodEnd(USAGE_PERIOD[feature], now).toISOString(),
  });
  return {
    tier,
    expiresAt: subscription.expiresAt,
    trialEndsAt: subscription.trialEndsAt,
    autoRenews: subscription.autoRenews,
    saves: usage('save'),
    smartSummaries: usage('smart_save'),
    compose: usage('compose'),
  };
}
