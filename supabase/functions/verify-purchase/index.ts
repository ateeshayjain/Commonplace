// Supabase Edge Function: verify-purchase
// The app sends a StoreKit transaction after a purchase, a restore or at launch;
// this asks Apple for the subscription's real status, links it to the caller
// and sets their tier. With no transaction it just returns the plan and this
// month's usage (Profile, paywall, save counter).

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  credentialsFromEnv,
  decodeJWSPayload,
  fetchSubscriptionStatus,
  subscriptionState,
  type TransactionInfo,
} from '../_shared/appstore.ts';
import { effectiveTier, planSummary, PRO_PRODUCT_IDS } from '../_shared/tiers.ts';
import {
  ownerOf,
  refreshUserTier,
  storeSubscription,
  SubscriptionOwnedElsewhere,
  SubscriptionWithoutAccount,
  type SubscriptionDetails,
} from '../_shared/subscriptions.ts';
import { usageThisMonth } from '../_shared/usage.ts';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

interface VerifyRequest {
  // VerificationResult<Transaction>.jwsRepresentation from StoreKit 2
  signedTransaction?: string;
}

function reply(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    status,
  });
}

function refuse(status: number, code: string, error: string): Response {
  return reply({ error, code }, status);
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) throw new Error('Missing authorization header');

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    );
    const { data: { user }, error: authError } = await supabase.auth.getUser(authHeader.replace('Bearer ', ''));
    if (authError || !user) throw new Error('Unauthorized');

    const { signedTransaction }: VerifyRequest = await req.json().catch(() => ({}));

    let details: SubscriptionDetails | null = null;
    if (signedTransaction) {
      const credentials = credentialsFromEnv();
      if (!credentials) {
        return refuse(503, 'not_configured', "Purchases can't be confirmed yet. Please try again later.");
      }

      // Unchecked: only says which subscription to ask Apple about
      const transaction = decodeJWSPayload<TransactionInfo>(signedTransaction);
      if (transaction.environment === 'Xcode' || transaction.environment === 'LocalTesting') {
        return refuse(400, 'local_storekit',
          "This purchase was made with Xcode's StoreKit test file, which the server can't confirm.");
      }
      if (transaction.bundleId !== credentials.bundleId) {
        return refuse(400, 'wrong_app', 'This purchase is for a different app.');
      }

      const status = await fetchSubscriptionStatus(credentials, transaction.originalTransactionId, transaction.environment);
      const state = status ? subscriptionState(status, PRO_PRODUCT_IDS) : null;
      if (!state) {
        return refuse(404, 'not_found', "The App Store has no Sangrah Pro subscription for this purchase.");
      }

      try {
        await ownerOf(supabase, state, user.id);
      } catch (e) {
        if (e instanceof SubscriptionOwnedElsewhere) return refuse(409, 'owned_elsewhere', e.message);
        if (e instanceof SubscriptionWithoutAccount) return refuse(409, 'no_account', e.message);
        throw e;
      }
      await storeSubscription(supabase, user.id, state);
      details = await refreshUserTier(supabase, user.id);
    }

    // Accounts without App Store subscriptions keep their users row as is
    if (!details) {
      const { data: row } = await supabase
        .from('users')
        .select('subscription_tier, subscription_expires_at')
        .eq('id', user.id)
        .maybeSingle();
      const { data: subscription } = await supabase
        .from('app_store_subscriptions')
        .select('trial_ends_at, auto_renews')
        .eq('user_id', user.id)
        .order('expires_at', { ascending: false, nullsFirst: false })
        .limit(1)
        .maybeSingle();
      const tier = effectiveTier(row);
      details = {
        tier,
        expiresAt: row?.subscription_expires_at ?? null,
        trialEndsAt: tier === 'pro' ? subscription?.trial_ends_at ?? null : null,
        autoRenews: subscription?.auto_renews ?? null,
      };
    }

    const used = await usageThisMonth(supabase, user.id);
    return reply(planSummary(details.tier, used, details));
  } catch (error) {
    console.error('verify-purchase error:', error);
    return reply({ error: (error as Error).message }, 400);
  }
});
