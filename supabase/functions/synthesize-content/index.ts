// Supabase Edge Function: synthesize-content
// Performs multi-dimensional analysis and content synthesis from multiple documents

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import Anthropic from "https://esm.sh/@anthropic-ai/sdk@0.17.1";

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
      JSON.stringify({ error: error.message }),
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

Respond with this exact JSON structure:
{
  "title": "Compelling title that captures the synthesis",
  "executive_summary": "2-3 sentence executive summary of the key insight",
  "first_order_insights": ["Direct insight 1", "Direct insight 2", "Direct insight 3"],
  "second_order_insights": ["Pattern/connection 1", "Pattern/connection 2", "Pattern/connection 3"],
  "third_order_insights": ["Future implication 1", "Contrarian take 1", "Non-obvious insight 1"],
  "common_themes": ["Theme 1", "Theme 2", "Theme 3"],
  "contrasts": ["Tension or disagreement between articles"],
  "future_implications": ["What this means for the next 1-5 years"],
  "actionable_advice": ["Specific action reader can take based on this synthesis"],
  "generated_content": [
    {
      "type": "Social Post",
      "platform": "twitter",
      "title": "",
      "content": "The actual post content under 280 chars",
      "hashtags": ["relevant", "hashtags"]
    },
    {
      "type": "Twitter Thread",
      "platform": "twitter",
      "title": "Thread title",
      "content": "",
      "thread_parts": ["1/ First tweet of thread", "2/ Second tweet", "3/ Third tweet with conclusion"]
    }
  ]
}

IMPORTANT:
- Be SPECIFIC, not generic. Reference actual content from the articles.
- Second-order insights should reveal connections the reader wouldn't see from individual articles.
- Third-order insights should be genuinely surprising or contrarian.
- Generated content should be immediately publishable - polished and engaging.
- For threads, each part should be under 280 characters and standalone compelling.`;

  try {
    const response = await anthropic.messages.create({
      model: 'claude-sonnet-4-20250514',
      max_tokens: 4000,
      messages: [
        { role: 'user', content: userPrompt }
      ],
      system: systemPrompt,
    });

    const text = response.content[0].type === 'text' ? response.content[0].text : '';
    const jsonMatch = text.match(/\{[\s\S]*\}/);

    if (jsonMatch) {
      const parsed = JSON.parse(jsonMatch[0]);
      return parsed;
    }
  } catch (e) {
    console.error('Claude synthesis failed:', e);
  }

  return generateFallbackSynthesis(documents, contentTypes, platforms);
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
