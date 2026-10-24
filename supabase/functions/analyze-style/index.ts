// Supabase Edge Function: analyze-style
// Analyzes user's social media posts to build a voice profile

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { Anthropic, CLAUDE_MODELS, generateText } from '../_shared/claude.ts';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

interface AnalyzeStyleRequest {
  platform: 'twitter' | 'linkedin';
}

interface VoiceAnalysis {
  tone: string;
  vocabularyLevel: number;
  postStructure: string;
  hashtagUsage: string;
  engagementStyle: string;
  topTopics: string[];
  samplePhrases: string[];
  averageLength: number;
  emojiUsage: string;
  postingPatterns: string;
}

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

    const { platform }: AnalyzeStyleRequest = await req.json();

    if (!platform || !['twitter', 'linkedin'].includes(platform)) {
      throw new Error('Invalid platform');
    }

    // Get social connection
    const { data: connection, error: connError } = await supabase
      .from('social_connections')
      .select('*')
      .eq('user_id', user.id)
      .eq('platform', platform)
      .eq('is_active', true)
      .single();

    if (connError || !connection) {
      throw new Error(`No active ${platform} connection found`);
    }

    // Fetch user's recent posts from platform
    const posts = await fetchUserPosts(platform, connection.access_token, 50);

    if (posts.length < 5) {
      throw new Error('Need at least 5 posts to analyze style');
    }

    // Analyze with Claude
    const analysis = await analyzePostStyle(posts, platform);

    // Save voice profile
    const { error: upsertError } = await supabase
      .from('voice_profiles')
      .upsert({
        user_id: user.id,
        platform,
        tone: analysis.tone,
        vocabulary_level: analysis.vocabularyLevel,
        post_structure: analysis.postStructure,
        hashtag_usage: analysis.hashtagUsage,
        engagement_style: analysis.engagementStyle,
        top_topics: analysis.topTopics,
        sample_phrases: analysis.samplePhrases,
        average_length: analysis.averageLength,
        emoji_usage: analysis.emojiUsage,
        posting_patterns: analysis.postingPatterns,
        posts_analyzed: posts.length,
        last_analyzed_at: new Date().toISOString(),
      }, {
        onConflict: 'user_id,platform',
      });

    if (upsertError) {
      console.error('Failed to save profile:', upsertError);
      throw new Error('Failed to save voice profile');
    }

    return new Response(
      JSON.stringify({
        success: true,
        profile: analysis,
        postsAnalyzed: posts.length,
      }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 200,
      }
    );

  } catch (error) {
    console.error('Error:', error);
    return new Response(
      JSON.stringify({ error: (error as Error).message }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 400,
      }
    );
  }
});

async function fetchUserPosts(
  platform: string,
  accessToken: string,
  limit: number
): Promise<{ text: string; likes: number; shares: number; date: string }[]> {
  if (platform === 'twitter') {
    // Get user ID first
    const meResponse = await fetch('https://api.twitter.com/2/users/me', {
      headers: { Authorization: `Bearer ${accessToken}` },
    });

    if (!meResponse.ok) {
      throw new Error('Failed to fetch Twitter user');
    }

    const me = await meResponse.json();
    const userId = me.data.id;

    // Get user's tweets
    const tweetsResponse = await fetch(
      `https://api.twitter.com/2/users/${userId}/tweets?max_results=${limit}&tweet.fields=public_metrics,created_at`,
      { headers: { Authorization: `Bearer ${accessToken}` } }
    );

    if (!tweetsResponse.ok) {
      throw new Error('Failed to fetch tweets');
    }

    const tweets = await tweetsResponse.json();

    return (tweets.data || []).map((tweet: any) => ({
      text: tweet.text,
      likes: tweet.public_metrics?.like_count || 0,
      shares: tweet.public_metrics?.retweet_count || 0,
      date: tweet.created_at,
    }));
  }

  if (platform === 'linkedin') {
    // LinkedIn API for user posts
    // Note: LinkedIn's API is more restrictive - this is simplified
    const response = await fetch(
      'https://api.linkedin.com/v2/ugcPosts?q=authors&authors=List(urn:li:person:me)&count=' + limit,
      { headers: { Authorization: `Bearer ${accessToken}` } }
    );

    if (!response.ok) {
      // LinkedIn API may require additional permissions
      console.log('LinkedIn API response:', await response.text());
      return [];
    }

    const data = await response.json();

    return (data.elements || []).map((post: any) => ({
      text: post.specificContent?.['com.linkedin.ugc.ShareContent']?.shareCommentary?.text || '',
      likes: post.socialDetail?.totalSocialActivityCounts?.numLikes || 0,
      shares: post.socialDetail?.totalSocialActivityCounts?.numShares || 0,
      date: new Date(post.created?.time || Date.now()).toISOString(),
    }));
  }

  return [];
}

async function analyzePostStyle(
  posts: { text: string; likes: number; shares: number }[],
  platform: string
): Promise<VoiceAnalysis> {
  const anthropicApiKey = Deno.env.get('ANTHROPIC_API_KEY');

  if (!anthropicApiKey) {
    // Return defaults without AI
    return {
      tone: 'professional',
      vocabularyLevel: 5,
      postStructure: 'medium',
      hashtagUsage: 'moderate',
      engagementStyle: 'informative',
      topTopics: [],
      samplePhrases: [],
      averageLength: Math.round(posts.reduce((sum, p) => sum + p.text.length, 0) / posts.length),
      emojiUsage: 'minimal',
      postingPatterns: 'unknown',
    };
  }

  const anthropic = new Anthropic({ apiKey: anthropicApiKey });

  // Prepare posts for analysis (top performing first)
  const sortedPosts = [...posts].sort((a, b) => (b.likes + b.shares) - (a.likes + a.shares));
  const postsText = sortedPosts
    .slice(0, 30) // Limit to 30 posts
    .map((p, i) => `[Post ${i + 1}] (${p.likes} likes, ${p.shares} shares)\n${p.text}`)
    .join('\n\n---\n\n');

  try {
    const text = await generateText(anthropic, {
      model: CLAUDE_MODELS.standard,
      effort: 'medium',
      prompt: `Analyze these ${platform} posts and create a voice profile. Look for patterns in writing style, tone, and engagement.

POSTS:
${postsText}

Analyze and respond with this exact JSON structure:
{
  "tone": "<dominant tone: professional/casual/humorous/inspirational/authoritative/conversational>",
  "vocabularyLevel": <1-10, where 1=very simple, 10=highly technical>,
  "postStructure": "<short/medium/long/mixed/thread-style>",
  "hashtagUsage": "<none/minimal/moderate/heavy>",
  "engagementStyle": "<informative/provocative/questioning/storytelling/educational>",
  "topTopics": ["topic1", "topic2", "topic3", "topic4", "topic5"],
  "samplePhrases": ["phrase they often use 1", "phrase 2", "phrase 3"],
  "emojiUsage": "<none/minimal/moderate/heavy>",
  "postingPatterns": "<brief description of patterns, e.g., 'opens with questions, uses numbered lists'>"
}

Only respond with valid JSON.`,
    });

    const jsonMatch = text.match(/\{[\s\S]*\}/);

    if (!jsonMatch) {
      throw new Error('No JSON in response');
    }

    const parsed = JSON.parse(jsonMatch[0]);

    return {
      tone: parsed.tone || 'professional',
      vocabularyLevel: parsed.vocabularyLevel || 5,
      postStructure: parsed.postStructure || 'medium',
      hashtagUsage: parsed.hashtagUsage || 'moderate',
      engagementStyle: parsed.engagementStyle || 'informative',
      topTopics: parsed.topTopics || [],
      samplePhrases: parsed.samplePhrases || [],
      averageLength: Math.round(posts.reduce((sum, p) => sum + p.text.length, 0) / posts.length),
      emojiUsage: parsed.emojiUsage || 'minimal',
      postingPatterns: parsed.postingPatterns || '',
    };

  } catch (e) {
    console.error('AI analysis failed:', e);

    // Return basic analysis
    return {
      tone: 'professional',
      vocabularyLevel: 5,
      postStructure: 'medium',
      hashtagUsage: 'moderate',
      engagementStyle: 'informative',
      topTopics: [],
      samplePhrases: [],
      averageLength: Math.round(posts.reduce((sum, p) => sum + p.text.length, 0) / posts.length),
      emojiUsage: 'minimal',
      postingPatterns: 'Analysis incomplete',
    };
  }
}
