// Claude model ids for every Edge Function. Change them here, not per function.
// Re-exported by claude.ts.

export const CLAUDE_MODELS = {
  // Enrichment of every Pro save (process-url). Chosen 30 Oct 2026 after a side-by-side
  // run on 15 real saves: close to Opus (word-for-word quotes, screenshot text,
  // summaries) at half the cost per save
  saves: 'claude-sonnet-5-5',
  // Enrichment of free-tier saves: about 0.07¢ per article save against Sonnet's 1.4¢
  freeSaves: 'claude-haiku-5-5',
  // Post generation, voice analysis, multi-document synthesis (Compose, Pro only)
  standard: 'claude-opus-5-5',
} as const;

export type ClaudeModel = typeof CLAUDE_MODELS[keyof typeof CLAUDE_MODELS];
