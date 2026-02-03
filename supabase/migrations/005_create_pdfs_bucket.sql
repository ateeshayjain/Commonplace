-- Create the pdfs storage bucket
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('pdfs', 'pdfs', true, 52428800, ARRAY['application/pdf'])
ON CONFLICT (id) DO NOTHING;

-- Allow authenticated users to upload PDFs to their own folder
CREATE POLICY "Users can upload own PDFs" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'pdfs' AND (storage.foldername(name))[1] = auth.uid()::text);

-- Allow public read access to PDFs
CREATE POLICY "Public can read PDFs" ON storage.objects
  FOR SELECT TO public
  USING (bucket_id = 'pdfs');

-- Allow service role to manage all PDFs (for Edge Functions)
CREATE POLICY "Service role can manage PDFs" ON storage.objects
  FOR ALL TO service_role
  USING (bucket_id = 'pdfs');
