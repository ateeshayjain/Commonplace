// Supabase Edge Function: process-url
// Processes a URL, extracts content, generates AI summary, and creates PDF

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import Anthropic from "https://esm.sh/@anthropic-ai/sdk@0.17.1";

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

    // Process asynchronously
    processContent(supabase, document.id, url, platform);

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
      JSON.stringify({ error: error.message }),
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

    // Generate AI enrichment
    const aiEnrichment = await generateAIEnrichment(content.title, content.bodyPlain);

    // Update with AI enrichment
    await supabase
      .from('documents')
      .update({
        ai_summary_short: aiEnrichment.summaryShort,
        ai_summary_long: aiEnrichment.summaryLong,
        ai_key_points: aiEnrichment.keyPoints,
        ai_categories: aiEnrichment.categories,
        ai_topics: aiEnrichment.topics,
        ai_complexity_score: aiEnrichment.complexityScore,
        ai_reading_level: aiEnrichment.readingLevel,
        processing_status: 'completed',
        processed_at: new Date().toISOString(),
      })
      .eq('id', documentId);

  } catch (error) {
    console.error('Processing error:', error);
    await supabase
      .from('documents')
      .update({
        processing_status: 'failed',
        processing_error: error.message,
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

// Content extraction - Uses Jina Reader API for high-quality extraction
async function extractContent(url: string, platform: string): Promise<ExtractedContent> {
  // For Twitter, try syndication endpoint first
  if (platform === 'twitter') {
    const tweetId = extractTweetId(url);
    if (tweetId) {
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
      authorName,
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
async function generateAIEnrichment(title: string, content: string) {
  const anthropicApiKey = Deno.env.get('ANTHROPIC_API_KEY');

  if (!anthropicApiKey) {
    console.log('Anthropic API key not configured, skipping AI enrichment');
    return {
      summaryShort: content.substring(0, 200) + '...',
      summaryLong: content.substring(0, 500),
      keyPoints: [],
      categories: [],
      topics: [],
      complexityScore: 5,
      readingLevel: 'intermediate',
    };
  }

  try {
    const anthropic = new Anthropic({ apiKey: anthropicApiKey });

    const response = await anthropic.messages.create({
      model: 'claude-sonnet-4-20250514',
      max_tokens: 2000,
      messages: [{
        role: 'user',
        content: `Analyze this content and provide:

1. SHORT SUMMARY (2-3 sentences, focus on main insight)
2. LONG SUMMARY (2-3 paragraphs)
3. KEY POINTS (3-5 bullet points)
4. CATEGORIES (choose from: Technology, Business, Health, Science, Culture, Politics, Design, Personal Dev)
5. TOPICS (3-5 specific topics)
6. COMPLEXITY SCORE (1-10, where 1=casual, 10=expert)
7. READING LEVEL (casual, intermediate, advanced, expert)

Title: ${title}
Content: ${content.substring(0, 10000)}

Respond in JSON format:
{
  "summaryShort": "...",
  "summaryLong": "...",
  "keyPoints": ["...", "..."],
  "categories": ["..."],
  "topics": ["..."],
  "complexityScore": 5,
  "readingLevel": "intermediate"
}`,
      }],
    });

    const text = response.content[0].type === 'text' ? response.content[0].text : '';
    const jsonMatch = text.match(/\{[\s\S]*\}/);

    if (jsonMatch) {
      return JSON.parse(jsonMatch[0]);
    }
  } catch (e) {
    console.error('AI enrichment failed:', e);
  }

  // Fallback
  return {
    summaryShort: content.substring(0, 200) + '...',
    summaryLong: content.substring(0, 500),
    keyPoints: [],
    categories: [],
    topics: [],
    complexityScore: 5,
    readingLevel: 'intermediate',
  };
}
