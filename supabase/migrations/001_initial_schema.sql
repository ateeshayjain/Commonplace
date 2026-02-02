-- Commonplace Database Schema
-- Migration 001: Initial Schema

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================
-- USERS TABLE
-- ============================================
CREATE TABLE users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email TEXT UNIQUE NOT NULL,
  full_name TEXT,
  avatar_url TEXT,
  subscription_tier TEXT DEFAULT 'free' CHECK (subscription_tier IN ('free', 'pro', 'creator', 'team')),
  subscription_expires_at TIMESTAMPTZ,

  -- Reading profile (JSONB for flexibility)
  reading_profile JSONB DEFAULT '{
    "complexity_preference": 5,
    "topics": [],
    "preferred_sources": [],
    "reading_speed_wpm": 200
  }'::jsonb,

  -- Settings
  settings JSONB DEFAULT '{
    "notifications_enabled": true,
    "email_digest": "weekly",
    "default_categories": [],
    "theme": "system"
  }'::jsonb,

  -- Timestamps
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  last_active_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes
CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_subscription ON users(subscription_tier);

-- ============================================
-- DOCUMENTS TABLE
-- ============================================
CREATE TABLE documents (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

  -- Source Information
  source_type TEXT NOT NULL CHECK (source_type IN (
    'twitter', 'linkedin', 'linkedin_article', 'article', 'substack',
    'medium', 'youtube', 'podcast', 'pdf', 'reddit', 'hackernews',
    'instagram', 'threads', 'email', 'screenshot', 'manual', 'unknown'
  )),
  source_url TEXT,
  source_domain TEXT,
  captured_at TIMESTAMPTZ DEFAULT NOW(),
  original_published_at TIMESTAMPTZ,
  is_source_deleted BOOLEAN DEFAULT FALSE,

  -- Author Information
  author_name TEXT,
  author_handle TEXT,
  author_url TEXT,
  author_avatar_url TEXT,

  -- Content
  title TEXT NOT NULL,
  subtitle TEXT,
  body_plain TEXT NOT NULL,
  body_structured JSONB,
  word_count INTEGER,
  reading_time_minutes INTEGER,
  language TEXT DEFAULT 'en',

  -- Social Context
  engagement JSONB DEFAULT '{
    "likes": null,
    "shares": null,
    "comments": null,
    "views": null
  }'::jsonb,
  comments_summary TEXT,
  sentiment TEXT CHECK (sentiment IN ('positive', 'negative', 'mixed', 'neutral')),

  -- Thread Information
  is_thread BOOLEAN DEFAULT FALSE,
  thread_position INTEGER,
  thread_total INTEGER,
  thread_id UUID,

  -- AI Enrichment
  ai_summary_short TEXT,
  ai_summary_long TEXT,
  ai_key_points JSONB,
  ai_categories JSONB,
  ai_topics JSONB,
  ai_complexity_score INTEGER CHECK (ai_complexity_score BETWEEN 1 AND 10),
  ai_reading_level TEXT CHECK (ai_reading_level IN ('casual', 'intermediate', 'advanced', 'expert')),
  ai_content_type TEXT CHECK (ai_content_type IN ('news', 'opinion', 'analysis', 'tutorial', 'thread', 'discussion')),
  ai_quotable_lines JSONB,

  -- Output
  pdf_url TEXT,
  pdf_version INTEGER DEFAULT 1,
  thumbnail_url TEXT,
  screenshot_url TEXT,

  -- User Data
  user_categories JSONB DEFAULT '[]'::jsonb,
  user_notes TEXT,
  user_highlights JSONB DEFAULT '[]'::jsonb,
  is_favorite BOOLEAN DEFAULT FALSE,
  is_archived BOOLEAN DEFAULT FALSE,
  read_progress DECIMAL(3,2) DEFAULT 0 CHECK (read_progress BETWEEN 0 AND 1),
  last_read_at TIMESTAMPTZ,

  -- Processing Status
  processing_status TEXT DEFAULT 'pending' CHECK (processing_status IN (
    'pending', 'fetching', 'extracting', 'enriching', 'rendering', 'completed', 'failed'
  )),
  processing_error TEXT,

  -- Quality Flags
  is_complete BOOLEAN DEFAULT TRUE,
  missing_fields JSONB DEFAULT '[]'::jsonb,
  extraction_confidence DECIMAL(3,2) DEFAULT 1.0,

  -- Timestamps
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  processed_at TIMESTAMPTZ
);

-- Indexes
CREATE INDEX idx_documents_user ON documents(user_id);
CREATE INDEX idx_documents_user_created ON documents(user_id, created_at DESC);
CREATE INDEX idx_documents_source_type ON documents(source_type);
CREATE INDEX idx_documents_thread ON documents(thread_id) WHERE thread_id IS NOT NULL;
CREATE INDEX idx_documents_status ON documents(processing_status) WHERE processing_status != 'completed';
CREATE INDEX idx_documents_search ON documents USING gin(to_tsvector('english', title || ' ' || body_plain));
CREATE INDEX idx_documents_categories ON documents USING gin(user_categories);
CREATE INDEX idx_documents_favorite ON documents(user_id) WHERE is_favorite = TRUE;

-- ============================================
-- CATEGORIES TABLE
-- ============================================
CREATE TABLE categories (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  slug TEXT NOT NULL,
  icon TEXT,
  color TEXT,
  is_system BOOLEAN DEFAULT FALSE,
  sort_order INTEGER DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW(),

  UNIQUE(user_id, slug)
);

-- System categories (user_id = NULL)
INSERT INTO categories (user_id, name, slug, icon, color, is_system, sort_order) VALUES
  (NULL, 'Technology', 'technology', '💻', '#007AFF', TRUE, 1),
  (NULL, 'Business', 'business', '📊', '#34C759', TRUE, 2),
  (NULL, 'Health', 'health', '🏥', '#FF3B30', TRUE, 3),
  (NULL, 'Science', 'science', '🔬', '#AF52DE', TRUE, 4),
  (NULL, 'Culture', 'culture', '🎭', '#FF9500', TRUE, 5),
  (NULL, 'Politics', 'politics', '🏛️', '#5856D6', TRUE, 6),
  (NULL, 'Design', 'design', '🎨', '#FF2D55', TRUE, 7),
  (NULL, 'Personal Dev', 'personal-dev', '🧠', '#00C7BE', TRUE, 8);

-- ============================================
-- MEDIA TABLE
-- ============================================
CREATE TABLE media (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  document_id UUID NOT NULL REFERENCES documents(id) ON DELETE CASCADE,

  type TEXT NOT NULL CHECK (type IN ('image', 'video', 'audio', 'document')),
  original_url TEXT,
  stored_url TEXT NOT NULL,
  mime_type TEXT NOT NULL,

  width INTEGER,
  height INTEGER,
  duration_seconds INTEGER,
  file_size_bytes BIGINT,

  alt_text TEXT,
  caption TEXT,
  ocr_text TEXT,

  is_featured BOOLEAN DEFAULT FALSE,
  sort_order INTEGER DEFAULT 0,

  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_media_document ON media(document_id);
CREATE INDEX idx_media_featured ON media(document_id) WHERE is_featured = TRUE;

-- ============================================
-- VOICE PROFILES TABLE (Phase 2)
-- ============================================
CREATE TABLE voice_profiles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

  platform TEXT NOT NULL CHECK (platform IN (
    'twitter', 'linkedin', 'facebook', 'instagram', 'threads', 'medium', 'substack', 'email'
  )),

  description TEXT,

  tone_formality INTEGER DEFAULT 5 CHECK (tone_formality BETWEEN 1 AND 10),
  tone_humor INTEGER DEFAULT 5 CHECK (tone_humor BETWEEN 1 AND 10),
  tone_opinion INTEGER DEFAULT 5 CHECK (tone_opinion BETWEEN 1 AND 10),

  avoid_phrases JSONB DEFAULT '[]'::jsonb,
  example_posts JSONB DEFAULT '[]'::jsonb,
  learned_patterns JSONB DEFAULT '{}'::jsonb,

  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),

  UNIQUE(user_id, platform)
);

-- ============================================
-- CAMPAIGNS TABLE (Phase 2)
-- ============================================
CREATE TABLE campaigns (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

  source_document_id UUID REFERENCES documents(id) ON DELETE SET NULL,
  source_text TEXT NOT NULL,

  detected_intent TEXT CHECK (detected_intent IN (
    'complaint', 'announcement', 'thought_leadership', 'tutorial',
    'question', 'story', 'promotion', 'update', 'other'
  )),

  status TEXT DEFAULT 'draft' CHECK (status IN ('draft', 'generated', 'published', 'scheduled')),
  scheduled_at TIMESTAMPTZ,

  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- CAMPAIGN POSTS TABLE
-- ============================================
CREATE TABLE campaign_posts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  campaign_id UUID NOT NULL REFERENCES campaigns(id) ON DELETE CASCADE,

  platform TEXT NOT NULL CHECK (platform IN (
    'twitter', 'linkedin', 'facebook', 'instagram', 'threads', 'medium', 'substack', 'email'
  )),

  content TEXT NOT NULL,
  content_parts JSONB,

  format TEXT NOT NULL CHECK (format IN ('single', 'thread', 'article', 'caption', 'newsletter')),
  character_count INTEGER,

  is_published BOOLEAN DEFAULT FALSE,
  published_at TIMESTAMPTZ,
  published_url TEXT,

  is_edited BOOLEAN DEFAULT FALSE,
  original_content TEXT,

  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_campaign_posts_campaign ON campaign_posts(campaign_id);

-- ============================================
-- ROW LEVEL SECURITY
-- ============================================
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE media ENABLE ROW LEVEL SECURITY;
ALTER TABLE voice_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE campaigns ENABLE ROW LEVEL SECURITY;
ALTER TABLE campaign_posts ENABLE ROW LEVEL SECURITY;

-- Users policies
CREATE POLICY "Users can view own data" ON users
  FOR SELECT USING (auth.uid() = id);

CREATE POLICY "Users can update own data" ON users
  FOR UPDATE USING (auth.uid() = id);

-- Documents policies
CREATE POLICY "Users can view own documents" ON documents
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can create documents" ON documents
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own documents" ON documents
  FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY "Users can delete own documents" ON documents
  FOR DELETE USING (auth.uid() = user_id);

-- Categories policies
CREATE POLICY "Users can view system and own categories" ON categories
  FOR SELECT USING (user_id IS NULL OR auth.uid() = user_id);

CREATE POLICY "Users can create own categories" ON categories
  FOR INSERT WITH CHECK (auth.uid() = user_id AND is_system = FALSE);

-- Media policies
CREATE POLICY "Users can view media of own documents" ON media
  FOR SELECT USING (
    EXISTS (SELECT 1 FROM documents WHERE documents.id = media.document_id AND documents.user_id = auth.uid())
  );

-- Voice profiles policies
CREATE POLICY "Users can manage own voice profiles" ON voice_profiles
  FOR ALL USING (auth.uid() = user_id);

-- Campaigns policies
CREATE POLICY "Users can manage own campaigns" ON campaigns
  FOR ALL USING (auth.uid() = user_id);

-- Campaign posts policies
CREATE POLICY "Users can manage posts of own campaigns" ON campaign_posts
  FOR ALL USING (
    EXISTS (SELECT 1 FROM campaigns WHERE campaigns.id = campaign_posts.campaign_id AND campaigns.user_id = auth.uid())
  );

-- ============================================
-- FUNCTIONS
-- ============================================

-- Update timestamps trigger
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply triggers
CREATE TRIGGER update_users_updated_at BEFORE UPDATE ON users
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER update_documents_updated_at BEFORE UPDATE ON documents
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER update_voice_profiles_updated_at BEFORE UPDATE ON voice_profiles
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER update_campaigns_updated_at BEFORE UPDATE ON campaigns
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER update_campaign_posts_updated_at BEFORE UPDATE ON campaign_posts
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- Full-text search function
CREATE OR REPLACE FUNCTION search_documents(
  p_user_id UUID,
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
) AS $$
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
  WHERE d.user_id = p_user_id
    AND d.processing_status = 'completed'
    AND to_tsvector('english', d.title || ' ' || COALESCE(d.body_plain, '')) @@ plainto_tsquery('english', p_query)
  ORDER BY rank DESC
  LIMIT p_limit;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
