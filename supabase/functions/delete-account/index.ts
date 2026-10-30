// Supabase Edge Function: delete-account
// Deletes the signed-in reader's account and everything in it, for Profile >
// Delete Account (App Store guideline 5.1.1(v)). Order: storage files first,
// then the public.users row (cascades to documents, quotes, tags, categories,
// collections, campaigns, generated assets), then the auth user (cascades
// sessions, identities and social connections). A failure part-way leaves the
// account signed in, so the reader can simply try again.

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

// Buckets that keep each reader's files under {user_id}/
const USER_BUCKETS = ['pdfs', 'screenshots', 'generated-assets'];
const PAGE_SIZE = 1000;

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) {
      return json({ error: 'Missing authorization header' }, 401);
    }

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    );

    // The account to delete is whoever the token belongs to, never a parameter
    const token = authHeader.replace('Bearer ', '');
    const { data: { user }, error: authError } = await supabase.auth.getUser(token);
    if (authError || !user) {
      return json({ error: 'Unauthorized' }, 401);
    }

    for (const bucket of USER_BUCKETS) {
      const paths = await listFiles(supabase, bucket, user.id);
      for (let i = 0; i < paths.length; i += 100) {
        const { error } = await supabase.storage.from(bucket).remove(paths.slice(i, i + 100));
        if (error) throw new Error(`Couldn't remove files from ${bucket}: ${error.message}`);
      }
    }

    const { error: rowsError } = await supabase.from('users').delete().eq('id', user.id);
    if (rowsError) throw new Error(`Couldn't delete saved data: ${rowsError.message}`);

    const { error: deleteError } = await supabase.auth.admin.deleteUser(user.id);
    if (deleteError) throw new Error(`Couldn't delete the sign-in: ${deleteError.message}`);

    console.log(`Deleted account ${user.id}`);
    return json({ deleted: true }, 200);
  } catch (error) {
    console.error('delete-account failed:', error);
    return json({ error: error instanceof Error ? error.message : 'Unknown error' }, 500);
  }
});

/** Every file path under `prefix`, walking into folders (list() is one level deep) */
async function listFiles(supabase: SupabaseClient, bucket: string, prefix: string): Promise<string[]> {
  const files: string[] = [];
  for (let offset = 0; ; offset += PAGE_SIZE) {
    const { data, error } = await supabase.storage.from(bucket).list(prefix, { limit: PAGE_SIZE, offset });
    if (error) throw new Error(`Couldn't list files in ${bucket}: ${error.message}`);
    for (const item of data ?? []) {
      const path = `${prefix}/${item.name}`;
      // Folders come back with a null id
      if (item.id === null) {
        files.push(...await listFiles(supabase, bucket, path));
      } else {
        files.push(path);
      }
    }
    if (!data || data.length < PAGE_SIZE) return files;
  }
}

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}
