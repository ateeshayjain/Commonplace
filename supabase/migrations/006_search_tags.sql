-- ============================================
-- Search also matches tags, the AI summary and the author.
--
-- The Library no longer has a tag filter row (categories cover the broad
-- topic, sources cover where it came from), so tags are found through
-- search instead. Weights: title A, tags and author B, summary C, body D.
-- ============================================

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
  WITH q AS (
    SELECT plainto_tsquery('english', p_query) AS query
  ),
  docs AS (
    SELECT
      d.id,
      d.title,
      d.ai_summary_short,
      d.source_type,
      d.author_name,
      d.created_at,
      setweight(to_tsvector('english', COALESCE(d.title, '')), 'A') ||
      setweight(to_tsvector('english', COALESCE((
        SELECT string_agg(t.name, ' ')
        FROM document_tags dt
        JOIN tags t ON t.id = dt.tag_id
        WHERE dt.document_id = d.id
      ), '') || ' ' || COALESCE(d.author_name, '')), 'B') ||
      setweight(to_tsvector('english', COALESCE(d.ai_summary_short, '')), 'C') ||
      setweight(to_tsvector('english', COALESCE(d.body_plain, '')), 'D') AS doc
    FROM documents d
    WHERE d.user_id = auth.uid()
      AND d.processing_status = 'completed'
  )
  SELECT
    docs.id,
    docs.title,
    docs.ai_summary_short,
    docs.source_type,
    docs.author_name,
    docs.created_at,
    ts_rank(docs.doc, q.query) AS rank
  FROM docs, q
  WHERE docs.doc @@ q.query
  ORDER BY rank DESC
  LIMIT p_limit;
END;
$$;
