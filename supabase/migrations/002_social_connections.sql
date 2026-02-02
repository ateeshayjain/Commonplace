-- Social connections table for OAuth tokens
CREATE TABLE IF NOT EXISTS social_connections (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    platform TEXT NOT NULL CHECK (platform IN ('twitter', 'linkedin', 'instagram', 'threads')),
    platform_user_id TEXT NOT NULL,
    platform_username TEXT,
    platform_display_name TEXT,
    platform_avatar_url TEXT,
    access_token TEXT,
    refresh_token TEXT,
    token_expires_at TIMESTAMPTZ,
    connected_at TIMESTAMPTZ DEFAULT NOW(),
    disconnected_at TIMESTAMPTZ,
    is_active BOOLEAN DEFAULT true,
    last_used_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),

    UNIQUE(user_id, platform)
);

-- Enable RLS
ALTER TABLE social_connections ENABLE ROW LEVEL SECURITY;

-- RLS Policies - users can only access their own connections
CREATE POLICY "Users can view own connections"
    ON social_connections FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own connections"
    ON social_connections FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own connections"
    ON social_connections FOR UPDATE
    USING (auth.uid() = user_id);

CREATE POLICY "Users can delete own connections"
    ON social_connections FOR DELETE
    USING (auth.uid() = user_id);

-- Index for faster lookups
CREATE INDEX idx_social_connections_user ON social_connections(user_id);
CREATE INDEX idx_social_connections_platform ON social_connections(platform);

-- Updated trigger
CREATE OR REPLACE FUNCTION update_social_connections_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_social_connections_updated_at
    BEFORE UPDATE ON social_connections
    FOR EACH ROW
    EXECUTE FUNCTION update_social_connections_updated_at();

-- Storage bucket for PDFs (if not exists)
INSERT INTO storage.buckets (id, name, public)
VALUES ('pdfs', 'pdfs', true)
ON CONFLICT (id) DO NOTHING;

-- Storage policy for PDFs
CREATE POLICY "Users can upload their own PDFs"
    ON storage.objects FOR INSERT
    WITH CHECK (
        bucket_id = 'pdfs'
        AND auth.uid()::text = (storage.foldername(name))[1]
    );

CREATE POLICY "Users can view their own PDFs"
    ON storage.objects FOR SELECT
    USING (
        bucket_id = 'pdfs'
        AND auth.uid()::text = (storage.foldername(name))[1]
    );

CREATE POLICY "Public can view PDFs"
    ON storage.objects FOR SELECT
    USING (bucket_id = 'pdfs');
