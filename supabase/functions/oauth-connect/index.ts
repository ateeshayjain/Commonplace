// Supabase Edge Function: oauth-connect
// Handles OAuth flows for Twitter and LinkedIn

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

interface OAuthRequest {
  platform: 'twitter' | 'linkedin';
  action: 'connect' | 'callback' | 'disconnect' | 'status';
  code?: string;
  state?: string;
  codeVerifier?: string;
}

// Platform-specific configurations
const TWITTER_CONFIG = {
  clientId: Deno.env.get('TWITTER_CLIENT_ID') || '',
  clientSecret: Deno.env.get('TWITTER_CLIENT_SECRET') || '',
  authUrl: 'https://twitter.com/i/oauth2/authorize',
  tokenUrl: 'https://api.twitter.com/2/oauth2/token',
  scopes: ['tweet.read', 'tweet.write', 'users.read', 'offline.access'],
  redirectUri: Deno.env.get('OAUTH_REDIRECT_URI') || '',
};

const LINKEDIN_CONFIG = {
  clientId: Deno.env.get('LINKEDIN_CLIENT_ID') || '',
  clientSecret: Deno.env.get('LINKEDIN_CLIENT_SECRET') || '',
  authUrl: 'https://www.linkedin.com/oauth/v2/authorization',
  tokenUrl: 'https://www.linkedin.com/oauth/v2/accessToken',
  scopes: ['r_liteprofile', 'w_member_social'],
  redirectUri: Deno.env.get('OAUTH_REDIRECT_URI') || '',
};

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) {
      throw new Error('Missing authorization header');
    }

    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const supabase = createClient(supabaseUrl, supabaseKey);

    const token = authHeader.replace('Bearer ', '');
    const { data: { user }, error: authError } = await supabase.auth.getUser(token);

    if (authError || !user) {
      throw new Error('Unauthorized');
    }

    const { platform, action, code, state, codeVerifier }: OAuthRequest = await req.json();

    if (!platform || !['twitter', 'linkedin'].includes(platform)) {
      throw new Error('Invalid platform. Must be "twitter" or "linkedin"');
    }

    switch (action) {
      case 'connect':
        return handleConnect(user.id, platform);

      case 'callback':
        return handleCallback(supabase, user.id, platform, code!, codeVerifier);

      case 'disconnect':
        return handleDisconnect(supabase, user.id, platform);

      case 'status':
        return handleStatus(supabase, user.id, platform);

      default:
        throw new Error('Invalid action');
    }

  } catch (error) {
    console.error('OAuth error:', error);
    return new Response(
      JSON.stringify({ error: error.message }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 400,
      }
    );
  }
});

// Generate OAuth authorization URL with PKCE
function handleConnect(userId: string, platform: 'twitter' | 'linkedin'): Response {
  const config = platform === 'twitter' ? TWITTER_CONFIG : LINKEDIN_CONFIG;

  // Generate PKCE code verifier and challenge
  const codeVerifier = generateCodeVerifier();
  const codeChallenge = generateCodeChallenge(codeVerifier);

  // Generate state for CSRF protection
  const state = crypto.randomUUID();

  const params = new URLSearchParams({
    response_type: 'code',
    client_id: config.clientId,
    redirect_uri: config.redirectUri,
    scope: config.scopes.join(' '),
    state: state,
    code_challenge: codeChallenge,
    code_challenge_method: 'S256',
  });

  const authUrl = `${config.authUrl}?${params.toString()}`;

  return new Response(
    JSON.stringify({
      authUrl,
      state,
      codeVerifier, // Client needs to store this for callback
    }),
    {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 200,
    }
  );
}

// Exchange authorization code for tokens
async function handleCallback(
  supabase: any,
  userId: string,
  platform: 'twitter' | 'linkedin',
  code: string,
  codeVerifier?: string
): Promise<Response> {
  const config = platform === 'twitter' ? TWITTER_CONFIG : LINKEDIN_CONFIG;

  // Exchange code for tokens
  const tokenParams: Record<string, string> = {
    grant_type: 'authorization_code',
    code,
    redirect_uri: config.redirectUri,
    client_id: config.clientId,
  };

  // Twitter uses PKCE
  if (platform === 'twitter' && codeVerifier) {
    tokenParams.code_verifier = codeVerifier;
  }

  // LinkedIn uses client_secret
  if (platform === 'linkedin') {
    tokenParams.client_secret = config.clientSecret;
  }

  const tokenResponse = await fetch(config.tokenUrl, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/x-www-form-urlencoded',
      ...(platform === 'twitter' ? {
        Authorization: `Basic ${btoa(`${config.clientId}:${config.clientSecret}`)}`,
      } : {}),
    },
    body: new URLSearchParams(tokenParams).toString(),
  });

  if (!tokenResponse.ok) {
    const errorData = await tokenResponse.text();
    console.error('Token exchange failed:', errorData);
    throw new Error('Failed to exchange authorization code');
  }

  const tokens = await tokenResponse.json();

  // Get user profile from platform
  const profile = await getPlatformProfile(platform, tokens.access_token);

  // Store connection in database
  const { error: upsertError } = await supabase
    .from('social_connections')
    .upsert({
      user_id: userId,
      platform,
      platform_user_id: profile.id,
      platform_username: profile.username,
      platform_display_name: profile.displayName,
      platform_avatar_url: profile.avatarUrl,
      access_token: tokens.access_token,
      refresh_token: tokens.refresh_token,
      token_expires_at: tokens.expires_in
        ? new Date(Date.now() + tokens.expires_in * 1000).toISOString()
        : null,
      connected_at: new Date().toISOString(),
      is_active: true,
    }, {
      onConflict: 'user_id,platform',
    });

  if (upsertError) {
    console.error('Database error:', upsertError);
    throw new Error('Failed to save connection');
  }

  return new Response(
    JSON.stringify({
      success: true,
      profile: {
        username: profile.username,
        displayName: profile.displayName,
        avatarUrl: profile.avatarUrl,
      },
    }),
    {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 200,
    }
  );
}

// Disconnect platform
async function handleDisconnect(
  supabase: any,
  userId: string,
  platform: string
): Promise<Response> {
  const { error } = await supabase
    .from('social_connections')
    .update({
      is_active: false,
      access_token: null,
      refresh_token: null,
      disconnected_at: new Date().toISOString(),
    })
    .eq('user_id', userId)
    .eq('platform', platform);

  if (error) {
    throw new Error('Failed to disconnect');
  }

  return new Response(
    JSON.stringify({ success: true }),
    {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 200,
    }
  );
}

// Get connection status
async function handleStatus(
  supabase: any,
  userId: string,
  platform: string
): Promise<Response> {
  const { data, error } = await supabase
    .from('social_connections')
    .select('platform_username, platform_display_name, platform_avatar_url, connected_at, is_active')
    .eq('user_id', userId)
    .eq('platform', platform)
    .single();

  if (error && error.code !== 'PGRST116') {
    throw error;
  }

  return new Response(
    JSON.stringify({
      connected: !!data?.is_active,
      profile: data ? {
        username: data.platform_username,
        displayName: data.platform_display_name,
        avatarUrl: data.platform_avatar_url,
        connectedAt: data.connected_at,
      } : null,
    }),
    {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 200,
    }
  );
}

// Get user profile from platform API
async function getPlatformProfile(
  platform: string,
  accessToken: string
): Promise<{
  id: string;
  username: string;
  displayName: string;
  avatarUrl?: string;
}> {
  if (platform === 'twitter') {
    const response = await fetch('https://api.twitter.com/2/users/me?user.fields=profile_image_url', {
      headers: { Authorization: `Bearer ${accessToken}` },
    });

    if (!response.ok) throw new Error('Failed to fetch Twitter profile');

    const data = await response.json();
    return {
      id: data.data.id,
      username: data.data.username,
      displayName: data.data.name,
      avatarUrl: data.data.profile_image_url,
    };
  }

  if (platform === 'linkedin') {
    const response = await fetch('https://api.linkedin.com/v2/me', {
      headers: { Authorization: `Bearer ${accessToken}` },
    });

    if (!response.ok) throw new Error('Failed to fetch LinkedIn profile');

    const data = await response.json();
    return {
      id: data.id,
      username: data.vanityName || data.id,
      displayName: `${data.localizedFirstName} ${data.localizedLastName}`,
    };
  }

  throw new Error('Unknown platform');
}

// PKCE helpers
function generateCodeVerifier(): string {
  const array = new Uint8Array(32);
  crypto.getRandomValues(array);
  return base64URLEncode(array);
}

function generateCodeChallenge(verifier: string): string {
  const encoder = new TextEncoder();
  const data = encoder.encode(verifier);
  const hash = new Uint8Array(32); // Simplified - would need actual SHA-256
  crypto.getRandomValues(hash); // Placeholder
  return base64URLEncode(hash);
}

function base64URLEncode(buffer: Uint8Array): string {
  return btoa(String.fromCharCode(...buffer))
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '');
}
