// Shared types for SangrahAI generation (PRD Modules 2-4)
// Row shapes mirror supabase/migrations/004_sangrah_data_model.sql; keep them in sync.

// ============================================
// Limits
// ============================================

export const HOOK_MAX_CHARS = 150;
export const KEY_TAKEAWAY_COUNT = 3;
export const CAROUSEL_SLIDE_LIMITS = { min: 5, max: 10 } as const;
export const VIDEO_DURATION_LIMITS = { min: 15, max: 90, default: 60 } as const;
export const DOSSIER_MAX_DOCUMENTS = 25;

/** A Key Idea within HOOK_MAX_CHARS, shortened at a word boundary with an ellipsis
 *  when the model runs long, instead of being cut mid-word */
export function fitHook(text: string): string {
  const hook = text.trim().replace(/\s+/g, ' ');
  if (hook.length <= HOOK_MAX_CHARS) return hook;
  const cut = hook.slice(0, HOOK_MAX_CHARS - 1);
  const lastSpace = cut.lastIndexOf(' ');
  const words = lastSpace > HOOK_MAX_CHARS / 2 ? cut.slice(0, lastSpace) : cut;
  return words.replace(/[\s,;:\u2014\u2013-]+$/, '') + '\u2026';
}

// ============================================
// Enums (match CHECK constraints)
// ============================================

export type ExportFormat =
  | 'pdf_dossier'
  | 'carousel_image_pack'
  | 'quote_graphic'
  | 'short_video_script'
  | 'generated_video';

export type AssetStatus = 'queued' | 'processing' | 'completed' | 'failed';

export type CarouselTheme = 'light' | 'dark';

export type QuoteStylePreset = 'minimal_card' | 'dark_chart' | 'bold_overlay';

export type TagSource = 'ai' | 'user';

// ============================================
// Module 2: summary structure (stored on documents)
// ============================================

// hook -> documents.ai_hook, executiveSummary -> ai_summary_long, keyTakeaways -> ai_key_points
export interface HierarchicalSummary {
  hook: string;              // <= HOOK_MAX_CHARS
  executiveSummary: string;  // markdown bullet list
  keyTakeaways: string[];    // KEY_TAKEAWAY_COUNT items
  tags: string[];            // deduplicated by slug on insert
}

// documents.metadata, keyed by source type
export interface YouTubeMetadata {
  channelName?: string;
  viewCount?: number;
  uploadDate?: string;       // ISO 8601
  thumbnailUrl?: string;
  chapters?: { startSec: number; title: string }[];
}

export interface BookOcrMetadata {
  pageCount: number;
  bookTitle?: string;
  pageNumbers?: number[];
}

// Articles read through Jina (Substack, Medium, blogs); body_plain is plain text
export interface ArticleMetadata {
  headings?: string[];       // section headings in body_plain, in order
}

export type DocumentMetadata = YouTubeMetadata | BookOcrMetadata | ArticleMetadata | Record<string, unknown>;

// ============================================
// API requests (PRD section 6; itemId -> documentId)
// ============================================

export interface PdfDossierRequest {
  documentIds: string[];     // 1..DOSSIER_MAX_DOCUMENTS, in dossier order
  title?: string;
  collectionId?: string;
}

export interface CarouselRequest {
  documentId: string;
  slideCount: number;        // CAROUSEL_SLIDE_LIMITS
  theme: CarouselTheme;
}

export interface QuoteGraphicRequest {
  documentId: string;
  quoteText?: string;        // omitted: Claude picks the strongest quote
  stylePreset: QuoteStylePreset;
}

export interface VideoScriptRequest {
  documentId: string;
  targetDurationSec: number; // VIDEO_DURATION_LIMITS
}

// Stored in generated_assets.params
export type GenerationParams =
  | { format: 'pdf_dossier'; title?: string }
  | { format: 'carousel_image_pack'; slideCount: number; theme: CarouselTheme }
  | { format: 'quote_graphic'; quoteText?: string; stylePreset: QuoteStylePreset }
  | { format: 'short_video_script'; targetDurationSec: number }
  | { format: 'generated_video'; targetDurationSec: number; scriptAssetId: string };

// ============================================
// Generated content (stored in generated_assets.content)
// ============================================

export interface DossierContent {
  title: string;
  pageCount: number;
  tableOfContents: { documentId: string; title: string; page: number }[];
}

export interface CarouselSlide {
  index: number;             // 0-based
  role: 'hook' | 'body' | 'cta';
  headline: string;
  body?: string;
}

export interface CarouselContent {
  title: string;
  slides: CarouselSlide[];
}

export interface QuoteGraphicContent {
  quote: string;
  attribution?: string;
}

export interface VideoScriptSegment {
  startSec: number;
  endSec: number;
  voiceover: string;
  onScreenText?: string;
  visualCue?: string;
}

export interface VideoScriptContent {
  hook: VideoScriptSegment;
  body: VideoScriptSegment[];
  callToAction: VideoScriptSegment;
  totalDurationSec: number;
}

export type GeneratedContent =
  | DossierContent
  | CarouselContent
  | QuoteGraphicContent
  | VideoScriptContent;

// ============================================
// Rows
// ============================================

export interface GeneratedAssetRow {
  id: string;
  user_id: string;
  document_id: string | null;
  source_document_ids: string[];
  collection_id: string | null;
  format: ExportFormat;
  status: AssetStatus;
  params: GenerationParams;
  content: GeneratedContent | null;
  storage_paths: string[];   // generated-assets bucket, {user_id}/... in display order
  error: string | null;
  created_at: string;
  updated_at: string;
  completed_at: string | null;
}

export interface TagRow {
  id: string;
  user_id: string;
  name: string;
  slug: string;
  created_at: string;
}

export interface CollectionRow {
  id: string;
  user_id: string;
  name: string;
  description: string | null;
  is_public: boolean;
  created_at: string;
  updated_at: string;
}
