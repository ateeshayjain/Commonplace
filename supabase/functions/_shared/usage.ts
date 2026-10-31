// Reads a user's tier and claims daily saves and monthly Pro allowances
// (usage_counts, migration 010).
// Needs a service-role client: users can read their counts but not write them.

import { effectiveTier, periodStart, USAGE_PERIOD, usageLimit, type Tier, type UsageFeature } from './tiers.ts';

// deno-lint-ignore no-explicit-any
type SupabaseClient = any;

export async function loadTier(supabase: SupabaseClient, userId: string): Promise<Tier> {
  const { data, error } = await supabase
    .from('users')
    .select('subscription_tier, subscription_expires_at')
    .eq('id', userId)
    .maybeSingle();
  if (error) {
    // Fail towards the free limits, never towards free Pro
    console.error('Tier lookup failed:', error);
    return 'free';
  }
  return effectiveTier(data);
}

// One use taken (a save, a smart summary, a Compose run); give it back with
// releaseUsage if what it was for doesn't happen
export interface UsageClaim {
  userId: string;
  feature: UsageFeature;
  tier: Tier;
  period: string;
  used: number;
}

// Takes one use in the current day or month, or returns null when the limit is reached
export async function claimUsage(
  supabase: SupabaseClient,
  userId: string,
  feature: UsageFeature,
  tier: Tier
): Promise<UsageClaim | null> {
  const { data, error } = await supabase.rpc('claim_usage', {
    p_user_id: userId,
    p_feature: feature,
    p_limit: usageLimit(tier, feature),
    p_period: USAGE_PERIOD[feature],
  });
  if (error) {
    throw new Error(`Couldn't check usage: ${error.message}`);
  }
  const row = Array.isArray(data) ? data[0] : data;
  if (!row) return null;
  return { userId, feature, tier, period: String(row.period).substring(0, 10), used: row.used };
}

export async function releaseUsage(supabase: SupabaseClient, claim: UsageClaim): Promise<void> {
  const { error } = await supabase.rpc('release_usage', {
    p_user_id: claim.userId,
    p_feature: claim.feature,
    p_period: claim.period,
  });
  if (error) {
    console.error('Releasing a use failed:', error);
  }
}

// Today's saves and this month's smart summaries and Compose runs
export async function currentUsage(
  supabase: SupabaseClient,
  userId: string,
  now: Date = new Date()
): Promise<Partial<Record<UsageFeature, number>>> {
  const { data, error } = await supabase
    .from('usage_counts')
    .select('feature, period, used')
    .eq('user_id', userId)
    .in('period', [periodStart('day', now), periodStart('month', now)]);
  if (error) {
    throw new Error(`Couldn't read usage: ${error.message}`);
  }
  const used: Partial<Record<UsageFeature, number>> = {};
  for (const row of data ?? []) {
    const feature = row.feature as UsageFeature;
    // On the 1st, the day and the month share a date: match the period to the feature
    if (String(row.period).substring(0, 10) === periodStart(USAGE_PERIOD[feature], now)) {
      used[feature] = row.used;
    }
  }
  return used;
}
