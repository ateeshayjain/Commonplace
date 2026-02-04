-- Rate limiting table for Edge Functions
CREATE TABLE IF NOT EXISTS rate_limits (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  function_name text NOT NULL,
  created_at timestamptz DEFAULT now() NOT NULL
);

CREATE INDEX idx_rate_limits_lookup ON rate_limits (user_id, function_name, created_at DESC);

-- Auto-cleanup old entries (older than 1 hour)
CREATE OR REPLACE FUNCTION cleanup_rate_limits() RETURNS void AS $$
  DELETE FROM rate_limits WHERE created_at < now() - interval '1 hour';
$$ LANGUAGE sql;

-- RLS: users can only see their own rate limit entries
ALTER TABLE rate_limits ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can read own rate limits" ON rate_limits
  FOR SELECT USING (auth.uid() = user_id);

-- Service role can insert (edge functions use service role key)
CREATE POLICY "Service role can insert rate limits" ON rate_limits
  FOR INSERT WITH CHECK (true);

CREATE POLICY "Service role can select rate limits" ON rate_limits
  FOR SELECT USING (true);
