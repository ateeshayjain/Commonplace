-- Migration 003: Auth and search fixes

-- ============================================
-- USERS: allow first-sign-in profile creation
-- ============================================
-- AuthService inserts the profile row on first sign-in; without this policy RLS blocks it.
-- New profiles must start on the free tier.
CREATE POLICY "Users can create own profile" ON users
  FOR INSERT WITH CHECK (auth.uid() = id AND subscription_tier = 'free');

-- ============================================
-- SEARCH: scope to the signed-in user
-- ============================================
-- The previous version was SECURITY DEFINER and trusted a caller-supplied p_user_id,
-- so any signed-in user could search anyone's documents. The iOS client also calls it
-- without p_user_id. Use auth.uid() and run with the caller's privileges so RLS applies.
DROP FUNCTION IF EXISTS search_documents(UUID, TEXT, INTEGER);

CREATE OR REPLACE FUNCTION search_documents(
  p_query TEXT,
  p_limit INTEGER DEFAULT 20
)
RETURNS TABLE (
  id UUID,
  title TEXT,
  ai_summary_short TEXT,
  source_type TEXT,
  author_name TEXT,
  created_at TIMESTAMPTZ,
  rank REAL
)
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_catalog
AS $$
BEGIN
  RETURN QUERY
  SELECT
    d.id,
    d.title,
    d.ai_summary_short,
    d.source_type,
    d.author_name,
    d.created_at,
    ts_rank(to_tsvector('english', d.title || ' ' || COALESCE(d.body_plain, '')), plainto_tsquery('english', p_query)) AS rank
  FROM documents d
  WHERE d.user_id = auth.uid()
    AND d.processing_status = 'completed'
    AND to_tsvector('english', d.title || ' ' || COALESCE(d.body_plain, '')) @@ plainto_tsquery('english', p_query)
  ORDER BY rank DESC
  LIMIT p_limit;
END;
$$;

-- ============================================
-- TRIGGER FUNCTIONS: pin search_path
-- ============================================
ALTER FUNCTION update_updated_at() SET search_path = public, pg_catalog;
ALTER FUNCTION update_social_connections_updated_at() SET search_path = public, pg_catalog;
