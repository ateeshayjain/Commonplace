-- Allow authenticated users to insert their own row
CREATE POLICY "Users can insert own data" ON users
  FOR INSERT WITH CHECK (auth.uid() = id);

-- Create a trigger function to auto-create user profile on signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
BEGIN
  INSERT INTO public.users (id, email, subscription_tier, reading_profile, settings, created_at, updated_at)
  VALUES (
    NEW.id,
    NEW.email,
    'free',
    '{"complexity_preference": 5, "topics": [], "preferred_sources": [], "reading_speed_wpm": 200}'::jsonb,
    '{"notifications_enabled": true, "email_digest": "weekly", "default_categories": [], "theme": "system"}'::jsonb,
    NOW(),
    NOW()
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger on auth.users insert
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();
