// Reads a user's tier and claims monthly AI credits (ai_usage, migration 010).
// Needs a service-role client: users can read their counts but not write them.

import { effectiveTier, usageLimit, usagePeriod, type Tier, type UsageFeature } from './tiers.ts';

// deno-lint-ignore no-explicit-any
type SupabaseClient = any;

export async function loadTier(supabase: SupabaseClient, userId: string): Promise<Tier> {
  const { data, error } = await supabase
    .from('users')
    .select('subscription_tier, subscription_expires_at')
    .eq('id', userId)
    .maybeSingle();
  if (error) {
    // Fail towards the cheaper model and the free limits, never towards free Pro
    console.error('Tier lookup failed:', error);
    return 'free';
  }
  return effectiveTier(data);
}

// A credit taken for one Claude call; give it back with releaseUsage if the
// call doesn't happen or fails
export interface UsageClaim {
  userId: string;
  feature: UsageFeature;
  tier: Tier;
  period: string;
  used: number;
}

// Takes one credit, or returns null when this month's limit is reached
export async function claimUsage(
  supabase: SupabaseClient,
  userId: string,
  feature: UsageFeature,
  tier: Tier
): Promise<UsageClaim | null> {
  const { data, error } = await supabase.rpc('claim_ai_usage', {
    p_user_id: userId,
    p_feature: feature,
    p_limit: usageLimit(tier, feature),
  });
  if (error) {
    throw new Error(`Couldn't check this month's AI usage: ${error.message}`);
  }
  const row = Array.isArray(data) ? data[0] : data;
  if (!row) return null;
  return { userId, feature, tier, period: String(row.period).substring(0, 10), used: row.used };
}

export async function releaseUsage(supabase: SupabaseClient, claim: UsageClaim): Promise<void> {
  const { error } = await supabase.rpc('release_ai_usage', {
    p_user_id: claim.userId,
    p_feature: claim.feature,
    p_period: claim.period,
  });
  if (error) {
    console.error('Releasing an AI credit failed:', error);
  }
}

export async function usageThisMonth(
  supabase: SupabaseClient,
  userId: string,
  now: Date = new Date()
): Promise<Partial<Record<UsageFeature, number>>> {
  const { data, error } = await supabase
    .from('ai_usage')
    .select('feature, used')
    .eq('user_id', userId)
    .eq('period', usagePeriod(now));
  if (error) {
    throw new Error(`Couldn't read this month's AI usage: ${error.message}`);
  }
  const used: Partial<Record<UsageFeature, number>> = {};
  for (const row of data ?? []) {
    used[row.feature as UsageFeature] = row.used;
  }
  return used;
}
