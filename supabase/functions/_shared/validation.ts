// Shared validation utilities for Edge Functions

const UUID_REGEX = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const MAX_URL_LENGTH = 2048;
const ALLOWED_URL_PROTOCOLS = ['http:', 'https:'];

export function validateURL(url: unknown): string {
  if (typeof url !== 'string' || url.trim().length === 0) {
    throw new ValidationError('URL is required');
  }
  if (url.length > MAX_URL_LENGTH) {
    throw new ValidationError(`URL exceeds maximum length of ${MAX_URL_LENGTH}`);
  }
  let parsed: URL;
  try {
    parsed = new URL(url);
  } catch {
    throw new ValidationError('Invalid URL format');
  }
  if (!ALLOWED_URL_PROTOCOLS.includes(parsed.protocol)) {
    throw new ValidationError('URL must use http or https protocol');
  }
  return url.trim();
}

export function validateUUID(value: unknown, fieldName = 'id'): string {
  if (typeof value !== 'string' || !UUID_REGEX.test(value)) {
    throw new ValidationError(`Invalid ${fieldName}: must be a valid UUID`);
  }
  return value;
}

export function validateStringArray(value: unknown, fieldName: string, maxLength = 20): string[] {
  if (!Array.isArray(value)) {
    throw new ValidationError(`${fieldName} must be an array`);
  }
  if (value.length > maxLength) {
    throw new ValidationError(`${fieldName} exceeds maximum of ${maxLength} items`);
  }
  return value.map((item, i) => {
    if (typeof item !== 'string') {
      throw new ValidationError(`${fieldName}[${i}] must be a string`);
    }
    return item.trim();
  });
}

export function validateEnum<T extends string>(value: unknown, allowed: readonly T[], fieldName: string): T {
  if (typeof value !== 'string' || !allowed.includes(value as T)) {
    throw new ValidationError(`${fieldName} must be one of: ${allowed.join(', ')}`);
  }
  return value as T;
}

export function sanitizeForPrompt(text: string, maxLength = 50000): string {
  // Remove markdown images: ![alt](url)
  text = text.replace(/!\[.*?\]\(.*?\)/g, '');
  // Remove HTML img tags
  text = text.replace(/<img[^>]*>/gi, '');
  // Remove markdown links but keep text: [text](url) -> text
  text = text.replace(/\[([^\]]+)\]\([^)]+\)/g, '$1');
  // Remove raw URLs that start a line
  text = text.replace(/^https?:\/\/\S+$/gm, '');
  // Remove horizontal rules
  text = text.replace(/^[-*_]{3,}$/gm, '');
  // Collapse multiple newlines
  text = text.replace(/\n{3,}/g, '\n\n');
  // Collapse multiple spaces
  text = text.replace(/[ \t]{2,}/g, ' ');
  // Strip common prompt injection patterns
  text = text.replace(/\b(ignore|disregard|forget)\s+(all\s+)?(previous|above|prior)\s+(instructions?|prompts?|context)\b/gi, '[filtered]');
  text = text.replace(/\b(system|assistant|human)\s*:/gi, '[filtered]:');
  // Truncate if needed
  if (text.length > maxLength) {
    text = text.slice(0, maxLength);
  }
  return text.trim();
}

export class ValidationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'ValidationError';
  }
}

export function handleValidationError(error: unknown, corsHeaders: Record<string, string>): Response {
  if (error instanceof ValidationError) {
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
  // Don't expose internal error details
  const message = error instanceof Error ? error.message : 'Internal server error';
  const isAuthError = message === 'Unauthorized' || message === 'Missing authorization header';
  return new Response(
    JSON.stringify({ error: isAuthError ? message : 'Internal server error' }),
    { status: isAuthError ? 401 : 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
  );
}
