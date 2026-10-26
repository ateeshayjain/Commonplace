// Supabase Edge Function: synthesize-content
// Performs multi-dimensional analysis and content synthesis from multiple documents

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { Anthropic, CLAUDE_MODELS, generateJSON, type ClaudeEffort } from '../_shared/claude.ts';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

interface SynthesizeRequest {
  documentIds: string[];
  contentTypes: string[];
  platforms: string[];
  thinkingDepth: string;
  includeHashtags: boolean;
  customPrompt?: string;
}

const STRING_LIST = { type: 'array', items: { type: 'string' } };

// Shape consumed by ComposeViewModel (SynthesisResult) in the iOS app
const SYNTHESIS_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: [
    'title', 'executive_summary', 'first_order_insights', 'second_order_insights', 'third_order_insights',
    'common_themes', 'contrasts', 'future_implications', 'actionable_advice', 'generated_content',
  ],
  properties: {
    title: { type: 'string' },
    executive_summary: { type: 'string' },
    first_order_insights: STRING_LIST,
    second_order_insights: STRING_LIST,
    third_order_insights: STRING_LIST,
    common_themes: STRING_LIST,
    contrasts: STRING_LIST,
    future_implications: STRING_LIST,
    actionable_advice: STRING_LIST,
    generated_content: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['type', 'platform', 'title', 'content', 'hashtags', 'thread_parts'],
        properties: {
          type: { type: 'string' },
          platform: { type: 'string' },
          title: { type: 'string' },
          content: { type: 'string' },
          hashtags: STRING_LIST,
          thread_parts: STRING_LIST,
        },
      },
    },
  },
};

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) throw new Error('Missing authorization header');

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    );

    const token = authHeader.replace('Bearer ', '');
    const { data: { user }, error: authError } = await supabase.auth.getUser(token);
    if (authError || !user) throw new Error('Unauthorized');

    const request: SynthesizeRequest = await req.json();
    const { documentIds, contentTypes, platforms, thinkingDepth, includeHashtags, customPrompt } = request;

    if (!documentIds?.length) throw new Error('At least one document is required');

    // Fetch all documents
    const { data: documents, error: docError } = await supabase
      .from('documents')
      .select('*')
      .in('id', documentIds)
      .eq('user_id', user.id);

    if (docError || !documents?.length) throw new Error('Documents not found');

    // Get user's voice profile if available
    const { data: voiceProfiles } = await supabase
      .from('voice_profiles')
      .select('*')
      .eq('user_id', user.id);

    // Perform synthesis
    const synthesis = await synthesizeDocuments(
      documents,
      contentTypes,
      platforms,
      thinkingDepth,
      includeHashtags,
      customPrompt,
      voiceProfiles || []
    );

    return new Response(
      JSON.stringify({ success: true, synthesis }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 200 }
    );

  } catch (error) {
    console.error('Synthesis error:', error);
    return new Response(
      JSON.stringify({ error: (error as Error).message }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 400 }
    );
  }
});

async function synthesizeDocuments(
  documents: any[],
  contentTypes: string[],
  platforms: string[],
  thinkingDepth: string,
  includeHashtags: boolean,
  customPrompt: string | undefined,
  voiceProfiles: any[]
) {
  const anthropicApiKey = Deno.env.get('ANTHROPIC_API_KEY');

  if (!anthropicApiKey) {
    return generateFallbackSynthesis(documents, contentTypes, platforms);
  }

  const anthropic = new Anthropic({ apiKey: anthropicApiKey });

  // Prepare document summaries for context
  const documentContext = documents.map((doc, i) => `
### ARTICLE ${i + 1}: ${doc.title}
Source: ${doc.source_type} | Author: ${doc.author_name || 'Unknown'}
Summary: ${doc.ai_summary_short || doc.body_plain?.substring(0, 500)}
Key Points: ${(doc.ai_key_points || []).join(', ')}
Full Content (excerpt): ${doc.body_plain?.substring(0, 2000)}
`).join('\n\n---\n\n');

  // Build the analysis prompt based on thinking depth
  const thinkingPrompt = buildThinkingPrompt(thinkingDepth);
  const contentPrompt = buildContentPrompt(contentTypes, platforms, includeHashtags);
  const voicePrompt = buildVoicePrompt(voiceProfiles, platforms);

  const systemPrompt = `You are a world-class analyst and content strategist. Your job is to synthesize multiple articles into actionable insights and compelling content.

You think in multiple dimensions:
- FIRST ORDER: What do the articles explicitly say? (Direct takeaways)
- SECOND ORDER: What patterns, connections, and tensions exist ACROSS the articles? What would someone miss if they read them separately?
- THIRD ORDER: What are the non-obvious implications? What does this mean for the future? What contrarian insights emerge? What would a genius-level thinker conclude?

${voicePrompt}

You always provide actionable, specific insights - never generic observations.`;

  const userPrompt = `Analyze these ${documents.length} articles and synthesize them into valuable insights and content.

${documentContext}

---

${thinkingPrompt}

${contentPrompt}

${customPrompt ? `\nADDITIONAL INSTRUCTIONS FROM USER:\n${customPrompt}\n` : ''}

OUTPUT FIELDS:
- title: compelling title that captures the synthesis
- executive_summary: 2-3 sentences on the key insight
- first_order_insights / second_order_insights / third_order_insights: 3 each
- common_themes (3), contrasts, future_implications (next 1-5 years), actionable_advice (specific actions)
- generated_content: one item per requested content type and platform, with "type" (e.g. "Social Post", "Twitter Thread", "Newsletter", "Long-form Article", "Executive Summary"), "platform", "title", "content" (the post or article text; empty string for threads), "hashtags" (empty array when not requested) and "thread_parts" (one string per tweet for threads, otherwise an empty array).

IMPORTANT:
- Be SPECIFIC, not generic. Reference actual content from the articles.
- Second-order insights should reveal connections the reader wouldn't see from individual articles.
- Third-order insights should be genuinely surprising or contrarian.
- Generated content should be immediately publishable - polished and engaging.
- For threads, each part should be under 280 characters and standalone compelling.`;

  try {
    return await generateJSON<Record<string, unknown>>(anthropic, {
      model: CLAUDE_MODELS.deepReasoning,
      effort: effortForThinkingDepth(thinkingDepth),
      schema: SYNTHESIS_SCHEMA,
      system: systemPrompt,
      prompt: userPrompt,
    });
  } catch (e) {
    console.error('Claude synthesis failed:', e);
  }

  return generateFallbackSynthesis(documents, contentTypes, platforms);
}

// Deeper synthesis gets more reasoning effort (and more latency/cost)
function effortForThinkingDepth(depth: string): ClaudeEffort {
  switch (depth) {
    case 'Surface Level':
      return 'low';
    case 'Second Order':
      return 'medium';
    case 'Third Order':
    default:
      return 'high';
  }
}

function buildThinkingPrompt(depth: string): string {
  switch (depth) {
    case 'Surface Level':
      return `Focus primarily on FIRST ORDER thinking:
- What are the main points of each article?
- What facts and data are presented?
- What do the authors conclude?`;

    case 'Second Order':
      return `Focus on FIRST and SECOND ORDER thinking:
- What patterns emerge across all articles?
- Where do the articles agree or disagree?
- What would someone miss if they only read one article?
- What synthesis emerges from reading all of them together?`;

    case 'Third Order':
    default:
      return `Apply ALL THREE LEVELS of thinking:
- FIRST ORDER: What do the articles say?
- SECOND ORDER: What patterns and connections exist across articles?
- THIRD ORDER:
  * What are the non-obvious implications?
  * What would a genius-level thinker conclude that most people would miss?
  * What contrarian insights emerge?
  * What does this mean for the future (1-5 years)?
  * What should smart people do differently based on this synthesis?
  * What's the "meta" insight - the insight about the insights?`;
  }
}

function buildContentPrompt(contentTypes: string[], platforms: string[], includeHashtags: boolean): string {
  const typeInstructions = contentTypes.map(type => {
    switch (type) {
      case 'Social Post':
        return `- Social Posts: Create punchy, engaging posts for ${platforms.join(' and ')}. Twitter max 280 chars. LinkedIn can be longer.`;
      case 'Twitter Thread':
        return `- Twitter Thread: Create a compelling 5-7 tweet thread. Each tweet should stand alone but build to a cohesive narrative. Start with a hook.`;
      case 'Newsletter':
        return `- Newsletter: Write a weekly digest format with personal commentary. Include "Why this matters" sections.`;
      case 'Long-form Article':
        return `- Article: Create a structured long-form piece with introduction, key sections, and conclusion.`;
      case 'Executive Summary':
        return `- Executive Summary: Bullet-point format for busy readers. Lead with the most important insight.`;
      default:
        return '';
    }
  }).filter(Boolean).join('\n');

  return `
CONTENT TO GENERATE:
${typeInstructions}
${includeHashtags ? '\nInclude relevant hashtags (3-5 per post).' : '\nDo not include hashtags.'}`;
}

function buildVoicePrompt(voiceProfiles: any[], platforms: string[]): string {
  if (!voiceProfiles.length) {
    return 'Write in a professional but engaging tone. Be direct and insightful.';
  }

  const relevantProfiles = voiceProfiles.filter(p => platforms.includes(p.platform));
  if (!relevantProfiles.length) {
    return 'Write in a professional but engaging tone. Be direct and insightful.';
  }

  return relevantProfiles.map(profile => `
For ${profile.platform.toUpperCase()} content, match this voice:
- Tone: ${profile.tone}
- Vocabulary Level: ${profile.vocabulary_level}/10
- Style: ${profile.engagement_style}
- Structure: ${profile.post_structure}
${profile.sample_phrases?.length ? `- Phrases they use: ${profile.sample_phrases.slice(0, 3).join(', ')}` : ''}
`).join('\n');
}

function generateFallbackSynthesis(documents: any[], contentTypes: string[], platforms: string[]) {
  const titles = documents.map(d => d.title).join(', ');
  const combinedSummary = documents.map(d => d.ai_summary_short || '').filter(Boolean).join(' ');

  return {
    title: `Synthesis: ${documents.length} Articles`,
    executive_summary: combinedSummary.substring(0, 200) || 'Analysis of selected articles.',
    first_order_insights: documents.map(d => d.title),
    second_order_insights: ['Multiple perspectives on this topic'],
    third_order_insights: ['Further analysis required'],
    common_themes: [],
    contrasts: [],
    future_implications: [],
    actionable_advice: ['Read the full articles for complete context'],
    generated_content: [{
      type: 'Social Post',
      platform: platforms[0] || 'twitter',
      title: '',
      content: `Interesting reads: ${titles.substring(0, 200)}`,
      hashtags: []
    }]
  };
}
