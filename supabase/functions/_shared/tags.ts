// Tag helpers shared by Edge Functions.
// Mirrors the slug rule in migrations/004_sangrah_data_model.sql (tags.slug):
// lowercase, with ASCII whitespace and punctuation removed. Only ASCII is stripped
// so non-Latin scripts (e.g. Devanagari with its combining marks) survive intact.

// deno-lint-ignore no-explicit-any
type SupabaseClient = any;

export const MAX_TAGS_PER_DOCUMENT = 6;
export const MAX_TAG_LENGTH = 64;

export function slugify(name: string): string {
  return name.replace(/[ \t\n\r!-/:-@[-`{-~]+/g, '').toLowerCase();
}

// Trim, drop empties/overlong names, and collapse names that share a slug
export function normalizeTagNames(names: string[]): string[] {
  const seen = new Set<string>();
  const result: string[] = [];
  for (const raw of names) {
    const name = raw.trim().slice(0, MAX_TAG_LENGTH);
    const slug = slugify(name);
    if (!slug || seen.has(slug)) continue;
    seen.add(slug);
    result.push(name);
    if (result.length === MAX_TAGS_PER_DOCUMENT) break;
  }
  return result;
}

// The user's most recently created tags, for the prompt to reuse
export async function fetchRecentTagNames(
  supabase: SupabaseClient,
  userId: string,
  limit = 50
): Promise<string[]> {
  const { data, error } = await supabase
    .from('tags')
    .select('name')
    .eq('user_id', userId)
    .order('created_at', { ascending: false })
    .limit(limit);
  if (error) {
    console.error('Failed to fetch tags:', error);
    return [];
  }
  return (data ?? []).map((row: { name: string }) => row.name);
}

// Upsert tags by slug for the user and link them to the document
export async function attachTags(
  supabase: SupabaseClient,
  userId: string,
  documentId: string,
  names: string[],
  source: 'ai' | 'user' = 'ai'
): Promise<void> {
  const tagNames = normalizeTagNames(names);
  if (!tagNames.length) return;

  // Existing tags with the same slug win (ignoreDuplicates), so the user's spelling is kept
  const { error: upsertError } = await supabase
    .from('tags')
    .upsert(
      tagNames.map((name) => ({ user_id: userId, name })),
      { onConflict: 'user_id,slug', ignoreDuplicates: true }
    );
  if (upsertError) {
    console.error('Failed to upsert tags:', upsertError);
    return;
  }

  const slugs = tagNames.map(slugify);
  const { data: tags, error: selectError } = await supabase
    .from('tags')
    .select('id')
    .eq('user_id', userId)
    .in('slug', slugs);
  if (selectError || !tags?.length) {
    console.error('Failed to look up tags:', selectError);
    return;
  }

  const { error: linkError } = await supabase
    .from('document_tags')
    .upsert(
      tags.map((tag: { id: string }) => ({ document_id: documentId, tag_id: tag.id, source })),
      { onConflict: 'document_id,tag_id', ignoreDuplicates: true }
    );
  if (linkError) {
    console.error('Failed to link tags:', linkError);
  }
}
