// Supabase Edge Function: process-url
// Processes a URL, extracts content, generates AI summary, and creates PDF

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { Anthropic, CLAUDE_MODELS, generateJSON, type ImageInput } from '../_shared/claude.ts';
import { attachTags, fetchRecentTagNames } from '../_shared/tags.ts';
import { HOOK_MAX_CHARS, KEY_TAKEAWAY_COUNT, fitHook } from '../_shared/generation.ts';
import { cleanArticleMarkdown, scribdPagesToText } from '../_shared/markdown.ts';
import { QUOTE_MAX_CHARS, QUOTE_MAX_COUNT, verbatimQuotes } from '../_shared/quotes.ts';
import { SCREENSHOT_BUCKET, screenshotPaths } from '../_shared/screenshots.ts';
import { dailySaveLimitReached, proRequired, type LimitError, type Tier } from '../_shared/tiers.ts';
import { claimUsage, loadTier, releaseUsage, type UsageClaim } from '../_shared/usage.ts';

// Supabase Edge Runtime: keeps background work alive after the response is sent
declare const EdgeRuntime: { waitUntil(promise: Promise<unknown>): void } | undefined;

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

interface ProcessURLRequest {
  url?: string;
  categories?: string[];
  // Storage paths of screenshots shared from Photos, in order; sent instead of url
  screenshots?: string[];
  // Screenshots read on the device (free accounts): the joined text and a title
  screenshotText?: string;
  title?: string;
  // Pro: summarise one save that has no smart summary yet (documents.ai_waiting)
  documentId?: string;
  // Pro: summarise the newest saves without one (sent after upgrading)
  resumeWaiting?: boolean;
}

// Waiting saves summarised per resumeWaiting request; the app asks again on its next launch
const RESUME_BATCH = 10;

interface ExtractedContent {
  title: string;
  subtitle?: string;
  bodyPlain: string;
  authorName?: string;
  authorHandle?: string;
  publishedAt?: string;
  engagement?: {
    likes?: number;
    shares?: number;
    comments?: number;
    views?: number;
  };
  isThread?: boolean;
  threadParts?: string[];
  // Source-specific extras stored in documents.metadata (shape: DocumentMetadata in iOS)
  metadata?: Record<string, unknown>;
  // Images whose text is part of the content (Instagram carousel slides); read by Claude vision
  images?: string[];
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    // Get auth token
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) {
      throw new Error('Missing authorization header');
    }

    // Initialize Supabase client
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const supabase = createClient(supabaseUrl, supabaseKey);

    // Get user from token
    const token = authHeader.replace('Bearer ', '');
    const { data: { user }, error: authError } = await supabase.auth.getUser(token);

    if (authError || !user) {
      throw new Error('Unauthorized');
    }

    // Parse request
    const { url, categories = [], screenshots, screenshotText, title, documentId, resumeWaiting }: ProcessURLRequest =
      await req.json();
    const tier = await loadTier(supabase, user.id);

    if (documentId !== undefined || resumeWaiting) {
      if (tier === 'free') return limitResponse(proRequired('summary'));
      return await summariseWaiting(supabase, user.id, documentId);
    }

    if (screenshots !== undefined) {
      if (tier === 'free') {
        // Free accounts read screenshots on the device and send the text
        // (screenshotText); remove what a stale plan or an older build uploaded
        await removeScreenshots(supabase, user.id, screenshots);
        return limitResponse(proRequired('screenshots'));
      }
      return await saveScreenshots(supabase, user.id, screenshots, categories);
    }

    if (screenshotText !== undefined) {
      return await saveScreenshotText(supabase, user.id, tier, screenshotText, title, categories);
    }

    if (!url) {
      throw new Error('URL is required');
    }

    // Detect platform
    const platform = detectPlatform(url);

    // The same link shared twice is one item, not two
    const canonical = canonicalUrl(url);
    const { data: existing } = await supabase
      .from('documents')
      .select('id, processing_status')
      .eq('user_id', user.id)
      .in('source_url', [url, canonical])
      .neq('processing_status', 'failed')
      .order('created_at', { ascending: false })
      .limit(1);
    if (existing && existing.length > 0) {
      return new Response(
        JSON.stringify({ id: existing[0].id, status: existing[0].processing_status, message: 'Already saved' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 200 }
      );
    }

    // Free accounts: FREE_SAVES_PER_DAY saves a day (a repeat of a saved link, above, doesn't count)
    const daily = await claimDailySave(supabase, user.id, tier);
    if (daily === 'limit') return limitResponse(dailySaveLimitReached());

    // Create initial document record
    const { data: document, error: insertError } = await supabase
      .from('documents')
      .insert({
        user_id: user.id,
        source_type: platform,
        source_url: url,
        source_domain: extractDomain(url),
        title: 'Processing...',
        body_plain: '',
        processing_status: 'fetching',
        user_categories: categories,
      })
      .select()
      .single();

    if (insertError) {
      if (daily) await releaseUsage(supabase, daily);
      throw insertError;
    }

    // Process asynchronously; without waitUntil the runtime may kill this after responding
    const processing = processContent(supabase, user.id, document.id, url, platform, tier, categories.length === 0);
    if (typeof EdgeRuntime !== 'undefined') {
      EdgeRuntime.waitUntil(processing);
    }

    return new Response(
      JSON.stringify({
        id: document.id,
        status: 'processing',
        message: 'Document queued for processing',
      }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 200,
      }
    );

  } catch (error) {
    console.error('Error:', error);
    return new Response(
      JSON.stringify({ error: (error as Error).message }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 400,
      }
    );
  }
});

// Process content asynchronously
async function processContent(
  supabase: any,
  userId: string,
  documentId: string,
  url: string,
  platform: string,
  tier: Tier,
  autoCategorise: boolean
) {
  try {
    // Update status
    await supabase
      .from('documents')
      .update({ processing_status: 'extracting' })
      .eq('id', documentId);

    // Extract content based on platform
    const content = await extractContent(url, platform);

    // Update with extracted content
    await supabase
      .from('documents')
      .update({
        title: content.title,
        subtitle: content.subtitle,
        body_plain: content.bodyPlain,
        author_name: content.authorName,
        author_handle: content.authorHandle,
        original_published_at: content.publishedAt,
        engagement: content.engagement,
        is_thread: content.isThread || false,
        metadata: content.metadata ?? {},
        processing_status: 'enriching',
        word_count: content.bodyPlain.split(/\s+/).length,
        reading_time_minutes: Math.ceil(content.bodyPlain.split(/\s+/).length / 200),
      })
      .eq('id', documentId);

    // Free saves keep the clean text without a Claude call. Pro saves get the
    // smart summary while this month's fair use lasts; after that they wait.
    const claim = tier === 'pro' ? await claimSmartSave(supabase, userId) : null;
    if (!claim) {
      const metadata = content.metadata ?? {};
      await markWaiting(supabase, documentId, {
        metadata: content.images?.length ? { ...metadata, pendingImages: content.images } : metadata,
      });
      return;
    }

    await enrichStoredText(supabase, userId, documentId, content.title, content.bodyPlain, content.images ?? [], autoCategorise, claim);

  } catch (error) {
    console.error('Processing error:', error);
    await supabase
      .from('documents')
      .update({
        processing_status: 'failed',
        processing_error: (error as Error).message,
      })
      .eq('id', documentId);
  }
}

// Update with AI enrichment (PRD: hook / executiveSummary / keyTakeaways)
async function saveEnrichment(
  supabase: any,
  userId: string,
  documentId: string,
  aiEnrichment: Enrichment,
  autoCategorise: boolean
) {
  await supabase
    .from('documents')
    .update({
      ai_hook: aiEnrichment.hook,
      ai_summary_short: aiEnrichment.summaryShort,
      ai_summary_long: aiEnrichment.executiveSummary,
      ai_key_points: aiEnrichment.keyTakeaways,
      ai_quotable_lines: aiEnrichment.quotableLines,
      ai_categories: aiEnrichment.categories,
      ai_topics: aiEnrichment.tags, // kept for the current UI until tags are shown
      ai_complexity_score: aiEnrichment.complexityScore,
      ai_reading_level: aiEnrichment.readingLevel,
      // The Library filters, rows and detail read user_categories; when the
      // save did not name any, the AI's picks become the starting point
      // (the user can still edit them).
      ...(autoCategorise ? { user_categories: aiEnrichment.categories } : {}),
      processing_status: 'completed',
      ai_waiting: false,
      processed_at: new Date().toISOString(),
    })
    .eq('id', documentId);

  await attachTags(supabase, userId, documentId, aiEnrichment.tags);
}

// MARK: Limits

// 402 with a code the app turns into the paywall or a "limit reached" message
function limitResponse(limit: LimitError): Response {
  return new Response(
    JSON.stringify({ error: limit.message, code: limit.code }),
    { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 402 }
  );
}

// One of today's free saves. Null for Pro (saves aren't limited) and when the
// check itself fails: a free save costs no Claude call, so it goes through.
async function claimDailySave(supabase: any, userId: string, tier: Tier): Promise<UsageClaim | null | 'limit'> {
  if (tier === 'pro') return null;
  try {
    return (await claimUsage(supabase, userId, 'save', tier)) ?? 'limit';
  } catch (error) {
    console.error('Daily save check failed:', error);
    return null;
  }
}

// One smart summary from this month's Pro fair use. Null when it's used up,
// and also when the check itself fails: the save then waits rather than
// running Claude unmetered.
async function claimSmartSave(supabase: any, userId: string): Promise<UsageClaim | null> {
  try {
    return await claimUsage(supabase, userId, 'smart_save', 'pro');
  } catch (error) {
    console.error('Smart summary check failed:', error);
    return null;
  }
}

// Stored and shown in the Library, without a smart summary (free saves, and
// Pro saves past the month's fair use)
async function markWaiting(supabase: any, documentId: string, fields: Record<string, unknown> = {}) {
  await supabase
    .from('documents')
    .update({ ...fields, processing_status: 'completed', ai_waiting: true })
    .eq('id', documentId);
}

// Summarises a link save's stored text (plus any slide images) on the claim's
// model. The claim is used up only if Claude answers: otherwise it is given
// back, and a new save gets the plain-text summary it always got while a
// resumed one goes back to waiting.
async function enrichStoredText(
  supabase: any,
  userId: string,
  documentId: string,
  title: string,
  body: string,
  imageUrls: string[],
  autoCategorise: boolean,
  claim: UsageClaim,
  resuming = false
) {
  let enriched: Enrichment | null = null;
  try {
    // Reuse the user's existing tags where they fit
    const existingTags = await fetchRecentTagNames(supabase, userId);
    const slideImages = await downloadImages(imageUrls);
    enriched = await generateAIEnrichment(title, body, existingTags, slideImages);
  } finally {
    if (!enriched) await releaseUsage(supabase, claim);
  }
  if (!enriched && resuming) {
    await markWaiting(supabase, documentId);
    return;
  }
  const aiEnrichment = enriched ?? fallbackEnrichment(body);

  // Slide text read from the images becomes part of the saved body
  if (aiEnrichment.transcribedText) {
    const combined = `${body}\n\n${aiEnrichment.transcribedText}`.trim();
    await supabase
      .from('documents')
      .update({
        body_plain: combined,
        word_count: combined.split(/\s+/).length,
        reading_time_minutes: Math.ceil(combined.split(/\s+/).length / 200),
      })
      .eq('id', documentId);
  }

  await saveEnrichment(supabase, userId, documentId, aiEnrichment, autoCategorise);
}

// Pro: summarises saves that have no smart summary yet: one (Summarise on the
// save) or the newest RESUME_BATCH (after upgrading). The stored text is used
// as is, so a link that has since gone offline still gets its summary.
async function summariseWaiting(supabase: any, userId: string, documentId: string | undefined): Promise<Response> {
  let query = supabase
    .from('documents')
    .select('id, source_type, title, body_plain, metadata, user_categories')
    .eq('user_id', userId)
    .eq('ai_waiting', true);
  query = documentId ? query.eq('id', documentId) : query.order('created_at', { ascending: false }).limit(RESUME_BATCH);
  const { data: waiting, error } = await query;
  if (error) throw error;

  const started: string[] = [];
  let limitReached = false;
  for (const doc of waiting ?? []) {
    // Readers can edit their own rows, metadata included, and the downloads
    // below run with the service role: check stored paths and URLs again
    // Screenshots read on the device have only text, summarised like a link's
    const storedPaths = doc.source_type === 'screenshot' ? doc.metadata?.screenshotPaths : undefined;
    const paths = storedPaths !== undefined ? screenshotPaths(storedPaths, userId) : null;
    if (storedPaths !== undefined && !paths) {
      console.log(`Waiting save ${doc.id} has invalid screenshot paths; skipped`);
      continue;
    }
    const pendingImages = Array.isArray(doc.metadata?.pendingImages)
      ? doc.metadata.pendingImages.filter((url: unknown): url is string => typeof url === 'string').slice(0, 10)
      : [];

    // Take the document first so two taps (or two devices) can't summarise it twice
    const { data: taken } = await supabase
      .from('documents')
      .update({ ai_waiting: false })
      .eq('id', doc.id)
      .eq('ai_waiting', true)
      .select('id');
    if (!taken?.length) continue;

    const claim = await claimSmartSave(supabase, userId);
    if (!claim) {
      await markWaiting(supabase, doc.id);
      limitReached = true;
      break;
    }

    const autoCategorise = (doc.user_categories ?? []).length === 0;
    const work = paths
      ? processScreenshots(supabase, userId, doc.id, paths, autoCategorise, claim)
      : enrichStoredText(supabase, userId, doc.id, doc.title, doc.body_plain, pendingImages, autoCategorise, claim, true)
          .catch(async (e) => {
            console.error('Summarising a waiting save failed:', e);
            await markWaiting(supabase, doc.id);
          });
    if (typeof EdgeRuntime !== 'undefined') {
      EdgeRuntime.waitUntil(work);
    }
    started.push(doc.id);
  }

  if (documentId && limitReached) {
    return new Response(
      JSON.stringify({ error: "You've used this month's smart summaries. More next month.", code: 'monthly_limit_reached' }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 402 }
    );
  }
  return new Response(
    JSON.stringify({ started, limitReached }),
    { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 200 }
  );
}

// MARK: Screenshots

// Free accounts: screenshots read on the device. The Share Extension sends
// the text, joined in order (Shared/ScreenshotText.swift); nothing is uploaded
// and Claude isn't called. A Pro account sending text gets the smart summary.
async function saveScreenshotText(
  supabase: any,
  userId: string,
  tier: Tier,
  text: unknown,
  title: unknown,
  categories: string[]
): Promise<Response> {
  if (typeof text !== 'string' || !text.trim()) {
    throw new Error('No text was found in the screenshots');
  }
  const body = text.trim().substring(0, 100_000);
  const heading = typeof title === 'string' && title.trim() ? title.trim().substring(0, 200) : 'Saved screenshots';
  const words = body.split(/\s+/).length;

  const daily = await claimDailySave(supabase, userId, tier);
  if (daily === 'limit') return limitResponse(dailySaveLimitReached());

  const { data: document, error: insertError } = await supabase
    .from('documents')
    .insert({
      user_id: userId,
      source_type: 'screenshot',
      title: heading,
      body_plain: body,
      word_count: words,
      reading_time_minutes: Math.ceil(words / 200),
      user_categories: categories,
      metadata: { textRecognition: 'on-device' },
      processing_status: tier === 'pro' ? 'enriching' : 'completed',
      ai_waiting: tier === 'free',
    })
    .select()
    .single();
  if (insertError) {
    if (daily) await releaseUsage(supabase, daily);
    throw insertError;
  }

  if (tier === 'pro') {
    const work = (async () => {
      const claim = await claimSmartSave(supabase, userId);
      if (!claim) return markWaiting(supabase, document.id);
      await enrichStoredText(supabase, userId, document.id, heading, body, [], categories.length === 0, claim);
    })().catch(async (e) => {
      console.error('Summarising screenshot text failed:', e);
      await markWaiting(supabase, document.id);
    });
    if (typeof EdgeRuntime !== 'undefined') {
      EdgeRuntime.waitUntil(work);
    }
  }

  return new Response(
    JSON.stringify({ id: document.id, status: tier === 'pro' ? 'processing' : 'completed', message: 'Screenshots saved' }),
    { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 200 }
  );
}

// Deletes uploaded screenshots that won't be read (paths checked: the caller's folder only)
async function removeScreenshots(supabase: any, userId: string, input: unknown) {
  const paths = screenshotPaths(input, userId);
  if (!paths) return;
  const { error } = await supabase.storage.from(SCREENSHOT_BUCKET).remove(paths);
  if (error) console.error('Removing unread screenshots failed:', error);
}

// A save made of screenshots (e.g. five screenshots of one article): the
// images are read together, in order, into one article
async function saveScreenshots(supabase: any, userId: string, input: unknown, categories: string[]): Promise<Response> {
  const paths = screenshotPaths(input, userId);
  if (!paths) {
    throw new Error('Invalid screenshots');
  }

  const { data: document, error: insertError } = await supabase
    .from('documents')
    .insert({
      user_id: userId,
      source_type: 'screenshot',
      title: 'Reading screenshots...',
      body_plain: '',
      processing_status: 'fetching',
      user_categories: categories,
      metadata: { screenshotPaths: paths, imageCount: paths.length },
    })
    .select()
    .single();

  if (insertError) {
    throw insertError;
  }

  const processing = processScreenshots(supabase, userId, document.id, paths, categories.length === 0);
  if (typeof EdgeRuntime !== 'undefined') {
    EdgeRuntime.waitUntil(processing);
  }

  return new Response(
    JSON.stringify({ id: document.id, status: 'processing', message: 'Screenshots queued for processing' }),
    { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 200 }
  );
}

async function processScreenshots(
  supabase: any,
  userId: string,
  documentId: string,
  paths: string[],
  autoCategorise: boolean,
  // Set when summarising a waiting save: the credit is already taken and the
  // save stays visible (completed) while it is read
  resumeClaim?: UsageClaim
) {
  let claim: UsageClaim | null = resumeClaim ?? null;
  try {
    if (!claim) {
      claim = await claimSmartSave(supabase, userId);
      if (!claim) {
        // The screenshots stay in storage until a credit is free
        await markWaiting(supabase, documentId, { title: 'Saved screenshots' });
        return;
      }
      await supabase
        .from('documents')
        .update({ processing_status: 'extracting' })
        .eq('id', documentId);
    }

    const images = await downloadScreenshots(supabase, userId, paths);
    if (images.length === 0) {
      throw new Error('The screenshots could not be read');
    }

    const existingTags = await fetchRecentTagNames(supabase, userId);
    const aiEnrichment = await generateAIEnrichment('', '', existingTags, images, 'screenshots');
    if (!aiEnrichment) {
      // Claude didn't answer: keep the save and its credit for another try
      await releaseUsage(supabase, claim);
      claim = null;
      await markWaiting(supabase, documentId, { title: 'Saved screenshots' });
      return;
    }
    claim = null;
    const body = aiEnrichment.transcribedText ?? '';
    if (!body) {
      throw new Error('No text was found in the screenshots');
    }

    const words = body.split(/\s+/).length;
    await supabase
      .from('documents')
      .update({
        title: aiEnrichment.title || 'Saved screenshots',
        author_name: aiEnrichment.authorName || null,
        source_domain: aiEnrichment.sourceName || null,
        body_plain: body,
        word_count: words,
        reading_time_minutes: Math.ceil(words / 200),
        ...(resumeClaim ? {} : { processing_status: 'enriching' }),
      })
      .eq('id', documentId);

    await saveEnrichment(supabase, userId, documentId, aiEnrichment, autoCategorise);
  } catch (error) {
    console.error('Screenshot processing error:', error);
    if (claim) await releaseUsage(supabase, claim);
    await supabase
      .from('documents')
      .update({
        title: 'Saved screenshots',
        processing_status: 'failed',
        processing_error: (error as Error).message,
      })
      .eq('id', documentId);
  }
}

// Paths were checked by screenshotPaths: the caller's folder only. Checked
// again here, since this reads storage with the service role.
async function downloadScreenshots(supabase: any, userId: string, paths: string[]): Promise<ImageInput[]> {
  if (!screenshotPaths(paths, userId)) {
    throw new Error('Invalid screenshots');
  }
  const images: ImageInput[] = [];
  for (const path of paths) {
    const { data, error } = await supabase.storage.from(SCREENSHOT_BUCKET).download(path);
    if (error || !data) {
      console.log(`Screenshot download failed (${path}):`, error);
      continue;
    }
    const bytes = new Uint8Array(await data.arrayBuffer());
    let binary = '';
    for (let i = 0; i < bytes.byteLength; i += 0x8000) {
      binary += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
    }
    images.push({ mediaType: 'image/jpeg', data: btoa(binary) });
  }
  console.log(`Downloaded ${images.length}/${paths.length} screenshots`);
  return images;
}

// Anthropic fetches image URLs itself and honours robots.txt, which Instagram's
// CDN uses to refuse it. Download the slides here instead and pass the bytes.
// Only Instagram/Facebook CDN hosts over https, no redirects, a timeout, and a
// streamed byte cap: the URLs come from a third-party page, so treat them as untrusted.
const IMAGE_HOSTS = [/(^|\.)cdninstagram\.com$/i, /(^|\.)fbcdn\.net$/i];

function isAllowedImageUrl(raw: string): boolean {
  try {
    const parsed = new URL(raw);
    return parsed.protocol === 'https:' && !parsed.port && IMAGE_HOSTS.some((re) => re.test(parsed.hostname));
  } catch {
    return false;
  }
}

async function readCapped(response: Response, maxBytes: number): Promise<Uint8Array | null> {
  const declared = Number(response.headers.get('content-length') ?? '0');
  if (declared > maxBytes) return null;
  if (!response.body) return null;
  const reader = response.body.getReader();
  const chunks: Uint8Array[] = [];
  let size = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    size += value.byteLength;
    if (size > maxBytes) {
      await reader.cancel();
      return null;
    }
    chunks.push(value);
  }
  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return bytes;
}

async function downloadImages(urls: string[], maxBytesEach = 4_000_000, maxTotal = 20_000_000): Promise<ImageInput[]> {
  const images: ImageInput[] = [];
  let total = 0;
  for (const url of urls) {
    if (!isAllowedImageUrl(url)) continue;
    try {
      const response = await fetch(url, {
        headers: { 'Accept': 'image/*' },
        redirect: 'manual',
        signal: AbortSignal.timeout(10_000),
      });
      const mediaType = (response.headers.get('content-type') ?? '').split(';')[0].trim();
      if (response.status !== 200 || !/^image\/(jpeg|png|gif|webp)$/.test(mediaType)) {
        await response.body?.cancel();
        continue;
      }
      const bytes = await readCapped(response, Math.min(maxBytesEach, maxTotal - total));
      if (!bytes || bytes.byteLength === 0) continue;
      total += bytes.byteLength;
      let binary = '';
      for (let i = 0; i < bytes.byteLength; i += 0x8000) {
        binary += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
      }
      images.push({ mediaType, data: btoa(binary) });
      if (total >= maxTotal) break;
    } catch (e) {
      console.log('Image download failed:', e);
    }
  }
  if (urls.length) console.log(`Downloaded ${images.length}/${urls.length} images (${total} bytes)`);
  return images;
}

// Platform detection
// Match on the parsed hostname (and path where it matters), never a substring of
// the whole URL: a crafted link like https://evil.example/instagram.com/p/x/ must
// not reach a platform extractor.
function detectPlatform(url: string): string {
  let host = '';
  let path = '';
  try {
    const parsed = new URL(url);
    host = parsed.hostname.toLowerCase().replace(/^(www\.|m\.|mobile\.)/, '');
    path = parsed.pathname;
  } catch {
    return 'article';
  }
  const is = (domain: string) => host === domain || host.endsWith(`.${domain}`);

  if (is('twitter.com') || is('x.com')) return 'twitter';
  if (is('linkedin.com') && /^\/(posts|pulse|feed|in)\//.test(path)) return 'linkedin';
  if (is('youtube.com') || host === 'youtu.be') return 'youtube';
  if (is('instagram.com') && /^\/([^/]+\/)?(p|reel|tv)\//.test(path)) return 'instagram';
  if (is('threads.net') || is('threads.com')) return 'threads';
  if (is('reddit.com')) return 'reddit';
  if (host === 'news.ycombinator.com') return 'hackernews';
  if (is('substack.com')) return 'substack';
  if (is('medium.com')) return 'medium';
  return 'article';
}

// Drop tracking parameters so x.com/...?s=12 and ...?s=46 are the same save
function canonicalUrl(url: string): string {
  try {
    const parsed = new URL(url);
    for (const key of [...parsed.searchParams.keys()]) {
      if (/^(s|t|si|igsh|igshid|psln|cplk|xtok|obrf|utm_[a-z]+|fbclid|ref_src)$/i.test(key)) parsed.searchParams.delete(key);
    }
    parsed.hash = '';
    return parsed.toString().replace(/\?$/, '');
  } catch {
    return url;
  }
}

function extractDomain(url: string): string {
  try {
    return new URL(url).hostname.replace('www.', '');
  } catch {
    return url;
  }
}

// fxtwitter mirrors X's public post data. It expands t.co links and carries
// the body of X Articles under tweet.article.content.blocks, which neither
// the syndication endpoint (preview only) nor a page fetch (login wall) does.
async function extractTweetViaFxTwitter(tweetId: string): Promise<ExtractedContent | null> {
  try {
    const response = await fetch(`https://api.fxtwitter.com/i/status/${tweetId}`, {
      headers: { 'User-Agent': 'CommonplaceBot/1.0' },
    });
    if (!response.ok) return null;
    const data = await response.json();
    const tweet = data?.tweet;
    if (!tweet) return null;

    const author = tweet.author ?? {};
    const base = {
      authorName: author.name as string | undefined,
      authorHandle: author.screen_name ? `@${author.screen_name}` : undefined,
      publishedAt: tweet.created_at as string | undefined,
      engagement: {
        likes: tweet.likes as number | undefined,
        shares: tweet.retweets as number | undefined,
        comments: tweet.replies as number | undefined,
        views: tweet.views as number | undefined,
      },
    };

    const blocks = tweet.article?.content?.blocks as Array<{ text?: string }> | undefined;
    if (blocks && blocks.length > 0) {
      const paragraphs = blocks
        .map((block) => (block.text ?? '').trim())
        .filter((text) => text.length > 0);
      const title = ((tweet.article?.title as string | undefined) ?? '').trim();
      return {
        ...base,
        title: title || paragraphs[0]?.substring(0, 100) || 'X Article',
        bodyPlain: paragraphs.join('\n\n'),
      };
    }

    let text = ((tweet.text as string | undefined) ?? '').trim();
    const quote = tweet.quote;
    if (quote?.text) {
      const quotedBy = quote.author?.screen_name ? `@${quote.author.screen_name}` : 'the quoted post';
      text = `${text}\n\nQuoting ${quotedBy}:\n${String(quote.text).trim()}`.trim();
    }
    if (!text) return null;
    const firstLine = text.split('\n')[0];
    return {
      ...base,
      title: firstLine.substring(0, 100) + (firstLine.length > 100 ? '...' : ''),
      bodyPlain: text,
    };
  } catch (e) {
    console.log('fxtwitter failed:', e);
    return null;
  }
}

function extractYouTubeVideoId(url: string): string | null {
  try {
    const parsed = new URL(url);
    if (parsed.hostname === 'youtu.be') return parsed.pathname.slice(1).split('/')[0] || null;
    const v = parsed.searchParams.get('v');
    if (v) return v;
    const shorts = parsed.pathname.match(/\/(?:shorts|embed|live)\/([A-Za-z0-9_-]{6,})/);
    return shorts ? shorts[1] : null;
  } catch {
    return null;
  }
}

// YouTube: the watch page is a shell for a reader, so Jina returns navigation
// chrome. Read the public oEmbed endpoint (title, channel, thumbnail) and the
// player JSON embedded in the page (description, keywords, length, views,
// publish date, chapters). The description is what gets summarized.
async function extractYouTube(url: string): Promise<ExtractedContent | null> {
  const videoId = extractYouTubeVideoId(url);
  if (!videoId) return null;
  const canonical = `https://www.youtube.com/watch?v=${videoId}`;

  let title = '';
  let channelName: string | undefined;
  let thumbnailUrl: string | undefined;
  try {
    const oembed = await fetch(`https://www.youtube.com/oembed?url=${encodeURIComponent(canonical)}&format=json`);
    if (oembed.ok) {
      const data = await oembed.json();
      title = (data.title as string | undefined) ?? '';
      channelName = data.author_name as string | undefined;
      thumbnailUrl = data.thumbnail_url as string | undefined;
    }
  } catch (e) {
    console.log('YouTube oEmbed failed:', e);
  }

  let description = '';
  let keywords: string[] = [];
  const metadata: Record<string, unknown> = {};
  try {
    const page = await fetch(canonical, {
      headers: {
        'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124 Safari/537.36',
        'Accept-Language': 'en',
      },
    });
    const html = await page.text();
    const match = html.match(/ytInitialPlayerResponse\s*=\s*(\{.*?\})\s*;\s*(?:var |<\/script>)/s);
    if (match) {
      const player = JSON.parse(match[1]);
      const details = player.videoDetails ?? {};
      title = title || (details.title as string | undefined) || '';
      channelName = channelName ?? (details.author as string | undefined);
      description = ((details.shortDescription as string | undefined) ?? '').trim();
      keywords = (details.keywords as string[] | undefined) ?? [];
      if (details.lengthSeconds) metadata.durationSec = Number(details.lengthSeconds);
      if (details.viewCount) metadata.viewCount = Number(details.viewCount);
      const publishDate = player.microformat?.playerMicroformatRenderer?.publishDate as string | undefined;
      if (publishDate) metadata.uploadDate = publishDate;
    }
    const chapters: { startSec: number; title: string }[] = [];
    const chapterPattern = /"macroMarkersListItemRenderer":\{"title":\{"simpleText":"([^"]+)"\},"timeDescription":\{"simpleText":"([^"]+)"\}/g;
    for (const m of html.matchAll(chapterPattern)) {
      const parts = m[2].split(':').map(Number);
      const startSec = parts.reduce((acc, part) => acc * 60 + part, 0);
      if (!chapters.some((c) => c.startSec === startSec)) chapters.push({ startSec, title: m[1] });
    }
    if (chapters.length) metadata.chapters = chapters;
  } catch (e) {
    console.log('YouTube page fetch failed:', e);
  }

  if (!title) return null;
  if (channelName) metadata.channelName = channelName;
  if (thumbnailUrl) metadata.thumbnailUrl = thumbnailUrl;

  const bodyParts = [description];
  if (keywords.length) bodyParts.push(`Keywords: ${keywords.join(', ')}`);
  const bodyPlain = bodyParts.filter((part) => part.length > 0).join('\n\n') || title;

  return {
    title,
    bodyPlain,
    authorName: channelName,
    publishedAt: metadata.uploadDate as string | undefined,
    engagement: metadata.viewCount ? { views: metadata.viewCount as number } : undefined,
    metadata,
  };
}

// Instagram. Primary source: the post's public embed page (the one sites use to
// embed a post), which carries the caption, the account and every carousel
// slide's image URL. Jina is a fallback; Instagram started refusing it (403) on
// 28 Oct 2026. Slides are read later by Claude (ExtractedContent.images).
function instagramShortcode(url: string): string | null {
  try {
    const match = new URL(url).pathname.match(/^\/(?:[^/]+\/)?(?:p|reel|tv)\/([A-Za-z0-9_-]{5,})/);
    return match ? match[1] : null;
  } catch {
    return null;
  }
}

function decodeHtmlEntities(text: string): string {
  return text
    .replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"').replace(/&#0?39;/g, "'")
    .replace(/&#(\d+);/g, (_, n) => String.fromCodePoint(Number(n)));
}

async function extractInstagramEmbed(shortcode: string): Promise<ExtractedContent | null> {
  try {
    const response = await fetch(`https://www.instagram.com/p/${shortcode}/embed/captioned/`, {
      redirect: 'manual',
      signal: AbortSignal.timeout(15_000),
    });
    if (response.status !== 200) return null;
    const html = await response.text();

    const block = html.match(/class="Caption"[^>]*>([\s\S]*?)<div class="CaptionComments"/)
      ?? html.match(/class="Caption"[^>]*>([\s\S]*?)<\/div>/);
    let caption = '';
    let username: string | undefined;
    if (block) {
      username = block[1].match(/class="CaptionUsername"[^>]*>([^<]+)</)?.[1]?.trim();
      caption = decodeHtmlEntities(
        block[1]
          .replace(/<br\s*\/?>/g, '\n')
          .replace(/<a class="CaptionUsername"[\s\S]*?<\/a>/, '')
          .replace(/<[^>]+>/g, '')
      ).replace(/[ \t]+/g, ' ').trim();
    }
    username = username ?? html.match(/class="UsernameText"[^>]*>([^<]+)</)?.[1]?.trim();

    // The post JSON sits in a script as an escaped string; undo that escaping once
    const unescaped = html
      .replace(/\\\\\//g, '/').replace(/\\\//g, '/')
      .replace(/\\u0025/g, '%').replace(/\\u0026/g, '&').replace(/\\"/g, '"');
    const sidecar = unescaped.indexOf('"edge_sidecar_to_children"');
    const region = sidecar >= 0 ? unescaped.slice(sidecar) : unescaped;
    const images: string[] = [];
    for (const match of region.matchAll(/"display_url":"(https:[^"]+)"/g)) {
      if (!images.includes(match[1])) images.push(match[1]);
      if (images.length >= 10) break;
    }

    if (!caption && images.length === 0) return null;
    const firstLine = caption.split('\n')[0] || `Instagram post${username ? ` by @${username}` : ''}`;
    return {
      title: firstLine.substring(0, 120),
      bodyPlain: caption,
      authorName: username,
      authorHandle: username ? `@${username}` : undefined,
      images,
      metadata: images.length ? { imageCount: images.length } : {},
    };
  } catch (e) {
    console.log('Instagram embed failed:', e);
    return null;
  }
}

async function extractInstagramViaJina(url: string): Promise<ExtractedContent | null> {
  try {
    const response = await fetch(`https://r.jina.ai/${url}`, {
      headers: { 'Accept': 'application/json', 'X-Return-Format': 'markdown' },
      signal: AbortSignal.timeout(20_000),
    });
    if (!response.ok) return null;
    const envelope = await response.json();
    const page = envelope?.data && typeof envelope.data === 'object' ? envelope.data : envelope;
    const rawTitle: string = page.title ?? '';
    const markdown: string = page.content ?? '';

    // "Name on Instagram: "caption text"". Anything else is the login wall, not the post.
    const titleMatch = rawTitle.match(/^(.*?) on Instagram: ["\u201c](.*)["\u201d]\s*$/s);
    if (!titleMatch) return null;
    const authorName = titleMatch[1].trim();
    const caption = titleMatch[2].trim();

    const images: string[] = [];
    const seenFiles = new Set<string>();
    for (const match of markdown.matchAll(/!\[[^\]]*\]\((https:\/\/[^)\s]*cdninstagram\.com[^)\s]*)\)/g)) {
      const src = match[1];
      if (/profile picture|s150x150|s320x320/.test(match[0])) continue;
      let file = src;
      try { file = new URL(src).pathname.split('/').pop() ?? src; } catch { /* keep src */ }
      if (seenFiles.has(file)) continue;
      seenFiles.add(file);
      images.push(src);
      if (images.length >= 10) break;
    }

    const firstLine = caption.split('\n')[0] || `Instagram post by ${authorName}`;
    return {
      title: firstLine.substring(0, 120),
      bodyPlain: caption,
      authorName,
      images,
      metadata: images.length ? { imageCount: images.length } : {},
    };
  } catch (e) {
    console.log('Instagram via Jina failed:', e);
    return null;
  }
}

async function extractInstagram(url: string): Promise<ExtractedContent | null> {
  const shortcode = instagramShortcode(url);
  if (shortcode) {
    const embedded = await extractInstagramEmbed(shortcode);
    if (embedded) return embedded;
  }
  return await extractInstagramViaJina(url);
}

// Content extraction - Uses Jina Reader API for high-quality extraction
async function extractContent(url: string, platform: string): Promise<ExtractedContent> {
  // For X / Twitter: fxtwitter first (expanded links, long posts, and X
  // Articles, whose tweet text is only a t.co link), then the syndication
  // endpoint as a fallback.
  if (platform === 'twitter') {
    const tweetId = extractTweetId(url);
    if (tweetId) {
      const viaFx = await extractTweetViaFxTwitter(tweetId);
      if (viaFx) return viaFx;
      try {
        const response = await fetch(
          `https://cdn.syndication.twimg.com/tweet-result?id=${tweetId}&token=0`
        );
        if (response.ok) {
          const data = await response.json();
          return {
            title: data.text.substring(0, 100) + (data.text.length > 100 ? '...' : ''),
            bodyPlain: data.text,
            authorName: data.user?.name,
            authorHandle: `@${data.user?.screen_name}`,
            publishedAt: data.created_at,
            engagement: {
              likes: data.favorite_count,
              shares: data.retweet_count,
              comments: data.reply_count,
              views: data.views_count,
            },
          };
        }
      } catch (e) {
        console.log('Twitter syndication failed:', e);
      }
    }
  }

  if (platform === 'youtube') {
    const video = await extractYouTube(url);
    if (video) return video;
  }

  if (platform === 'instagram') {
    const post = await extractInstagram(url);
    if (post) return post;
    // The generic path would only reach Instagram's login wall and summarise that
    throw new Error("Couldn't read this Instagram post. It may be private or deleted.");
  }

  // Try Jina Reader API first (free tier: 1M tokens/month)
  try {
    console.log('Trying Jina Reader API...');
    const jinaResponse = await fetch(`https://r.jina.ai/${url}`, {
      headers: {
        'Accept': 'application/json',
        'X-Return-Format': 'markdown',
      },
    });

    if (jinaResponse.ok) {
      const envelope = await jinaResponse.json();
      // With Accept: application/json, Jina wraps the page in { code, status, data: {...} }.
      // Reading the fields off the envelope produced "Untitled" with an empty body.
      const page = envelope?.data && typeof envelope.data === 'object' ? envelope.data : envelope;
      const raw: string = page.content || page.text || '';
      // Scribd's only text is in its page images' alt text; keep it before images are stripped
      const markdown = isScribd(url) ? scribdPagesToText(raw) : raw;
      // Jina returns Markdown; body_plain is shown and printed as plain text
      const article = cleanArticleMarkdown(markdown, page.title);
      if (article.text.trim().length > 0) {
        console.log('Jina extraction successful');
        return {
          title: page.title || 'Untitled',
          subtitle: page.description,
          bodyPlain: article.text,
          // Jina puts the page's <meta name="author"> under metadata; the byline
          // names every co-author, so it wins when the page has one
          authorName: article.byline ?? page.metadata?.author ?? page.author,
          publishedAt: page.publishedTime,
          metadata: article.headings.length ? { headings: article.headings } : undefined,
        };
      }
      console.log('Jina returned no body text, falling back to HTML parsing');
    }
  } catch (e) {
    console.log('Jina extraction failed, falling back to HTML parsing:', e);
  }

  // Fallback: Generic article extraction using fetch + parsing
  try {
    const response = await fetch(url, {
      headers: {
        'User-Agent': 'Mozilla/5.0 (compatible; CommonplaceBot/1.0)',
      },
    });
    const html = await response.text();
    // A bot wall (Cloudflare on Medium) is not the article; never summarise it
    if (!response.ok || /<title>(Attention Required!|Just a moment)/i.test(html)) {
      throw new BlockedPageError(`This site didn't let us read the page (HTTP ${response.status}). Try again later.`);
    }

    // Extract basic metadata from HTML
    const title = extractFromHTML(html, /<title>([^<]+)<\/title>/i) ||
                  extractFromHTML(html, /og:title" content="([^"]+)"/i) ||
                  'Untitled';

    const description = extractFromHTML(html, /og:description" content="([^"]+)"/i) ||
                        extractFromHTML(html, /name="description" content="([^"]+)"/i);

    // Extract body text (simplified)
    const bodyText = html
      .replace(/<script[^>]*>[\s\S]*?<\/script>/gi, '')
      .replace(/<style[^>]*>[\s\S]*?<\/style>/gi, '')
      .replace(/<[^>]+>/g, ' ')
      .replace(/\s+/g, ' ')
      .trim()
      .substring(0, 50000); // Limit to 50k chars

    const authorName = extractFromHTML(html, /author" content="([^"]+)"/i) ||
                       extractFromHTML(html, /name="author" content="([^"]+)"/i);

    return {
      title: title.substring(0, 200),
      subtitle: description?.substring(0, 300),
      bodyPlain: bodyText || description || 'Content could not be extracted',
      authorName: authorName ?? undefined,
    };
  } catch (e) {
    if (e instanceof BlockedPageError) throw e;
    console.error('Extraction failed:', e);
    return {
      title: 'Could not extract content',
      bodyPlain: `Failed to extract content from ${url}`,
    };
  }
}

class BlockedPageError extends Error {}

function isScribd(url: string): boolean {
  try {
    const host = new URL(url).hostname.toLowerCase();
    return host === 'scribd.com' || host.endsWith('.scribd.com');
  } catch {
    return false;
  }
}

function extractTweetId(url: string): string | null {
  const match = url.match(/status\/(\d+)/);
  return match ? match[1] : null;
}

function extractFromHTML(html: string, pattern: RegExp): string | null {
  const match = html.match(pattern);
  return match ? match[1].trim() : null;
}

// AI Enrichment
interface Enrichment {
  hook: string;              // <= HOOK_MAX_CHARS, single sentence
  summaryShort: string;      // 2-3 sentences
  executiveSummary: string;  // markdown bullet list
  keyTakeaways: string[];    // exactly KEY_TAKEAWAY_COUNT
  quotableLines: string[];   // verbatim from the content, for share cards; may be empty
  tags: string[];            // 3-6, deduplicated downstream by slug
  categories: string[];
  complexityScore: number;   // 1-10
  readingLevel: 'casual' | 'intermediate' | 'advanced' | 'expert';
  transcribedText?: string;  // text read from supplied images, empty when none
  // Screenshot saves only: what the screenshots show of the piece itself
  title?: string;
  authorName?: string;
  sourceName?: string;
}

const CATEGORIES = ['Technology', 'Business', 'Health', 'Science', 'Culture', 'Politics', 'Design', 'Personal Dev'];

// Structured-output schema: types/enums/required only; lengths and counts are enforced below
const ENRICHMENT_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['hook', 'summaryShort', 'executiveSummary', 'keyTakeaways', 'quotableLines', 'tags', 'categories', 'complexityScore', 'readingLevel', 'transcribedText'],
  properties: {
    transcribedText: { type: 'string' },
    hook: { type: 'string' },
    summaryShort: { type: 'string' },
    executiveSummary: { type: 'string' },
    keyTakeaways: { type: 'array', items: { type: 'string' } },
    quotableLines: { type: 'array', items: { type: 'string' } },
    tags: { type: 'array', items: { type: 'string' } },
    categories: { type: 'array', items: { type: 'string', enum: CATEGORIES } },
    complexityScore: { type: 'integer' },
    readingLevel: { type: 'string', enum: ['casual', 'intermediate', 'advanced', 'expert'] },
  },
};

// Screenshots carry no page metadata, so Claude also reads the headline, author and source
const SCREENSHOT_SCHEMA = {
  ...ENRICHMENT_SCHEMA,
  required: [...ENRICHMENT_SCHEMA.required, 'title', 'authorName', 'sourceName'],
  properties: {
    ...ENRICHMENT_SCHEMA.properties,
    title: { type: 'string' },
    authorName: { type: 'string' },
    sourceName: { type: 'string' },
  },
};

function fallbackEnrichment(content: string): Enrichment {
  return {
    hook: fitHook(content),
    summaryShort: content.substring(0, 200) + '...',
    executiveSummary: content.substring(0, 500),
    keyTakeaways: [],
    quotableLines: [],
    tags: [],
    categories: [],
    complexityScore: 5,
    readingLevel: 'intermediate',
    transcribedText: '',
  };
}

const STATUS_TAGS = /^(missing content|needs review|shortened url|twitter link|no content|untitled)$/i;

// Images are either a post's slides (Instagram) next to its caption, or
// screenshots that are the whole content
type ImageKind = 'slides' | 'screenshots';

function imageInstructions(images: ImageInput[], kind: ImageKind): string {
  if (!images.length) return 'transcribedText: return an empty string.';
  if (kind === 'slides') {
    return `The ${images.length} image(s) above are the post's slides; their text IS the content. Transcribe them faithfully, in order, into transcribedText (plain text, slide breaks as blank lines) and base everything below on caption plus slides.`;
  }
  return `The ${images.length} image(s) above are screenshots of ONE piece (an article, thread or post), in the order they were taken; their text IS the content.
- transcribedText: the piece's main text, transcribed faithfully and in order as plain text, paragraphs separated by blank lines. Keep the author's wording, spelling and capitalisation. Leave out phone and app chrome: status bar, menus, buttons, like/view/reply counts, ads, and comments under the piece. Screenshots usually overlap: text that appears at the bottom of one and the top of the next is written once.
- title: the piece's headline as shown; if it has none, a short descriptive title (under 80 characters).
- authorName: the author's name as shown; an empty string if none is visible.
- sourceName: the publication, site or app as shown (e.g. "Substack", "The Atlantic", "LinkedIn"); an empty string if none is visible.
Base everything below on the transcribed text.`;
}

// The smart summary (Pro). Null when Claude can't be reached or fails, so the
// caller can give the credit back
async function generateAIEnrichment(
  title: string,
  content: string,
  existingTags: string[],
  images: ImageInput[] = [],
  kind: ImageKind = 'slides'
): Promise<Enrichment | null> {
  const anthropicApiKey = Deno.env.get('ANTHROPIC_API_KEY');

  if (!anthropicApiKey) {
    console.log('Anthropic API key not configured, skipping AI enrichment');
    return null;
  }

  try {
    const anthropic = new Anthropic({ apiKey: anthropicApiKey });

    const fromScreenshots = kind === 'screenshots' && images.length > 0;
    const result = await generateJSON<Enrichment>(anthropic, {
      model: CLAUDE_MODELS.saves,
      effort: 'low',
      schema: fromScreenshots ? SCREENSHOT_SCHEMA : ENRICHMENT_SCHEMA,
      images,
      // A long article's transcription comes on top of the summary fields
      maxTokens: fromScreenshots ? 20000 : undefined,
      prompt: `Analyze this content for a personal knowledge library.
${imageInstructions(images, kind)}
${fromScreenshots ? '' : `
Title: ${title}
Content: ${content.substring(0, 10000)}
`}
Produce:
- hook: ONE sentence, max ${HOOK_MAX_CHARS} characters (about 25 words), the single most striking idea. No preamble.
- summaryShort: 2-3 sentences on the main insight.
- executiveSummary: a markdown bullet list (5-8 bullets) of the arguments, key figures and practical implications.
- keyTakeaways: exactly ${KEY_TAKEAWAY_COUNT} actionable takeaways, each one sentence.
- quotableLines: 2-${QUOTE_MAX_COUNT} of the most striking lines, each copied WORD FOR WORD from the content (they are shared as quotes credited to the author, so never paraphrase, shorten or merge sentences). Each under ${QUOTE_MAX_CHARS} characters. Return an empty list if the content has no such lines.
- tags: 3-6 short topical tags (1-3 words each, Title Case, no # symbol). Specific over generic: "Transformer Models" not "AI". Tags describe the subject only; never add status labels such as "Missing Content" or "Needs Review". If the content is thin, summarize what is there without commenting on what is missing.
${existingTags.length ? `  Reuse these existing tags when they fit, spelled exactly as given: ${existingTags.join(', ')}` : ''}
- categories: 1-2 from: ${CATEGORIES.join(', ')}.
- complexityScore: 1 (casual) to 10 (expert).
- readingLevel: casual, intermediate, advanced or expert.

Write in the language of the content.`,
    });

    return {
      hook: fitHook(result.hook),
      summaryShort: result.summaryShort.trim(),
      executiveSummary: result.executiveSummary.trim(),
      keyTakeaways: result.keyTakeaways.slice(0, KEY_TAKEAWAY_COUNT),
      // Slide text counts as content: Instagram quotes often live in the slides
      quotableLines: verbatimQuotes(result.quotableLines ?? [], `${content}\n${result.transcribedText ?? ''}`),
      tags: result.tags.filter((tag) => !STATUS_TAGS.test(tag.trim())),
      categories: result.categories.filter((c) => CATEGORIES.includes(c)),
      complexityScore: Math.min(10, Math.max(1, Math.round(result.complexityScore))),
      readingLevel: result.readingLevel,
      transcribedText: (result.transcribedText ?? '').trim(),
      title: result.title?.trim().substring(0, 200),
      authorName: result.authorName?.trim().substring(0, 120),
      sourceName: result.sourceName?.trim().substring(0, 120),
    };
  } catch (e) {
    console.error('AI enrichment failed:', e);
    return null;
  }
}
