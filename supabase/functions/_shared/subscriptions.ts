// Stores App Store subscription states (app_store_subscriptions, migration 010)
// and sets users.subscription_tier from them. Service-role client only: the
// tier columns reject changes from app users.

import { tierFromSubscriptions, type SubscriptionState } from './appstore.ts';
import type { Tier } from './tiers.ts';

// deno-lint-ignore no-explicit-any
type SupabaseClient = any;

export class SubscriptionOwnedElsewhere extends Error {
  constructor() {
    super('This App Store subscription is linked to a different Sangrah account. Sign in with that account to use Pro.');
  }
}

// A purchase made outside the app (an offer code redeemed in the App Store)
// carries no account; linking it by "first to claim" would let anyone who
// learns a transaction id take it over, so support links these by hand
export class SubscriptionWithoutAccount extends Error {
  constructor() {
    super("This purchase isn't linked to a Sangrah account yet. Please contact support to link it.");
  }
}

// Who a subscription belongs to: whoever it is already stored for, else the
// account Apple's record names (appAccountToken, set by the app at purchase).
// With a claimant (verify-purchase), throws unless the claimant is that owner.
export async function ownerOf(
  supabase: SupabaseClient,
  state: SubscriptionState,
  claimant: string | null
): Promise<string | null> {
  const { data: stored } = await supabase
    .from('app_store_subscriptions')
    .select('user_id')
    .eq('original_transaction_id', state.originalTransactionId)
    .maybeSingle();
  const owner: string | null = stored?.user_id ?? state.appAccountToken;
  if (claimant) {
    if (!owner) throw new SubscriptionWithoutAccount();
    if (owner.toLowerCase() !== claimant.toLowerCase()) throw new SubscriptionOwnedElsewhere();
  }
  return owner;
}

export async function storeSubscription(supabase: SupabaseClient, userId: string, state: SubscriptionState) {
  const { error } = await supabase.from('app_store_subscriptions').upsert({
    original_transaction_id: state.originalTransactionId,
    user_id: userId,
    product_id: state.productId,
    status: state.status,
    expires_at: state.expiresAt,
    trial_ends_at: state.trialEndsAt,
    auto_renews: state.autoRenews,
    environment: state.environment,
    updated_at: new Date().toISOString(),
  });
  if (error) throw new Error(`Couldn't store the subscription: ${error.message}`);
}

export interface SubscriptionDetails {
  tier: Tier;
  expiresAt: string | null;
  trialEndsAt: string | null;
  autoRenews: boolean | null;
}

// Recomputes the user's tier from their App Store subscriptions. Accounts
// with none are left as they are (a tier set by hand, or plain free).
export async function refreshUserTier(supabase: SupabaseClient, userId: string): Promise<SubscriptionDetails | null> {
  const { data: rows, error } = await supabase
    .from('app_store_subscriptions')
    .select('status, expires_at, trial_ends_at, auto_renews')
    .eq('user_id', userId)
    .order('expires_at', { ascending: false, nullsFirst: false });
  if (error) throw new Error(`Couldn't read subscriptions: ${error.message}`);
  if (!rows?.length) return null;

  const { tier, expiresAt } = tierFromSubscriptions(rows);
  const { error: updateError } = await supabase
    .from('users')
    .update({ subscription_tier: tier, subscription_expires_at: expiresAt })
    .eq('id', userId);
  if (updateError) throw new Error(`Couldn't update the tier: ${updateError.message}`);

  // The subscription giving access (or the latest one) describes the plan
  const current = rows.find((row: { expires_at: string | null }) => row.expires_at === expiresAt) ?? rows[0];
  return {
    tier,
    expiresAt,
    trialEndsAt: tier === 'pro' ? current.trial_ends_at : null,
    autoRenews: current.auto_renews,
  };
}
