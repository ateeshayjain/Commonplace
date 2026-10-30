// Shared Claude API helper for Edge Functions
// Keeps the SDK version, model choice, and response handling in one place.

import Anthropic from "https://esm.sh/@anthropic-ai/sdk@0.137.0";

export { Anthropic };

// Model ids live in models.ts (no imports, so tier logic and its tests don't load the SDK)
import { CLAUDE_MODELS, type ClaudeModel } from './models.ts';
export { CLAUDE_MODELS, type ClaudeModel };

export type ClaudeEffort = 'low' | 'medium' | 'high' | 'xhigh' | 'max';

// Server-side refusal fallback: if a safety classifier declines, the API re-runs
// the request on a fallback model. Haiku 5.5 has none (a fallback list is a 400),
// so its requests go without the parameter and a refusal is final.
export function supportsServerFallback(model: ClaudeModel): boolean {
  return model !== CLAUDE_MODELS.freeSaves;
}

function fallbackParams(model: ClaudeModel) {
  return supportsServerFallback(model)
    ? { betas: ['server-side-fallback-2026-07-01'], fallbacks: 'default' as const }
    : {};
}

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
    ...fallbackParams(model),
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

// A JSON Schema object for structured outputs. Keep to types, enums, required and
// additionalProperties:false; enforce lengths and counts in code afterwards.
export type JSONSchema = Record<string, unknown>;

// An image for the model: a public URL (fetched by Anthropic, which honours
// robots.txt) or bytes already downloaded (base64, for hosts that block it).
export type ImageInput = string | { mediaType: string; data: string };

interface GenerateJSONOptions extends GenerateTextOptions {
  schema: JSONSchema;
  // Images to show the model before the prompt (e.g. carousel slides)
  images?: ImageInput[];
}

// Same as generateText, but Claude is constrained to return JSON matching `schema`,
// so the result can be parsed directly instead of regex-matched out of prose.
export async function generateJSON<T>(
  anthropic: Anthropic,
  { model, prompt, system, maxTokens = 16000, effort, schema, images = [] }: GenerateJSONOptions
): Promise<T> {
  const content = [
    ...images.map((image) =>
      typeof image === 'string'
        ? { type: 'image' as const, source: { type: 'url' as const, url: image } }
        : { type: 'image' as const, source: { type: 'base64' as const, media_type: image.mediaType, data: image.data } }
    ),
    { type: 'text' as const, text: prompt },
  ];
  const response = await anthropic.beta.messages.create({
    model,
    max_tokens: maxTokens,
    system,
    output_config: {
      effort,
      format: { type: 'json_schema', schema },
    },
    ...fallbackParams(model),
    messages: [{ role: 'user', content }],
  });

  if (response.stop_reason === 'refusal') {
    throw new Error(`Claude declined the request (${response.stop_details?.category ?? 'unknown'})`);
  }
  if (response.stop_reason === 'max_tokens') {
    throw new Error(`Claude response hit max_tokens (${maxTokens}); JSON is incomplete`);
  }

  const textParts: string[] = [];
  for (const block of response.content) {
    if (block.type === 'text') {
      textParts.push(block.text);
    }
  }
  return JSON.parse(textParts.join('')) as T;
}
