-- ============================================
-- Saved quotes: the lines a reader bookmarks, from any save.
--
-- A quote card's bookmark adds a row here; the Quotes tab lists them across
-- the whole library, newest first. The text is copied (not referenced by
-- position) so a quote survives the document's body being re-cleaned.
-- ============================================

CREATE TABLE saved_quotes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL DEFAULT auth.uid() REFERENCES users(id) ON DELETE CASCADE,
  document_id UUID NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
  text TEXT NOT NULL CHECK (char_length(text) BETWEEN 1 AND 1000),
  -- false for the hook (Sangrah's summary line), true for the author's own words
  is_verbatim BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  UNIQUE(user_id, document_id, text)
);

CREATE INDEX idx_saved_quotes_user_created ON saved_quotes(user_id, created_at DESC);
CREATE INDEX idx_saved_quotes_document ON saved_quotes(document_id);

ALTER TABLE saved_quotes ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can manage own saved quotes" ON saved_quotes
  FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (
    auth.uid() = user_id
    AND EXISTS (SELECT 1 FROM documents WHERE documents.id = saved_quotes.document_id AND documents.user_id = auth.uid())
  );
