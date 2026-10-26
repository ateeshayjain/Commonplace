// Shared Claude API helper for Edge Functions
// Keeps the SDK version, model choice, and response handling in one place.

import Anthropic from "https://esm.sh/@anthropic-ai/sdk@0.137.0";

export { Anthropic };

export const CLAUDE_MODELS = {
  // Summaries, post generation, voice analysis
  standard: 'claude-opus-5-5',
  // Multi-document synthesis (second/third-order thinking)
  deepReasoning: 'claude-fable-5-1',
} as const;

export type ClaudeModel = typeof CLAUDE_MODELS[keyof typeof CLAUDE_MODELS];
export type ClaudeEffort = 'low' | 'medium' | 'high' | 'xhigh' | 'max';

interface GenerateTextOptions {
  model: ClaudeModel;
  prompt: string;
  system?: string;
  // Thinking is always on for these models and counts toward max_tokens,
  // so leave room for it on top of the visible reply.
  maxTokens?: number;
  effort: ClaudeEffort;
}

export async function generateText(
  anthropic: Anthropic,
  { model, prompt, system, maxTokens = 16000, effort }: GenerateTextOptions
): Promise<string> {
  const response = await anthropic.beta.messages.create({
    model,
    max_tokens: maxTokens,
    system,
    output_config: { effort },
    // If a safety classifier declines, the API re-runs the request on a fallback model
    betas: ['server-side-fallback-2026-07-01'],
    fallbacks: 'default',
    messages: [{ role: 'user', content: prompt }],
  });

  if (response.stop_reason === 'refusal') {
    throw new Error(`Claude declined the request (${response.stop_details?.category ?? 'unknown'})`);
  }
  if (response.stop_reason === 'max_tokens') {
    console.warn(`Claude response hit max_tokens (${maxTokens}); output may be truncated`);
  }

  // Responses can start with thinking blocks, so read text blocks by type
  const textParts: string[] = [];
  for (const block of response.content) {
    if (block.type === 'text') {
      textParts.push(block.text);
    }
  }
  return textParts.join('');
}
