-- Migration 010: Free and Pro tiers
-- Free: up to 5 saves a day, no Claude. Pro: smart summaries (fair use),
-- Compose and post generation. Limits live in supabase/functions/_shared/tiers.ts;
-- this migration stores what they are checked against and stops users from
-- changing their own tier.

-- ============================================
-- USERS: only the service role changes the tier
-- ============================================
-- The "Users can update own data" policy (migration 001) covers every column,
-- so a signed-in user could PATCH their own subscription_tier to 'pro'.
-- RLS can't limit columns, so a trigger rejects tier changes made by app
-- users (PostgREST runs their requests as the `authenticated` role). Edge
-- Functions use the service role and pass through. SECURITY INVOKER (the
-- default) is required: current_user must be the caller, not the owner.
CREATE OR REPLACE FUNCTION protect_subscription_columns()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_catalog
AS $$
BEGIN
  IF current_user IN ('authenticated', 'anon') THEN
    IF TG_OP = 'INSERT' THEN
      IF NEW.subscription_tier IS DISTINCT FROM 'free' OR NEW.subscription_expires_at IS NOT NULL THEN
        RAISE EXCEPTION 'New accounts start on the free tier' USING ERRCODE = '42501';
      END IF;
    ELSIF NEW.subscription_tier IS DISTINCT FROM OLD.subscription_tier
       OR NEW.subscription_expires_at IS DISTINCT FROM OLD.subscription_expires_at THEN
      RAISE EXCEPTION 'The subscription tier is set by the server' USING ERRCODE = '42501';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER users_protect_subscription
  BEFORE INSERT OR UPDATE ON users
  FOR EACH ROW EXECUTE FUNCTION protect_subscription_columns();

-- ============================================
-- USAGE COUNTS: saves per day, smart summaries and Compose runs per month
-- ============================================
-- Counted separately from documents so deleting saves doesn't give them back.
-- Free accounts: 'save' per UTC day. Pro: 'smart_save' (Claude summaries,
-- fair use) and 'compose' per UTC calendar month.
CREATE TABLE usage_counts (
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  period DATE NOT NULL,  -- the UTC day ('save') or the first day of the UTC month
  feature TEXT NOT NULL CHECK (feature IN ('save', 'smart_save', 'compose')),
  used INTEGER NOT NULL DEFAULT 0 CHECK (used >= 0),
  PRIMARY KEY (user_id, period, feature)
);

ALTER TABLE usage_counts ENABLE ROW LEVEL SECURITY;

-- Readers see their own counts (Profile: "3 of 5 saves left today"); only
-- Edge Functions write them
CREATE POLICY "Users can view own usage" ON usage_counts
  FOR SELECT USING ((SELECT auth.uid()) = user_id);

-- Takes one use of `feature` in the current day or month (p_period) if fewer
-- than p_limit are used (p_limit NULL = unlimited, still counted). Returns the
-- period and the new count, or no row when the limit is reached. One
-- statement, so two saves arriving together can't both take the last one.
CREATE OR REPLACE FUNCTION claim_usage(p_user_id UUID, p_feature TEXT, p_limit INTEGER, p_period TEXT)
RETURNS TABLE (period DATE, used INTEGER)
LANGUAGE plpgsql
SET search_path = public, pg_catalog
AS $$
-- The output columns share names with usage_counts' columns
#variable_conflict use_column
DECLARE
  v_period DATE;
BEGIN
  IF p_period NOT IN ('day', 'month') THEN
    RAISE EXCEPTION 'p_period must be day or month';
  END IF;
  IF p_limit IS NOT NULL AND p_limit <= 0 THEN
    RETURN;
  END IF;
  v_period := date_trunc(p_period, now() AT TIME ZONE 'UTC')::date;

  RETURN QUERY
  INSERT INTO usage_counts AS u (user_id, period, feature, used)
  VALUES (p_user_id, v_period, p_feature, 1)
  ON CONFLICT (user_id, period, feature) DO UPDATE
    SET used = u.used + 1
    WHERE p_limit IS NULL OR u.used < p_limit
  RETURNING u.period, u.used;
END;
$$;

-- Gives a use back when the save or Claude call it was claimed for didn't happen
CREATE OR REPLACE FUNCTION release_usage(p_user_id UUID, p_feature TEXT, p_period DATE)
RETURNS void
LANGUAGE sql
SET search_path = public, pg_catalog
AS $$
  UPDATE usage_counts
  SET used = GREATEST(used - 1, 0)
  WHERE user_id = p_user_id AND feature = p_feature AND period = p_period;
$$;

REVOKE EXECUTE ON FUNCTION claim_usage(UUID, TEXT, INTEGER, TEXT) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION release_usage(UUID, TEXT, DATE) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION claim_usage(UUID, TEXT, INTEGER, TEXT) TO service_role;
GRANT EXECUTE ON FUNCTION release_usage(UUID, TEXT, DATE) TO service_role;

-- ============================================
-- DOCUMENTS: saves without a smart summary yet
-- ============================================
-- Free saves are stored with their text and no Claude call; a Pro save past
-- the monthly fair-use limit waits the same way. Both are marked completed so
-- they show in the Library, with ai_waiting set until they are summarised
-- (Summarise on a Pro account, or automatically after upgrading).
ALTER TABLE documents ADD COLUMN ai_waiting BOOLEAN NOT NULL DEFAULT FALSE;

CREATE INDEX idx_documents_ai_waiting ON documents(user_id, created_at DESC) WHERE ai_waiting;

-- ============================================
-- APP STORE SUBSCRIPTIONS: which account owns which purchase
-- ============================================
-- One row per App Store original transaction (a subscription, across its
-- renewals). Written by verify-purchase and app-store-notifications after
-- asking Apple's App Store Server API for the current status; users.subscription_tier
-- is derived from these rows.
CREATE TABLE app_store_subscriptions (
  original_transaction_id TEXT PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  product_id TEXT NOT NULL,
  -- App Store status: 1 active, 2 expired, 3 billing retry, 4 billing grace period, 5 revoked
  status INTEGER NOT NULL,
  -- End of paid (or grace-period) access
  expires_at TIMESTAMPTZ,
  -- Free-trial end, while the subscription is in its trial
  trial_ends_at TIMESTAMPTZ,
  auto_renews BOOLEAN NOT NULL DEFAULT TRUE,
  environment TEXT NOT NULL CHECK (environment IN ('Production', 'Sandbox')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_app_store_subscriptions_user ON app_store_subscriptions(user_id);

ALTER TABLE app_store_subscriptions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own App Store subscriptions" ON app_store_subscriptions
  FOR SELECT USING ((SELECT auth.uid()) = user_id);
