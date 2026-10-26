-- Migration 005: book_ocr source type (Phase 1, book scanning)
-- NOT YET APPLIED to the live project: DROP CONSTRAINT needs a Supabase dashboard confirmation.
-- Apply from the SQL editor or `supabase db push` when book scanning ships.
ALTER TABLE documents DROP CONSTRAINT documents_source_type_check;
ALTER TABLE documents ADD CONSTRAINT documents_source_type_check CHECK (source_type IN (
  'twitter', 'linkedin', 'linkedin_article', 'article', 'substack',
  'medium', 'youtube', 'podcast', 'pdf', 'reddit', 'hackernews',
  'instagram', 'threads', 'email', 'screenshot', 'manual', 'unknown',
  'book_ocr'
));
