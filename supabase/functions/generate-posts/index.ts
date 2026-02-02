// Supabase Edge Function: generate-posts
// Generates platform-specific social media posts based on user's voice profile

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import Anthropic from "https://esm.sh/@anthropic-ai/sdk@0.17.1";

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

interface GeneratePostsRequest {
  documentId: string;
  platforms: ('twitter' | 'linkedin')[];
}

interface VoiceProfile {
  platform: string;
  tone: string;
  vocabulary_level: number;
  post_structure: string;
  hashtag_usage: string;
  engagement_style: string;
  top_topics: string[];
  sample_phrases: string[];
}

interface GeneratedPost {
  platform: string;
  variations: {
    content: string;
    hashtags: string[];
    characterCount: number;
    isOptimal: boolean;
  }[];
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

    const { documentId, platforms }: GeneratePostsRequest = await req.json();

    if (!documentId) {
      throw new Error('Document ID is required');
    }

    if (!platforms || platforms.length === 0) {
      throw new Error('At least one platform is required');
    }

    // Get document
    const { data: document, error: docError } = await supabase
      .from('documents')
      .select('*')
      .eq('id', documentId)
      .eq('user_id', user.id)
      .single();

    if (docError || !document) {
      throw new Error('Document not found');
    }

    // Get voice profiles for requested platforms
    const { data: profiles } = await supabase
      .from('voice_profiles')
      .select('*')
      .eq('user_id', user.id)
      .in('platform', platforms);

    // Generate posts for each platform
    const generatedPosts = await generatePlatformPosts(document, platforms, profiles || []);

    // Create or update campaign
    const { data: campaign, error: campaignError } = await supabase
      .from('campaigns')
      .upsert({
        user_id: user.id,
        document_id: documentId,
        status: 'draft',
        platforms: platforms,
      }, {
        onConflict: 'user_id,document_id',
      })
      .select()
      .single();

    if (campaignError) {
      console.error('Campaign error:', campaignError);
    }

    // Store generated posts
    if (campaign) {
      for (const post of generatedPosts) {
        for (let i = 0; i < post.variations.length; i++) {
          const variation = post.variations[i];
          await supabase.from('campaign_posts').insert({
            campaign_id: campaign.id,
            platform: post.platform,
            content: variation.content,
            hashtags: variation.hashtags,
            variation_index: i,
            is_selected: i === 0, // Select first variation by default
            status: 'draft',
          });
        }
      }
    }

    return new Response(
      JSON.stringify({
        success: true,
        campaignId: campaign?.id,
        posts: generatedPosts,
      }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 200,
      }
    );

  } catch (error) {
    console.error('Error:', error);
    return new Response(
      JSON.stringify({ error: error.message }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 400,
      }
    );
  }
});

async function generatePlatformPosts(
  document: any,
  platforms: string[],
  profiles: VoiceProfile[]
): Promise<GeneratedPost[]> {
  const anthropicApiKey = Deno.env.get('ANTHROPIC_API_KEY');

  if (!anthropicApiKey) {
    // Return simple defaults without AI
    return platforms.map(platform => ({
      platform,
      variations: [
        {
          content: `Check out: ${document.title}`,
          hashtags: [],
          characterCount: `Check out: ${document.title}`.length,
          isOptimal: true,
        },
      ],
    }));
  }

  const anthropic = new Anthropic({ apiKey: anthropicApiKey });
  const results: GeneratedPost[] = [];

  for (const platform of platforms) {
    const profile = profiles.find(p => p.platform === platform);
    const platformConstraints = getPlatformConstraints(platform);

    const prompt = buildPrompt(document, platform, profile, platformConstraints);

    try {
      const response = await anthropic.messages.create({
        model: 'claude-sonnet-4-20250514',
        max_tokens: 2000,
        messages: [{
          role: 'user',
          content: prompt,
        }],
      });

      const text = response.content[0].type === 'text' ? response.content[0].text : '';
      const parsed = parsePostResponse(text, platform, platformConstraints);

      results.push({
        platform,
        variations: parsed,
      });
    } catch (e) {
      console.error(`Failed to generate for ${platform}:`, e);
      results.push({
        platform,
        variations: [{
          content: `${document.title}\n\nRead more: [link]`,
          hashtags: [],
          characterCount: document.title.length + 20,
          isOptimal: false,
        }],
      });
    }
  }

  return results;
}

function getPlatformConstraints(platform: string): {
  maxLength: number;
  hashtagLimit: number;
  style: string;
} {
  switch (platform) {
    case 'twitter':
      return {
        maxLength: 280,
        hashtagLimit: 3,
        style: 'concise, punchy, often uses threads for longer content',
      };
    case 'linkedin':
      return {
        maxLength: 3000,
        hashtagLimit: 5,
        style: 'professional, thought leadership, may include personal insights',
      };
    default:
      return {
        maxLength: 500,
        hashtagLimit: 5,
        style: 'general social media',
      };
  }
}

function buildPrompt(
  document: any,
  platform: string,
  profile: VoiceProfile | undefined,
  constraints: { maxLength: number; hashtagLimit: number; style: string }
): string {
  let voiceSection = '';

  if (profile) {
    voiceSection = `
VOICE PROFILE (match this style closely):
- Tone: ${profile.tone}
- Vocabulary Level: ${profile.vocabulary_level}/10
- Post Structure: ${profile.post_structure}
- Hashtag Usage: ${profile.hashtag_usage}
- Engagement Style: ${profile.engagement_style}
- Frequently Discussed Topics: ${profile.top_topics?.join(', ')}
${profile.sample_phrases?.length ? `- Sample Phrases They Use: ${profile.sample_phrases.slice(0, 3).join(', ')}` : ''}
`;
  } else {
    voiceSection = `
No voice profile available. Use a professional, engaging tone appropriate for ${platform}.
`;
  }

  return `Write 3 ${platform} posts about this article. Each should be a unique take/angle.

ARTICLE:
Title: ${document.title}
${document.ai_summary_short ? `Summary: ${document.ai_summary_short}` : ''}
${document.ai_key_points?.length ? `Key Points:\n${document.ai_key_points.map((p: string) => `- ${p}`).join('\n')}` : ''}

PLATFORM CONSTRAINTS:
- Maximum length: ${constraints.maxLength} characters
- Maximum hashtags: ${constraints.hashtagLimit}
- Platform style: ${constraints.style}
${voiceSection}

OUTPUT FORMAT (respond with valid JSON only):
{
  "variations": [
    {
      "content": "Post text here (no hashtags in main text)",
      "hashtags": ["tag1", "tag2"],
      "angle": "key insight, question, personal take, etc."
    },
    {
      "content": "Second variation...",
      "hashtags": ["tag1", "tag2"],
      "angle": "..."
    },
    {
      "content": "Third variation...",
      "hashtags": ["tag1", "tag2"],
      "angle": "..."
    }
  ]
}

IMPORTANT:
- Each variation should take a DIFFERENT angle (insight, question, personal take, controversial opinion, etc.)
- Match the voice profile tone and style as closely as possible
- Keep content under ${constraints.maxLength} characters
- Make posts engaging and shareable
- For Twitter: be punchy and direct
- For LinkedIn: add professional context or personal insight`;
}

function parsePostResponse(
  text: string,
  platform: string,
  constraints: { maxLength: number; hashtagLimit: number }
): {
  content: string;
  hashtags: string[];
  characterCount: number;
  isOptimal: boolean;
}[] {
  try {
    // Extract JSON from response
    const jsonMatch = text.match(/\{[\s\S]*\}/);
    if (!jsonMatch) {
      throw new Error('No JSON found in response');
    }

    const parsed = JSON.parse(jsonMatch[0]);

    return parsed.variations.map((v: any) => {
      const hashtags = (v.hashtags || []).slice(0, constraints.hashtagLimit);
      const content = v.content.trim();
      const characterCount = content.length;

      return {
        content,
        hashtags,
        characterCount,
        isOptimal: characterCount <= constraints.maxLength,
      };
    });
  } catch (e) {
    console.error('Failed to parse post response:', e);

    // Return fallback
    return [{
      content: 'Failed to generate post',
      hashtags: [],
      characterCount: 0,
      isOptimal: false,
    }];
  }
}
