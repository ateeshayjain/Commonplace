// Supabase Edge Function: process-url
// Processes a URL, extracts content, generates AI summary, and creates PDF

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { Anthropic, CLAUDE_MODELS, generateJSON } from '../_shared/claude.ts';
import { attachTags, fetchRecentTagNames } from '../_shared/tags.ts';
import { HOOK_MAX_CHARS, KEY_TAKEAWAY_COUNT } from '../_shared/generation.ts';

// Supabase Edge Runtime: keeps background work alive after the response is sent
declare const EdgeRuntime: { waitUntil(promise: Promise<unknown>): void } | undefined;

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

interface ProcessURLRequest {
  url: string;
  categories?: string[];
}

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
    const { url, categories = [] }: ProcessURLRequest = await req.json();

    if (!url) {
      throw new Error('URL is required');
    }

    // Detect platform
    const platform = detectPlatform(url);

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
      throw insertError;
    }

    // Process asynchronously; without waitUntil the runtime may kill this after responding
    const processing = processContent(supabase, user.id, document.id, url, platform);
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
  platform: string
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
        processing_status: 'enriching',
        word_count: content.bodyPlain.split(/\s+/).length,
        reading_time_minutes: Math.ceil(content.bodyPlain.split(/\s+/).length / 200),
      })
      .eq('id', documentId);

    // Generate AI enrichment, reusing the user's existing tags where they fit
    const existingTags = await fetchRecentTagNames(supabase, userId);
    const aiEnrichment = await generateAIEnrichment(content.title, content.bodyPlain, existingTags);

    // Update with AI enrichment (PRD: hook / executiveSummary / keyTakeaways)
    await supabase
      .from('documents')
      .update({
        ai_hook: aiEnrichment.hook,
        ai_summary_short: aiEnrichment.summaryShort,
        ai_summary_long: aiEnrichment.executiveSummary,
        ai_key_points: aiEnrichment.keyTakeaways,
        ai_categories: aiEnrichment.categories,
        ai_topics: aiEnrichment.tags, // kept for the current UI until tags are shown
        ai_complexity_score: aiEnrichment.complexityScore,
        ai_reading_level: aiEnrichment.readingLevel,
        processing_status: 'completed',
        processed_at: new Date().toISOString(),
      })
      .eq('id', documentId);

    await attachTags(supabase, userId, documentId, aiEnrichment.tags);

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

// Platform detection
function detectPlatform(url: string): string {
  const patterns: Record<string, RegExp[]> = {
    twitter: [/twitter\.com/, /x\.com/],
    linkedin: [/linkedin\.com\/(posts|pulse|feed|in)\//],
    youtube: [/youtube\.com/, /youtu\.be/],
    instagram: [/instagram\.com\/(p|reel|tv)\//],
    threads: [/threads\.net/],
    reddit: [/reddit\.com/],
    hackernews: [/news\.ycombinator\.com/],
    substack: [/\.substack\.com/],
    medium: [/medium\.com/],
  };

  for (const [platform, regexes] of Object.entries(patterns)) {
    for (const regex of regexes) {
      if (regex.test(url)) {
        return platform;
      }
    }
  }

  return 'article';
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

    const text = ((tweet.text as string | undefined) ?? '').trim();
    if (!text) return null;
    return {
      ...base,
      title: text.substring(0, 100) + (text.length > 100 ? '...' : ''),
      bodyPlain: text,
    };
  } catch (e) {
    console.log('fxtwitter failed:', e);
    return null;
  }
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
      const data = await jinaResponse.json();
      console.log('Jina extraction successful');
      return {
        title: data.title || 'Untitled',
        subtitle: data.description,
        bodyPlain: data.content || data.text || '',
        authorName: data.author,
        publishedAt: data.publishedTime,
      };
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
    console.error('Extraction failed:', e);
    return {
      title: 'Could not extract content',
      bodyPlain: `Failed to extract content from ${url}`,
    };
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
  tags: string[];            // 3-6, deduplicated downstream by slug
  categories: string[];
  complexityScore: number;   // 1-10
  readingLevel: 'casual' | 'intermediate' | 'advanced' | 'expert';
}

const CATEGORIES = ['Technology', 'Business', 'Health', 'Science', 'Culture', 'Politics', 'Design', 'Personal Dev'];

// Structured-output schema: types/enums/required only; lengths and counts are enforced below
const ENRICHMENT_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['hook', 'summaryShort', 'executiveSummary', 'keyTakeaways', 'tags', 'categories', 'complexityScore', 'readingLevel'],
  properties: {
    hook: { type: 'string' },
    summaryShort: { type: 'string' },
    executiveSummary: { type: 'string' },
    keyTakeaways: { type: 'array', items: { type: 'string' } },
    tags: { type: 'array', items: { type: 'string' } },
    categories: { type: 'array', items: { type: 'string', enum: CATEGORIES } },
    complexityScore: { type: 'integer' },
    readingLevel: { type: 'string', enum: ['casual', 'intermediate', 'advanced', 'expert'] },
  },
};

function fallbackEnrichment(content: string): Enrichment {
  return {
    hook: content.substring(0, HOOK_MAX_CHARS),
    summaryShort: content.substring(0, 200) + '...',
    executiveSummary: content.substring(0, 500),
    keyTakeaways: [],
    tags: [],
    categories: [],
    complexityScore: 5,
    readingLevel: 'intermediate',
  };
}

async function generateAIEnrichment(title: string, content: string, existingTags: string[]): Promise<Enrichment> {
  const anthropicApiKey = Deno.env.get('ANTHROPIC_API_KEY');

  if (!anthropicApiKey) {
    console.log('Anthropic API key not configured, skipping AI enrichment');
    return fallbackEnrichment(content);
  }

  try {
    const anthropic = new Anthropic({ apiKey: anthropicApiKey });

    const result = await generateJSON<Enrichment>(anthropic, {
      model: CLAUDE_MODELS.standard,
      effort: 'low',
      schema: ENRICHMENT_SCHEMA,
      prompt: `Analyze this content for a personal knowledge library.

Title: ${title}
Content: ${content.substring(0, 10000)}

Produce:
- hook: ONE sentence, max ${HOOK_MAX_CHARS} characters, the single most striking idea. No preamble.
- summaryShort: 2-3 sentences on the main insight.
- executiveSummary: a markdown bullet list (5-8 bullets) of the arguments, key figures and practical implications.
- keyTakeaways: exactly ${KEY_TAKEAWAY_COUNT} actionable takeaways, each one sentence.
- tags: 3-6 short topical tags (1-3 words each, Title Case, no # symbol). Specific over generic: "Transformer Models" not "AI".
${existingTags.length ? `  Reuse these existing tags when they fit, spelled exactly as given: ${existingTags.join(', ')}` : ''}
- categories: 1-2 from: ${CATEGORIES.join(', ')}.
- complexityScore: 1 (casual) to 10 (expert).
- readingLevel: casual, intermediate, advanced or expert.

Write in the language of the content.`,
    });

    return {
      hook: result.hook.trim().substring(0, HOOK_MAX_CHARS),
      summaryShort: result.summaryShort.trim(),
      executiveSummary: result.executiveSummary.trim(),
      keyTakeaways: result.keyTakeaways.slice(0, KEY_TAKEAWAY_COUNT),
      tags: result.tags,
      categories: result.categories.filter((c) => CATEGORIES.includes(c)),
      complexityScore: Math.min(10, Math.max(1, Math.round(result.complexityScore))),
      readingLevel: result.readingLevel,
    };
  } catch (e) {
    console.error('AI enrichment failed:', e);
    return fallbackEnrichment(content);
  }
}
