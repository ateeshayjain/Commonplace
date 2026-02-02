// Supabase Edge Function: generate-pdf
// Generates a clean PDF from document content using pdf-lib

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { PDFDocument, StandardFonts, rgb, PageSizes } from "https://esm.sh/pdf-lib@1.17.1";

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
      JSON.stringify({ error: error.message }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 400,
      }
    );
  }
});

// PDF Generation
async function generateArticlePDF(document: any): Promise<Uint8Array> {
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

  // Helper: Add new page if needed
  function ensureSpace(height: number): void {
    if (yPosition - height < margin) {
      page = pdfDoc.addPage(PageSizes.Letter);
      yPosition = pageHeight - margin;
    }
  }

  // Helper: Wrap text into lines
  function wrapText(text: string, font: any, size: number, maxWidth: number): string[] {
    const words = text.split(' ');
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

    if (currentLine) {
      lines.push(currentLine);
    }

    return lines;
  }

  // Helper: Draw wrapped text
  function drawWrappedText(
    text: string,
    font: any,
    size: number,
    color = rgb(0.1, 0.1, 0.1)
  ): void {
    const lines = wrapText(text, font, size, contentWidth);
    for (const line of lines) {
      ensureSpace(lineHeight);
      page.drawText(line, {
        x: margin,
        y: yPosition,
        font,
        size,
        color,
      });
      yPosition -= lineHeight;
    }
  }

  // === HEADER: Source & Date ===
  const sourceText = `${getSourceIcon(document.source_type)} ${document.source_domain || document.source_type}`;
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
    const boxHeight = (summaryLines.length * lineHeight) + 40;

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
    page.drawText('✨ AI Summary', {
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

    yPosition -= 20;
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
    // Split into paragraphs
    const paragraphs = document.body_plain.split(/\n\n+/);

    for (const paragraph of paragraphs) {
      const cleanPara = paragraph.trim();
      if (!cleanPara) continue;

      drawWrappedText(cleanPara, helvetica, bodySize);
      yPosition -= 10; // Paragraph spacing
    }
  }

  // === FOOTER (on last page) ===
  yPosition = margin - 20;
  const footerText = `Saved with Commonplace • ${document.source_url || ''}`;
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

function getSourceIcon(sourceType: string): string {
  const icons: Record<string, string> = {
    twitter: '𝕏',
    linkedin: 'in',
    youtube: '▶',
    article: '📄',
    substack: '📧',
    medium: 'M',
    reddit: '🔴',
    hackernews: 'Y',
    instagram: '📷',
    threads: '🧵',
    podcast: '🎙',
    pdf: '📑',
  };
  return icons[sourceType] || '📄';
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
