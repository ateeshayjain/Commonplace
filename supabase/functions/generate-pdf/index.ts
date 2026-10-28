// Supabase Edge Function: generate-pdf
// Generates a clean PDF from document content using pdf-lib

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { PDFDocument, StandardFonts, rgb, PageSizes } from "https://esm.sh/pdf-lib@1.17.1";
import { bodyToBlocks } from '../_shared/markdown.ts';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

interface GeneratePDFRequest {
  documentId: string;
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
    const { documentId }: GeneratePDFRequest = await req.json();

    if (!documentId) {
      throw new Error('Document ID is required');
    }

    // Get document
    const { data: document, error: docError } = await supabase
      .from('documents')
      .select('*')
      .eq('id', documentId)
      .eq('user_id', user.id)
      .single();

    if (docError || !document) {
      throw new Error('Document not found');
    }

    // Generate PDF
    const pdfBytes = await generateArticlePDF(document);

    // Upload to Supabase Storage
    const fileName = `${documentId}.pdf`;
    const { error: uploadError } = await supabase.storage
      .from('pdfs')
      .upload(`${user.id}/${fileName}`, pdfBytes, {
        contentType: 'application/pdf',
        upsert: true,
      });

    if (uploadError) {
      console.error('Upload error:', uploadError);
      throw new Error('Failed to upload PDF');
    }

    // Get public URL
    const { data: urlData } = supabase.storage
      .from('pdfs')
      .getPublicUrl(`${user.id}/${fileName}`);

    // Update document with PDF URL
    await supabase
      .from('documents')
      .update({ pdf_url: urlData.publicUrl })
      .eq('id', documentId);

    return new Response(
      JSON.stringify({
        success: true,
        pdfUrl: urlData.publicUrl,
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

// PDF Generation
async function generateArticlePDF(input: any): Promise<Uint8Array> {
  let document = input;
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

  // The standard fonts only encode Windows-1252 (WinAnsi); pdf-lib throws on
  // anything else (emoji, arrows, Devanagari, a bare newline). Map common
  // look-alikes and drop the rest, testing each character with the real encoder.
  const REPLACEMENTS: Record<string, string> = {
    '\u2192': '->', '\u2190': '<-', '\u2194': '<->', '\u21d2': '=>',
    '\u2212': '-', '\u2010': '-', '\u2011': '-', '\u2012': '-', '\u2015': '-',
    '\u2032': "'", '\u2033': '"', '\u2009': ' ', '\u200a': ' ', '\u202f': ' ',
    '\u2002': ' ', '\u2003': ' ', '\u2007': ' ', '\u2008': ' ', '\t': ' ',
    '\u2264': '<=', '\u2265': '>=', '\u2260': '!=', '\u2713': 'v', '\u2714': 'v',
    '\u25cf': '•', '\u25aa': '•', '\u25b6': '>', '\u2605': '*', '\u2606': '*',
  };
  const encodable = new Map<string, boolean>();
  function safe(text: string | null | undefined): string {
    if (!text) return '';
    let out = '';
    for (const ch of text.normalize('NFC')) {
      if (ch === '\n') { out += '\n'; continue; }
      const mapped = REPLACEMENTS[ch] ?? ch;
      for (const part of mapped) {
        let ok = encodable.get(part);
        if (ok === undefined) {
          try { helvetica.widthOfTextAtSize(part, 10); helveticaBold.widthOfTextAtSize(part, 10); ok = true; } catch { ok = false; }
          encodable.set(part, ok);
        }
        if (ok) out += part;
      }
    }
    return out.replace(/[ ]{2,}/g, ' ');
  }
  document = {
    ...document,
    title: safe(document.title) || 'Untitled',
    author_name: safe(document.author_name),
    author_handle: safe(document.author_handle),
    source_domain: safe(document.source_domain),
    // Footer link without share-tracking parameters (?s=12, ?xtok=..., ?si=...)
    source_url: safe((document.source_url ?? '').split('?')[0]),
    ai_summary_short: safe(document.ai_summary_short),
    ai_key_points: (document.ai_key_points ?? []).map((p: string) => safe(p)).filter((p: string) => p.trim()),
    body_plain: safe(document.body_plain),
  };

  // Helper: Add new page if needed
  function ensureSpace(height: number): void {
    if (yPosition - height < margin) {
      page = pdfDoc.addPage(PageSizes.Letter);
      yPosition = pageHeight - margin;
    }
  }

  // Helper: Wrap text into lines
  function wrapText(text: string, font: any, size: number, maxWidth: number): string[] {
    const lines: string[] = [];
    for (const rawLine of text.split('\n')) {
      const words = rawLine.split(' ').filter((w) => w.length > 0);
      let currentLine = '';
      for (const word of words) {
        const testLine = currentLine ? `${currentLine} ${word}` : word;
        if (font.widthOfTextAtSize(testLine, size) > maxWidth && currentLine) {
          lines.push(currentLine);
          currentLine = word;
        } else {
          currentLine = testLine;
        }
      }
      lines.push(currentLine);
    }
    // keep blank lines inside a paragraph, but not trailing ones
    while (lines.length && lines[lines.length - 1] === '') lines.pop();
    return lines;
  }

  // Helper: Draw wrapped text
  function drawWrappedText(
    text: string,
    font: any,
    size: number,
    color = rgb(0.1, 0.1, 0.1),
    indent = 0
  ): void {
    const lines = wrapText(text, font, size, contentWidth - indent);
    for (const line of lines) {
      ensureSpace(lineHeight);
      page.drawText(line, {
        x: margin + indent,
        y: yPosition,
        font,
        size,
        color,
      });
      yPosition -= lineHeight;
    }
  }

  // === HEADER: Source & Date ===
  const sourceText = `${getSourceLabel(document.source_type)} · ${document.source_domain || document.source_type}`;
  const dateText = formatDate(document.created_at);

  page.drawText(sourceText, {
    x: margin,
    y: yPosition,
    font: helvetica,
    size: captionSize,
    color: rgb(0.5, 0.5, 0.5),
  });

  const dateWidth = helvetica.widthOfTextAtSize(dateText, captionSize);
  page.drawText(dateText, {
    x: pageWidth - margin - dateWidth,
    y: yPosition,
    font: helvetica,
    size: captionSize,
    color: rgb(0.5, 0.5, 0.5),
  });

  yPosition -= 30;

  // === TITLE ===
  const titleLines = wrapText(document.title, helveticaBold, titleSize, contentWidth);
  for (const line of titleLines) {
    ensureSpace(titleSize + 6);
    page.drawText(line, {
      x: margin,
      y: yPosition,
      font: helveticaBold,
      size: titleSize,
      color: rgb(0.1, 0.1, 0.1),
    });
    yPosition -= titleSize + 6;
  }

  yPosition -= 10;

  // === AUTHOR ===
  if (document.author_name) {
    const authorText = document.author_handle
      ? `By ${document.author_name} (${document.author_handle})`
      : `By ${document.author_name}`;

    page.drawText(authorText, {
      x: margin,
      y: yPosition,
      font: helvetica,
      size: 10,
      color: rgb(0.4, 0.4, 0.4),
    });
    yPosition -= 20;
  }

  // === READING TIME ===
  if (document.reading_time_minutes) {
    page.drawText(`${document.reading_time_minutes} min read`, {
      x: margin,
      y: yPosition,
      font: helvetica,
      size: captionSize,
      color: rgb(0.5, 0.5, 0.5),
    });
    yPosition -= 30;
  }

  // === AI SUMMARY BOX ===
  if (document.ai_summary_short) {
    ensureSpace(100);

    // Draw summary box background
    const summaryLines = wrapText(document.ai_summary_short, helvetica, bodySize, contentWidth - 20);
    const boxHeight = (summaryLines.length * lineHeight) + 52;

    page.drawRectangle({
      x: margin,
      y: yPosition - boxHeight + 20,
      width: contentWidth,
      height: boxHeight,
      color: rgb(0.95, 0.95, 0.98),
      borderColor: rgb(0.8, 0.8, 0.9),
      borderWidth: 1,
    });

    yPosition -= 10;

    // Summary header
    page.drawText('AI Summary', {
      x: margin + 10,
      y: yPosition,
      font: helveticaBold,
      size: 10,
      color: rgb(0.4, 0.4, 0.6),
    });

    yPosition -= 20;

    // Summary text
    for (const line of summaryLines) {
      page.drawText(line, {
        x: margin + 10,
        y: yPosition,
        font: helvetica,
        size: bodySize,
        color: rgb(0.2, 0.2, 0.2),
      });
      yPosition -= lineHeight;
    }

    yPosition -= 32;
  }

  // === KEY POINTS ===
  if (document.ai_key_points && document.ai_key_points.length > 0) {
    ensureSpace(30);

    page.drawText('Key Points', {
      x: margin,
      y: yPosition,
      font: helveticaBold,
      size: 12,
      color: rgb(0.2, 0.2, 0.2),
    });

    yPosition -= 20;

    for (const point of document.ai_key_points) {
      const pointLines = wrapText(`• ${point}`, helvetica, bodySize, contentWidth - 15);
      for (let i = 0; i < pointLines.length; i++) {
        ensureSpace(lineHeight);
        page.drawText(pointLines[i], {
          x: margin + (i === 0 ? 0 : 15),
          y: yPosition,
          font: helvetica,
          size: bodySize,
          color: rgb(0.2, 0.2, 0.2),
        });
        yPosition -= lineHeight;
      }
    }

    yPosition -= 15;
  }

  // === DIVIDER ===
  ensureSpace(20);
  page.drawLine({
    start: { x: margin, y: yPosition },
    end: { x: pageWidth - margin, y: yPosition },
    thickness: 0.5,
    color: rgb(0.8, 0.8, 0.8),
  });
  yPosition -= 20;

  // === CONTENT ===
  if (document.body_plain) {
    // Older article saves hold Jina's raw Markdown; newer ones are plain text
    // with their section headings listed in metadata.headings
    const headings = (document.metadata?.headings ?? []).map((h: string) => safe(h));
    const blocks = bodyToBlocks(document.body_plain, document.title, headings);

    for (const block of blocks) {
      const text = block.text.trim();
      if (!text) continue;

      switch (block.kind) {
        case 'heading':
          ensureSpace(lineHeight * 3); // keep a heading with the text under it
          yPosition -= 6;
          drawWrappedText(text, helveticaBold, 13);
          yPosition -= 4;
          break;
        case 'quote':
          drawWrappedText(text, helvetica, bodySize, rgb(0.35, 0.35, 0.35), 16);
          yPosition -= 10;
          break;
        default:
          drawWrappedText(text, helvetica, bodySize);
          yPosition -= 10; // Paragraph spacing
      }
    }
  }

  // === FOOTER (on last page) ===
  yPosition = margin - 20;
  let footerText = `Saved with Sangrah • ${document.source_url || ''}`;
  while (footerText.length > 20 && helvetica.widthOfTextAtSize(footerText, 8) > contentWidth) {
    footerText = footerText.slice(0, -2) + '…';
    footerText = footerText.replace(/……$/, '…');
  }
  const footerWidth = helvetica.widthOfTextAtSize(footerText, 8);

  page.drawText(footerText, {
    x: (pageWidth - footerWidth) / 2,
    y: 30,
    font: helvetica,
    size: 8,
    color: rgb(0.6, 0.6, 0.6),
  });

  return await pdfDoc.save();
}

// Plain-text labels: the standard PDF fonts cannot draw emoji
function getSourceLabel(sourceType: string): string {
  const labels: Record<string, string> = {
    twitter: 'X',
    linkedin: 'LinkedIn',
    youtube: 'YouTube',
    article: 'Article',
    substack: 'Substack',
    medium: 'Medium',
    reddit: 'Reddit',
    hackernews: 'Hacker News',
    instagram: 'Instagram',
    threads: 'Threads',
    podcast: 'Podcast',
    pdf: 'PDF',
  };
  return labels[sourceType] || 'Saved';
}

function formatDate(dateString: string): string {
  try {
    const date = new Date(dateString);
    return date.toLocaleDateString('en-US', {
      year: 'numeric',
      month: 'long',
      day: 'numeric',
    });
  } catch {
    return dateString;
  }
}
