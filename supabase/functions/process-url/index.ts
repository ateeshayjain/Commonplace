// Supabase Edge Function: process-url
// Processes a URL, extracts content, generates AI summary, and creates PDF

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { PDFDocument, StandardFonts, rgb, PageSizes } from "https://esm.sh/pdf-lib@1.17.1";
import { validateURL, validateStringArray, sanitizeForPrompt, handleValidationError } from "../_shared/validation.ts";
import { checkRateLimit } from "../_shared/rateLimiter.ts";

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

    const rateLimitResponse = await checkRateLimit(supabase, user.id, 'process-url', corsHeaders);
    if (rateLimitResponse) return rateLimitResponse;

    // Parse and validate request
    const body: ProcessURLRequest = await req.json();
    const url = validateURL(body.url);
    const categories = body.categories ? validateStringArray(body.categories, 'categories', 10) : [];

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

    // Process content (must await to keep worker alive)
    await processContent(supabase, document.id, url, platform);

    return new Response(
      JSON.stringify({
        id: document.id,
        status: 'completed',
        message: 'Document processed successfully',
      }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 200,
      }
    );

  } catch (error) {
    console.error('Error:', error);
    return handleValidationError(error, corsHeaders);
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

    // Update with AI enrichment - use separate simple updates to isolate failures
    const updateData: Record<string, any> = {
      processing_status: 'rendering',
      processed_at: new Date().toISOString(),
    };

    // Only store AI fields if enrichment succeeded (not null)
    if (aiEnrichment) {
      if (aiEnrichment.summaryShort) updateData.ai_summary_short = aiEnrichment.summaryShort;
      if (aiEnrichment.summaryLong) updateData.ai_summary_long = aiEnrichment.summaryLong;
      if (aiEnrichment.keyPoints?.length) updateData.ai_key_points = aiEnrichment.keyPoints;
      if (aiEnrichment.categories?.length) updateData.ai_categories = aiEnrichment.categories;
      if (aiEnrichment.topics?.length) updateData.ai_topics = aiEnrichment.topics;
      if (aiEnrichment.complexityScore) updateData.ai_complexity_score = aiEnrichment.complexityScore;
      if (aiEnrichment.readingLevel) updateData.ai_reading_level = aiEnrichment.readingLevel;
    } else {
      console.warn('AI enrichment returned null - document will not have AI summaries');
    }

    const { error: aiUpdateError } = await supabase
      .from('documents')
      .update(updateData)
      .eq('id', documentId);

    if (aiUpdateError) console.error('AI update error:', aiUpdateError);

    // Generate PDF
    try {
      const pdfUrl = await generatePDF(supabase, documentId);
      await supabase
        .from('documents')
        .update({ pdf_url: pdfUrl, processing_status: 'completed' })
        .eq('id', documentId);
    } catch (pdfError: any) {
      console.error('PDF generation failed (non-fatal):', pdfError);
      await supabase
        .from('documents')
        .update({ processing_status: 'completed' })
        .eq('id', documentId);
      return { success: true, pdfGenerated: false, pdfError: pdfError?.message || String(pdfError) };
    }

    return { success: true, pdfGenerated: true };

  } catch (error) {
    console.error('Processing error:', error);
    await supabase
      .from('documents')
      .update({
        processing_status: 'failed',
        processing_error: error.message,
      })
      .eq('id', documentId);
    return { error: error.message };
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
    const jinaResponse = await fetch(`https://r.jina.ai/${url}`, {
      headers: {
        'Accept': 'application/json',
        'X-Return-Format': 'markdown',
      },
    });

    if (jinaResponse.ok) {
      const response = await jinaResponse.json();
      const data = response.data || response;
      // Clean up markdown content - remove images and clean formatting
      let content = data.content || data.text || '';
      content = content
        .replace(/!\[.*?\]\(.*?\)/g, '') // Remove markdown images
        .replace(/<img[^>]*>/gi, '') // Remove HTML img tags
        .replace(/\[([^\]]+)\]\([^)]+\)/g, '$1') // Keep link text, remove URL
        .replace(/^[-*_]{3,}$/gm, '') // Remove horizontal rules
        .replace(/\n{3,}/g, '\n\n') // Collapse multiple newlines
        .trim();
      return {
        title: data.title || 'Untitled',
        subtitle: data.description,
        bodyPlain: content,
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
    console.error('ANTHROPIC_API_KEY not found in environment - AI enrichment skipped');
    return null;
  }

  console.log('Starting AI enrichment, API key exists:', !!anthropicApiKey, 'content length:', content.length);

  try {
    const prompt = `Analyze this content and provide:

1. SHORT SUMMARY (2-3 sentences, focus on main insight)
2. LONG SUMMARY (2-3 paragraphs)
3. KEY POINTS (3-5 bullet points)
4. CATEGORIES (choose from: Technology, Business, Health, Science, Culture, Politics, Design, Personal Dev)
5. TOPICS (3-5 specific topics)
6. COMPLEXITY SCORE (1-10, where 1=casual, 10=expert)
7. READING LEVEL (casual, intermediate, advanced, expert)

Title: ${sanitizeForPrompt(title, 500)}
Content: ${sanitizeForPrompt(content.substring(0, 10000))}

Respond ONLY with valid JSON, no other text:
{"summaryShort": "...", "summaryLong": "...", "keyPoints": ["..."], "categories": ["..."], "topics": ["..."], "complexityScore": 5, "readingLevel": "intermediate"}`;

    const claudeResponse = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': anthropicApiKey,
        'anthropic-version': '2023-06-01',
      },
      body: JSON.stringify({
        model: 'claude-sonnet-4-20250514',
        max_tokens: 2000,
        messages: [{ role: 'user', content: prompt }],
      }),
    });

    if (!claudeResponse.ok) {
      const errText = await claudeResponse.text();
      console.error('Claude API error status:', claudeResponse.status);
      console.error('Claude API error body:', errText.substring(0, 500));
      throw new Error(`Claude API error: ${claudeResponse.status} - ${errText.substring(0, 100)}`);
    }

    console.log('Claude API response OK, parsing...');

    const claudeData = await claudeResponse.json();
    const text = claudeData.content?.[0]?.type === 'text' ? claudeData.content[0].text : '';

    if (!text) {
      console.error('Claude returned empty text, response:', JSON.stringify(claudeData).substring(0, 500));
      throw new Error('Empty response from Claude');
    }

    const jsonMatch = text.match(/\{[\s\S]*\}/);

    if (jsonMatch) {
      try {
        const parsed = JSON.parse(jsonMatch[0]);
        console.log('AI enrichment success:', Object.keys(parsed).join(', '));
        return parsed;
      } catch (parseError) {
        console.error('Failed to parse Claude JSON:', jsonMatch[0].substring(0, 200));
        throw parseError;
      }
    } else {
      console.error('No JSON found in Claude response:', text.substring(0, 300));
      throw new Error('No JSON in Claude response');
    }
  } catch (e: any) {
    console.error('AI enrichment failed:', e.message || e);
    // Return null to indicate AI enrichment failed - don't store raw content as "summary"
    return null;
  }
}


// PDF Generation
async function generatePDF(supabase: any, documentId: string): Promise<string> {
  // Fetch the fully enriched document
  const { data: doc, error } = await supabase
    .from('documents')
    .select('*')
    .eq('id', documentId)
    .single();

  if (error || !doc) throw new Error('Document not found for PDF');

  const pdfDoc = await PDFDocument.create();
  const helvetica = await pdfDoc.embedFont(StandardFonts.Helvetica);
  const helveticaBold = await pdfDoc.embedFont(StandardFonts.HelveticaBold);

  const pageWidth = PageSizes.Letter[0];
  const pageHeight = PageSizes.Letter[1];
  const margin = 50;
  const contentWidth = pageWidth - (margin * 2);
  const lineHeight = 16;
  const titleSize = 20;
  const bodySize = 11;
  const captionSize = 9;

  let page = pdfDoc.addPage(PageSizes.Letter);
  let yPosition = pageHeight - margin;

  function ensureSpace(height: number): void {
    if (yPosition - height < margin) {
      page = pdfDoc.addPage(PageSizes.Letter);
      yPosition = pageHeight - margin;
    }
  }

  function wrapText(text: string, font: any, size: number, maxWidth: number): string[] {
    // Strip non-WinAnsi characters (Helvetica only supports WinAnsi encoding)
    const cleanText = text.replace(/[\n\r\t]/g, ' ').replace(/[^\x20-\x7E\xA0-\xFF]/g, '').replace(/\s+/g, ' ').trim();
    const words = cleanText.split(' ');
    const lines: string[] = [];
    let currentLine = '';
    for (const word of words) {
      const testLine = currentLine ? `${currentLine} ${word}` : word;
      const width = font.widthOfTextAtSize(testLine, size);
      if (width > maxWidth && currentLine) {
        lines.push(currentLine);
        currentLine = word;
      } else {
        currentLine = testLine;
      }
    }
    if (currentLine) lines.push(currentLine);
    return lines;
  }

  function drawWrappedText(text: string, font: any, size: number, color = rgb(0.1, 0.1, 0.1)): void {
    const lines = wrapText(text, font, size, contentWidth);
    for (const line of lines) {
      ensureSpace(lineHeight);
      page.drawText(line, { x: margin, y: yPosition, font, size, color });
      yPosition -= lineHeight;
    }
  }

  // Sanitize text for WinAnsi encoding
  function safe(text: string): string {
    return text.replace(/[^\x20-\x7E\xA0-\xFF]/g, '').trim();
  }

  // Header
  const sourceText = safe(`${doc.source_domain || doc.source_type}`);
  page.drawText(sourceText, { x: margin, y: yPosition, font: helvetica, size: captionSize, color: rgb(0.5, 0.5, 0.5) });
  yPosition -= 30;

  // Title
  const titleLines = wrapText(doc.title, helveticaBold, titleSize, contentWidth);
  for (const line of titleLines) {
    ensureSpace(titleSize + 6);
    page.drawText(line, { x: margin, y: yPosition, font: helveticaBold, size: titleSize, color: rgb(0.1, 0.1, 0.1) });
    yPosition -= titleSize + 6;
  }
  yPosition -= 10;

  // Author
  if (doc.author_name) {
    page.drawText(safe(`By ${doc.author_name}`), { x: margin, y: yPosition, font: helvetica, size: 10, color: rgb(0.4, 0.4, 0.4) });
    yPosition -= 20;
  }

  // AI Summary box
  if (doc.ai_summary_short) {
    ensureSpace(80);
    const summaryLines = wrapText(doc.ai_summary_short, helvetica, bodySize, contentWidth - 20);
    const boxHeight = (summaryLines.length * lineHeight) + 40;
    page.drawRectangle({ x: margin, y: yPosition - boxHeight + 20, width: contentWidth, height: boxHeight, color: rgb(0.95, 0.95, 0.98), borderColor: rgb(0.8, 0.8, 0.9), borderWidth: 1 });
    yPosition -= 10;
    page.drawText('AI Summary', { x: margin + 10, y: yPosition, font: helveticaBold, size: 10, color: rgb(0.4, 0.4, 0.6) });
    yPosition -= 20;
    for (const line of summaryLines) {
      page.drawText(line, { x: margin + 10, y: yPosition, font: helvetica, size: bodySize, color: rgb(0.2, 0.2, 0.2) });
      yPosition -= lineHeight;
    }
    yPosition -= 20;
  }

  // Key Points
  if (doc.ai_key_points && doc.ai_key_points.length > 0) {
    ensureSpace(30);
    page.drawText('Key Points', { x: margin, y: yPosition, font: helveticaBold, size: 12, color: rgb(0.2, 0.2, 0.2) });
    yPosition -= 20;
    for (const point of doc.ai_key_points) {
      const pointLines = wrapText(`• ${point}`, helvetica, bodySize, contentWidth - 15);
      for (const pl of pointLines) {
        ensureSpace(lineHeight);
        page.drawText(pl, { x: margin, y: yPosition, font: helvetica, size: bodySize, color: rgb(0.2, 0.2, 0.2) });
        yPosition -= lineHeight;
      }
    }
    yPosition -= 15;
  }

  // Divider
  ensureSpace(20);
  page.drawLine({ start: { x: margin, y: yPosition }, end: { x: pageWidth - margin, y: yPosition }, thickness: 0.5, color: rgb(0.8, 0.8, 0.8) });
  yPosition -= 20;

  // Content
  if (doc.body_plain) {
    const paragraphs = doc.body_plain.split(/\n\n+/);
    for (const paragraph of paragraphs) {
      const cleanPara = paragraph.trim();
      if (!cleanPara) continue;
      drawWrappedText(cleanPara, helvetica, bodySize);
      yPosition -= 10;
    }
  }

  // Footer
  page.drawText(`Saved with Commonplace`, { x: margin, y: 30, font: helvetica, size: 8, color: rgb(0.6, 0.6, 0.6) });

  const pdfBytes = await pdfDoc.save();

  // Upload to storage
  const fileName = `${doc.user_id}/${documentId}.pdf`;
  const { error: uploadError } = await supabase.storage
    .from('pdfs')
    .upload(fileName, pdfBytes, { contentType: 'application/pdf', upsert: true });

  if (uploadError) throw uploadError;

  const { data: urlData } = supabase.storage.from('pdfs').getPublicUrl(fileName);
  return urlData.publicUrl;
}
