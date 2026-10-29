// Quotable lines for share cards (documents.ai_quotable_lines). The cards credit
// the original author, so a line is kept only when it appears word for word in
// the saved text: a paraphrase put in quotation marks would misquote them.

export const QUOTE_MAX_COUNT = 4;
export const QUOTE_MAX_CHARS = 220;
const QUOTE_MIN_CHARS = 20;

// Compare ignoring case, spacing, curly quotes and dash styles, which the model
// (and the page) may render differently from each other
function comparable(text: string): string {
  return text
    .normalize('NFKC')
    .toLowerCase()
    .replace(/[‘’‚‛′]/g, "'")
    .replace(/[“”„‟″]/g, '"')
    .replace(/[‐-―−]/g, '-')
    .replace(/\s+/g, ' ')
    .trim();
}

/** Lines from `candidates` found verbatim in `content`, deduplicated, trimmed of wrapping quote marks. */
export function verbatimQuotes(candidates: string[], content: string): string[] {
  const haystack = comparable(content);
  const kept: string[] = [];
  const seen = new Set<string>();
  for (const raw of candidates) {
    const line = raw.trim().replace(/^["'“‘]+|["'”’]+$/g, '').trim();
    const key = comparable(line);
    if (line.length < QUOTE_MIN_CHARS || line.length > QUOTE_MAX_CHARS) continue;
    if (seen.has(key) || !haystack.includes(key)) continue;
    seen.add(key);
    kept.push(line);
    if (kept.length === QUOTE_MAX_COUNT) break;
  }
  return kept;
}
