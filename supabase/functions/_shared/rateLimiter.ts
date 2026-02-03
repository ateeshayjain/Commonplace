// Simple in-memory sliding window rate limiter for Edge Functions
// Note: Each Edge Function invocation is isolated in Deno Deploy,
// so this uses a Supabase table for persistence across invocations.

import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

interface RateLimitConfig {
  maxRequests: number;
  windowSeconds: number;
}

const DEFAULT_CONFIGS: Record<string, RateLimitConfig> = {
  'process-url': { maxRequests: 10, windowSeconds: 60 },
  'generate-posts': { maxRequests: 5, windowSeconds: 60 },
  'synthesize-content': { maxRequests: 5, windowSeconds: 60 },
  'analyze-style': { maxRequests: 3, windowSeconds: 60 },
  'generate-pdf': { maxRequests: 10, windowSeconds: 60 },
  'oauth-connect': { maxRequests: 3, windowSeconds: 60 },
};

export async function checkRateLimit(
  supabase: SupabaseClient,
  userId: string,
  functionName: string,
  corsHeaders: Record<string, string>,
): Promise<Response | null> {
  const config = DEFAULT_CONFIGS[functionName];
  if (!config) return null;

  const windowStart = new Date(Date.now() - config.windowSeconds * 1000).toISOString();

  // Count recent requests using RPC or direct query
  const { count, error } = await supabase
    .from('rate_limits')
    .select('*', { count: 'exact', head: true })
    .eq('user_id', userId)
    .eq('function_name', functionName)
    .gte('created_at', windowStart);

  if (error) {
    // If table doesn't exist, skip rate limiting gracefully
    console.warn('Rate limit check failed:', error.message);
    return null;
  }

  if ((count ?? 0) >= config.maxRequests) {
    return new Response(
      JSON.stringify({ error: 'Rate limit exceeded. Please try again later.' }),
      {
        status: 429,
        headers: {
          ...corsHeaders,
          'Content-Type': 'application/json',
          'Retry-After': String(config.windowSeconds),
        },
      }
    );
  }

  // Record this request
  await supabase
    .from('rate_limits')
    .insert({ user_id: userId, function_name: functionName });

  return null;
}
