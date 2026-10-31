// Supabase Edge Function: app-store-notifications
// App Store Server Notifications V2 endpoint (renewals, expiries, refunds,
// billing problems). Apple calls it without a Supabase token, so JWT checks
// are off for it in config.toml. The notification only names a subscription;
// its status is re-read from the App Store Server API (see _shared/appstore.ts),
// so a forged notification changes nothing.

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  credentialsFromEnv,
  decodeJWSPayload,
  fetchSubscriptionStatus,
  subscriptionState,
  type NotificationPayload,
  type TransactionInfo,
} from '../_shared/appstore.ts';
import { PRO_PRODUCT_IDS } from '../_shared/tiers.ts';
import { ownerOf, refreshUserTier, storeSubscription } from '../_shared/subscriptions.ts';

// Apple retries anything but a 200, so only transient failures get a 500
const ok = () => new Response('ok', { status: 200 });

serve(async (req) => {
  if (req.method !== 'POST') return new Response('Method not allowed', { status: 405 });

  const credentials = credentialsFromEnv();
  if (!credentials) {
    console.error('App Store notification received, but the App Store secrets are not set');
    return new Response('Not configured', { status: 503 });
  }

  let payload: NotificationPayload;
  let transaction: TransactionInfo | null;
  try {
    const { signedPayload } = await req.json();
    payload = decodeJWSPayload<NotificationPayload>(signedPayload);
    transaction = payload.data?.signedTransactionInfo
      ? decodeJWSPayload<TransactionInfo>(payload.data.signedTransactionInfo)
      : null;
  } catch {
    return new Response('Bad request', { status: 400 });
  }

  // TEST notifications and other apps' traffic carry nothing to update
  if (!transaction || payload.data?.bundleId !== credentials.bundleId) {
    console.log(`App Store notification ${payload.notificationType} ignored`);
    return ok();
  }

  try {
    const status = await fetchSubscriptionStatus(credentials, transaction.originalTransactionId, payload.data?.environment);
    const state = status ? subscriptionState(status, PRO_PRODUCT_IDS) : null;
    if (!state) return ok();

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    );
    const owner = await ownerOf(supabase, state, null);
    if (!owner) {
      // Not linked yet: the app links it with verify-purchase after the purchase
      return ok();
    }
    const { data: account } = await supabase.from('users').select('id').eq('id', owner).maybeSingle();
    if (!account) {
      // The account was deleted; the subscription itself is cancelled in the App Store
      return ok();
    }

    await storeSubscription(supabase, owner, state);
    await refreshUserTier(supabase, owner);
    console.log(`App Store ${payload.notificationType}${payload.subtype ? `/${payload.subtype}` : ''}: status ${state.status}`);
    return ok();
  } catch (error) {
    console.error('app-store-notifications error:', error);
    return new Response('Try again', { status: 500 });
  }
});
