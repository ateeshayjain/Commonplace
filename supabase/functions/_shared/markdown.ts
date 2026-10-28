// Turns the Markdown that Jina Reader returns for articles (Substack, Medium,
// blogs) into readable plain text. documents.body_plain is shown as plain text
// in the app and printed as-is in PDFs, so link and image syntax, page chrome
// (subscribe buttons, like counts) and the comment section must not reach it.

export type ArticleBlockKind = 'heading' | 'paragraph' | 'list' | 'quote';

export interface ArticleBlock {
  kind: ArticleBlockKind;
  text: string;
}

export interface CleanedArticle {
  /** Paragraphs separated by blank lines; list items one per line, prefixed "• " or "1. ". */
  text: string;
  /** Section headings, in order; stored in documents.metadata.headings so PDFs can bold them. */
  headings: string[];
}

// Page text is untrusted: every open-ended span below has an upper bound so a
// hostile line (e.g. 200k characters of "*a ") is cleaned in linear time, not
// quadratic. Longer links or emphasis are simply left as they are.
const MAX_INPUT_CHARS = 300_000;

// A link or image destination: allows one level of parentheses and an optional "title"
const DEST = String.raw`\((?:[^()\s]|\([^()\s]{0,200}\)){0,2048}(?:\s+"[^"]{0,200}")?\)`;
const IMAGE = new RegExp(String.raw`!\[[^\]]{0,500}\]` + DEST, 'g');
const LINK = new RegExp(String.raw`\[([^\]]{0,500})\]` + DEST, 'g');

// Lines that are page furniture, compared after inline cleanup, case-insensitively
const CHROME_LINES = new Set([
  'subscribe', 'sign in', 'subscribe sign in', 'sign up', 'share', 'like', 'comment',
  'comments', 'restack', 'previous', 'next', 'listen', 'follow', 'see all', 'get app',
  'write', 'upgrade to paid', 'member-only story', 'top latest discussions',
  'press enter or click to view image in full size',
]);

// Everything from one of these lines on is comments, related posts or the site footer
const END_MARKERS = [
  /^discussion about this post$/i,
  /^comments restacks$/i,
  /^ready for more\??$/i,
  /^top latest discussions$/i,
  /^responses \(\d+\)$/i,
  /^recommended from medium$/i,
  /^more from .+ and .+$/i,
];

const MONTH = '(?:jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec)[a-z]*';
const DATE_LINE = new RegExp(`^${MONTH}\\.? \\d{1,2}(?:, \\d{4})?$`, 'i');
const COUNT_LINE = /^[\d.,]+\s*[km]?$/i;
const SEPARATORS = /[∙•·|]/g;

/** True when text carries Markdown syntax worth cleaning (links, images, headings, emphasis). */
export function looksLikeMarkdown(text: string): boolean {
  return /\]\(https?:\/\//.test(text) || /^#{1,6} \S/m.test(text) || /\*\*\S/.test(text);
}

/** Strip inline Markdown from one line: images, links, emphasis, code, escapes. */
export function cleanInline(line: string): string {
  return line
    .replace(IMAGE, '')
    .replace(LINK, '$1')
    .replace(/<(https?:\/\/[^>\s]{1,2048})>/g, '$1')
    .replace(/<\/?(?:br|span|div|sup|sub|em|strong|i|b|u|a)\b[^>]{0,500}>/gi, ' ')
    .replace(/`([^`]{1,500})`/g, '$1')
    .replace(/\*\*(?=\S)(.{1,500}?)(?<=\S)\*\*/g, '$1')
    .replace(/(?<![\w_])__(?=\S)(.{1,500}?)(?<=\S)__(?![\w_])/g, '$1')
    .replace(/(?<![\w*])\*(?=[^\s*])(.{1,500}?)(?<=[^\s*])\*(?![\w*])/g, '$1')
    .replace(/(?<![\w_])_(?=[^\s_])(.{1,500}?)(?<=[^\s_])_(?![\w_])/g, '$1')
    .replace(/~~(.{1,500}?)~~/g, '$1')
    .replace(/\\([\\`*_{}\[\]()#+\-.!>|~])/g, '$1')
    .replace(/\u00a0/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function normalise(text: string): string {
  return text.toLowerCase().replace(/[^\p{L}\p{N}]+/gu, ' ').trim();
}

function isChrome(raw: string, cleaned: string): boolean {
  const bare = cleaned.replace(SEPARATORS, ' ').replace(/\s+/g, ' ').trim();
  if (!bare) return true;
  if (CHROME_LINES.has(bare.toLowerCase())) return true;
  if (COUNT_LINE.test(bare) || DATE_LINE.test(bare)) return true;
  if (/^\d[\d,.]*[km]? (likes?|restacks?|comments?|claps?)$/i.test(bare)) return true;
  if (/^©/.test(bare) || /^already have an account\?/i.test(bare)) return true;
  // A line made only of links (bylines, nav, share buttons) carries no prose
  const withoutLinks = raw.replace(IMAGE, '').replace(LINK, '').replace(SEPARATORS, '').trim();
  return /\]\(/.test(raw) && withoutLinks === '';
}

/** Parse article Markdown into blocks, dropping page chrome. */
export function markdownToBlocks(md: string, title?: string): ArticleBlock[] {
  let lines = md.slice(0, MAX_INPUT_CHARS).replace(/\r\n?/g, '\n').split('\n');

  // Drop the masthead: everything up to the heading that repeats the title
  if (title) {
    const wanted = normalise(title);
    const at = lines.findIndex((l) => /^#{1,6}\s/.test(l) && normalise(cleanInline(l.replace(/^#+\s*/, ''))) === wanted);
    if (at >= 0) lines = lines.slice(at + 1);
  }

  const blocks: ArticleBlock[] = [];
  let paragraph: string[] = [];
  let quote: string[] = [];
  let list: string[] = [];
  let inFence = false;

  const flush = () => {
    if (paragraph.length) blocks.push({ kind: 'paragraph', text: paragraph.join(' ') });
    if (quote.length) blocks.push({ kind: 'quote', text: quote.join(' ') });
    if (list.length) blocks.push({ kind: 'list', text: list.join('\n') });
    paragraph = [];
    quote = [];
    list = [];
  };

  for (const raw of lines) {
    if (/^\s*(```|~~~)/.test(raw)) { flush(); inFence = !inFence; continue; }
    if (inFence) { if (raw.trim()) paragraph.push(raw.trim()); continue; }

    const trimmed = raw.trim();
    if (!trimmed) { flush(); continue; }
    if (/^([-*_])(\s*\1){2,}$/.test(trimmed)) { flush(); continue; } // horizontal rule
    if (/^\|?[\s:-]+\|[\s|:-]*$/.test(trimmed)) continue; // table divider row

    const heading = trimmed.match(/^#{1,6}\s+(.*?)\s*#*$/);
    if (heading) {
      flush();
      const text = cleanInline(heading[1]);
      if (END_MARKERS.some((re) => re.test(text))) break;
      if (!isChrome(heading[1], text)) blocks.push({ kind: 'heading', text });
      continue;
    }

    const quoted = trimmed.match(/^>\s?(.*)$/);
    if (quoted) {
      if (paragraph.length || list.length) { const q = quote; quote = []; flush(); quote = q; }
      const text = cleanInline(quoted[1]);
      if (text) quote.push(text);
      else if (quote.length) { blocks.push({ kind: 'quote', text: quote.join(' ') }); quote = []; }
      continue;
    }

    const cleaned = cleanInline(trimmed.startsWith('|') ? trimmed.replace(/^\||\|$/g, '').replace(/\|/g, ' | ') : trimmed);
    if (END_MARKERS.some((re) => re.test(cleaned))) break;
    if (isChrome(trimmed, cleaned)) continue;

    const item = trimmed.match(/^(?:[-*+]|(\d+)[.)])\s+/);
    if (item) {
      if (paragraph.length || quote.length) flush();
      const text = cleanInline(trimmed.slice(item[0].length));
      if (text) list.push(item[1] ? `${item[1]}. ${text}` : `• ${text}`);
      continue;
    }

    if (list.length || quote.length) flush();
    paragraph.push(cleaned);
  }
  flush();
  return blocks;
}

/** Clean article Markdown into the plain text stored in body_plain, plus its headings. */
export function cleanArticleMarkdown(md: string, title?: string): CleanedArticle {
  const blocks = markdownToBlocks(md, title);
  return {
    text: blocks.map((b) => b.text).join('\n\n'),
    headings: blocks.filter((b) => b.kind === 'heading').map((b) => b.text),
  };
}

/**
 * Blocks for a stored body: Markdown is parsed (saves made before cleanup
 * existed); plain text is split into paragraphs, with known headings marked.
 */
export function bodyToBlocks(body: string, title?: string, headings: string[] = []): ArticleBlock[] {
  if (looksLikeMarkdown(body)) return markdownToBlocks(body, title);
  const known = new Set(headings.map(normalise));
  return body
    .split(/\n{2,}/)
    .map((p) => p.trim())
    .filter(Boolean)
    .map((text) => ({
      kind: known.has(normalise(text)) ? 'heading' : /^(•|\d+\.) /.test(text) ? 'list' : 'paragraph',
      text,
    }));
}
