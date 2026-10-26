-- Migration 004: SangrahAI data model
-- Maps the SangrahAI PRD (section 5) onto the existing schema:
--   SavedItem      -> documents (+ ai_hook, metadata; 'book_ocr' source type in 005)
--   Tag            -> tags + document_tags (per-user, deduplicated by slug)
--   Collection     -> collections + collection_documents
--   GeneratedAsset -> generated_assets (+ private 'generated-assets' storage bucket)

-- ============================================
-- DOCUMENTS: PRD summary structure + ingestion metadata
-- ============================================
-- (book_ocr source type is added in 005; it needs a constraint drop, which requires dashboard confirmation)

-- hook: single-sentence overview (PRD: max 150 chars; enforced at generation, column allows 255)
-- executiveSummary maps to ai_summary_long, keyTakeaways to ai_key_points
ALTER TABLE documents ADD COLUMN ai_hook TEXT CHECK (char_length(ai_hook) <= 255);

-- Source-specific metadata, e.g. YouTube channel/views/chapters, OCR page count
ALTER TABLE documents ADD COLUMN metadata JSONB NOT NULL DEFAULT '{}'::jsonb;

-- ============================================
-- TAGS (per-user; near-duplicates collapse onto one slug)
-- ============================================
CREATE TABLE tags (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name TEXT NOT NULL CHECK (char_length(name) BETWEEN 1 AND 64),
  -- "Design Trends", "design-trends" and "DesignTrends" all map to "designtrends".
  -- Strips only ASCII whitespace/punctuation: [:punct:] would also strip combining marks
  -- such as the Devanagari virama and mangle non-Latin tags.
  slug TEXT GENERATED ALWAYS AS (lower(regexp_replace(name, '[ \t\n\r!-/:-@[-`{-~]+', '', 'g'))) STORED,
  created_at TIMESTAMPTZ DEFAULT NOW(),

  UNIQUE(user_id, slug)
);

CREATE TABLE document_tags (
  document_id UUID NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
  tag_id UUID NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
  source TEXT NOT NULL DEFAULT 'ai' CHECK (source IN ('ai', 'user')),
  created_at TIMESTAMPTZ DEFAULT NOW(),

  PRIMARY KEY (document_id, tag_id)
);

CREATE INDEX idx_document_tags_tag ON document_tags(tag_id);

-- ============================================
-- COLLECTIONS
-- ============================================
CREATE TABLE collections (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  description TEXT,
  is_public BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_collections_user ON collections(user_id);

CREATE TABLE collection_documents (
  collection_id UUID NOT NULL REFERENCES collections(id) ON DELETE CASCADE,
  document_id UUID NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
  sort_order INTEGER DEFAULT 0,
  added_at TIMESTAMPTZ DEFAULT NOW(),

  PRIMARY KEY (collection_id, document_id)
);

CREATE INDEX idx_collection_documents_document ON collection_documents(document_id);

CREATE TRIGGER update_collections_updated_at BEFORE UPDATE ON collections
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ============================================
-- GENERATED ASSETS (Module 3 + 4 outputs)
-- ============================================
CREATE TABLE generated_assets (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

  -- Single-source assets set document_id; dossiers/syntheses list every source
  document_id UUID REFERENCES documents(id) ON DELETE SET NULL,
  source_document_ids UUID[] NOT NULL DEFAULT '{}',
  collection_id UUID REFERENCES collections(id) ON DELETE SET NULL,

  format TEXT NOT NULL CHECK (format IN (
    'pdf_dossier', 'carousel_image_pack', 'quote_graphic', 'short_video_script', 'generated_video'
  )),
  status TEXT NOT NULL DEFAULT 'queued' CHECK (status IN ('queued', 'processing', 'completed', 'failed')),

  params JSONB NOT NULL DEFAULT '{}'::jsonb,       -- request parameters (theme, slide count, style preset, duration)
  content JSONB,                                   -- generated text payload (slide script, quote, video script)
  storage_paths TEXT[] NOT NULL DEFAULT '{}',      -- files in the generated-assets bucket, in display order
  error TEXT,

  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  completed_at TIMESTAMPTZ
);

CREATE INDEX idx_generated_assets_user_created ON generated_assets(user_id, created_at DESC);
CREATE INDEX idx_generated_assets_document ON generated_assets(document_id) WHERE document_id IS NOT NULL;
CREATE INDEX idx_generated_assets_pending ON generated_assets(status) WHERE status IN ('queued', 'processing');

CREATE TRIGGER update_generated_assets_updated_at BEFORE UPDATE ON generated_assets
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ============================================
-- ROW LEVEL SECURITY
-- ============================================
ALTER TABLE tags ENABLE ROW LEVEL SECURITY;
ALTER TABLE document_tags ENABLE ROW LEVEL SECURITY;
ALTER TABLE collections ENABLE ROW LEVEL SECURITY;
ALTER TABLE collection_documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE generated_assets ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can manage own tags" ON tags
  FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can tag own documents" ON document_tags
  FOR ALL
  USING (EXISTS (SELECT 1 FROM documents WHERE documents.id = document_tags.document_id AND documents.user_id = auth.uid()))
  WITH CHECK (
    EXISTS (SELECT 1 FROM documents WHERE documents.id = document_tags.document_id AND documents.user_id = auth.uid())
    AND EXISTS (SELECT 1 FROM tags WHERE tags.id = document_tags.tag_id AND tags.user_id = auth.uid())
  );

CREATE POLICY "Users can manage own collections" ON collections
  FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Public collections are viewable" ON collections
  FOR SELECT USING (is_public = TRUE);

CREATE POLICY "Users can manage items in own collections" ON collection_documents
  FOR ALL
  USING (EXISTS (SELECT 1 FROM collections WHERE collections.id = collection_documents.collection_id AND collections.user_id = auth.uid()))
  WITH CHECK (
    EXISTS (SELECT 1 FROM collections WHERE collections.id = collection_documents.collection_id AND collections.user_id = auth.uid())
    AND EXISTS (SELECT 1 FROM documents WHERE documents.id = collection_documents.document_id AND documents.user_id = auth.uid())
  );

CREATE POLICY "Items in public collections are viewable" ON collection_documents
  FOR SELECT USING (EXISTS (SELECT 1 FROM collections WHERE collections.id = collection_documents.collection_id AND collections.is_public = TRUE));

-- Assets are created and updated by Edge Functions (service role); users read and delete their own
CREATE POLICY "Users can view own generated assets" ON generated_assets
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can delete own generated assets" ON generated_assets
  FOR DELETE USING (auth.uid() = user_id);

-- ============================================
-- STORAGE: generated assets (private, served via signed URLs)
-- ============================================
INSERT INTO storage.buckets (id, name, public)
VALUES ('generated-assets', 'generated-assets', false)
ON CONFLICT (id) DO NOTHING;

-- Objects live under {user_id}/...; Edge Functions upload with the service role
CREATE POLICY "Users can view own generated files"
  ON storage.objects FOR SELECT
  USING (
    bucket_id = 'generated-assets'
    AND auth.uid()::text = (storage.foldername(name))[1]
  );

CREATE POLICY "Users can delete own generated files"
  ON storage.objects FOR DELETE
  USING (
    bucket_id = 'generated-assets'
    AND auth.uid()::text = (storage.foldername(name))[1]
  );
