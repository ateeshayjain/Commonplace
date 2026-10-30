-- ============================================
-- Screenshot saves: images shared to Sangrah from Photos.
--
-- The Share Extension uploads each screenshot (JPEG, resized on the phone)
-- to screenshots/{user_id}/{batch_id}/{n}.jpg with the user's own token, then
-- asks process-url to read them. process-url downloads them with the service
-- role, has Claude transcribe them in order into one saved article, and keeps
-- the paths in documents.metadata.screenshotPaths.
-- ============================================

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('screenshots', 'screenshots', false, 6291456, ARRAY['image/jpeg'])
ON CONFLICT (id) DO NOTHING;

CREATE POLICY "Users can upload own screenshots"
  ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'screenshots'
    AND auth.uid()::text = (storage.foldername(name))[1]
  );

CREATE POLICY "Users can view own screenshots"
  ON storage.objects FOR SELECT
  USING (
    bucket_id = 'screenshots'
    AND auth.uid()::text = (storage.foldername(name))[1]
  );

CREATE POLICY "Users can delete own screenshots"
  ON storage.objects FOR DELETE
  USING (
    bucket_id = 'screenshots'
    AND auth.uid()::text = (storage.foldername(name))[1]
  );
