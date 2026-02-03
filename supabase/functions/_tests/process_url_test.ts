import { assertEquals, assertExists } from "https://deno.land/std@0.177.0/testing/asserts.ts";

// Mock AI Enrichment response parsing tests
// These test the JSON extraction logic from Claude responses

function extractJSONFromResponse(text: string): Record<string, any> | null {
  const jsonMatch = text.match(/\{[\s\S]*\}/);
  if (jsonMatch) {
    try {
      return JSON.parse(jsonMatch[0]);
    } catch {
      return null;
    }
  }
  return null;
}

// Platform detection tests
function detectPlatform(url: string): string {
  const patterns: Record<string, RegExp[]> = {
    twitter: [/twitter\.com/, /x\.com/],
    linkedin: [/linkedin\.com\/(posts|pulse|feed|in)\//],
    youtube: [/youtube\.com/, /youtu\.be/],
    instagram: [/instagram\.com\/(p|reel|tv)\//],
    threads: [/threads\.net/],
    reddit: [/reddit\.com/],
    hackernews: [/news\.ycombinator\.com/],
    substack: [/\.substack\.com/],
    medium: [/medium\.com/],
  };

  for (const [platform, regexes] of Object.entries(patterns)) {
    for (const regex of regexes) {
      if (regex.test(url)) {
        return platform;
      }
    }
  }

  return 'article';
}

// JSON Extraction Tests
Deno.test("extractJSONFromResponse - extracts valid JSON from response", () => {
  const response = `Here is the analysis:
{"summaryShort": "This is a test summary.", "keyPoints": ["Point 1", "Point 2"]}`;

  const result = extractJSONFromResponse(response);
  assertExists(result);
  assertEquals(result?.summaryShort, "This is a test summary.");
  assertEquals(result?.keyPoints?.length, 2);
});

Deno.test("extractJSONFromResponse - handles pure JSON response", () => {
  const response = '{"summaryShort": "Pure JSON", "complexityScore": 5}';

  const result = extractJSONFromResponse(response);
  assertExists(result);
  assertEquals(result?.summaryShort, "Pure JSON");
  assertEquals(result?.complexityScore, 5);
});

Deno.test("extractJSONFromResponse - returns null for invalid JSON", () => {
  const response = "This is just plain text with no JSON";

  const result = extractJSONFromResponse(response);
  assertEquals(result, null);
});

Deno.test("extractJSONFromResponse - handles malformed JSON gracefully", () => {
  const response = '{"summaryShort": "Incomplete JSON';

  const result = extractJSONFromResponse(response);
  assertEquals(result, null);
});

Deno.test("extractJSONFromResponse - extracts nested JSON", () => {
  const response = `Analysis complete:
{
  "summaryShort": "Test",
  "summaryLong": "Longer test summary with multiple sentences.",
  "keyPoints": ["First point", "Second point", "Third point"],
  "categories": ["Technology"],
  "topics": ["AI", "Testing"],
  "complexityScore": 7,
  "readingLevel": "intermediate"
}`;

  const result = extractJSONFromResponse(response);
  assertExists(result);
  assertEquals(result?.keyPoints?.length, 3);
  assertEquals(result?.complexityScore, 7);
  assertEquals(result?.readingLevel, "intermediate");
});

// Platform Detection Tests
Deno.test("detectPlatform - detects Twitter URLs", () => {
  assertEquals(detectPlatform("https://twitter.com/user/status/123"), "twitter");
  assertEquals(detectPlatform("https://x.com/user/status/123"), "twitter");
});

Deno.test("detectPlatform - detects LinkedIn URLs", () => {
  assertEquals(detectPlatform("https://linkedin.com/posts/user-123"), "linkedin");
  assertEquals(detectPlatform("https://linkedin.com/pulse/article-title"), "linkedin");
  assertEquals(detectPlatform("https://linkedin.com/in/username"), "linkedin");
});

Deno.test("detectPlatform - detects YouTube URLs", () => {
  assertEquals(detectPlatform("https://youtube.com/watch?v=abc123"), "youtube");
  assertEquals(detectPlatform("https://youtu.be/abc123"), "youtube");
});

Deno.test("detectPlatform - detects Reddit URLs", () => {
  assertEquals(detectPlatform("https://reddit.com/r/programming/comments/abc"), "reddit");
  assertEquals(detectPlatform("https://www.reddit.com/r/tech"), "reddit");
});

Deno.test("detectPlatform - detects Substack URLs", () => {
  assertEquals(detectPlatform("https://newsletter.substack.com/p/article"), "substack");
});

Deno.test("detectPlatform - detects Medium URLs", () => {
  assertEquals(detectPlatform("https://medium.com/@user/article-title"), "medium");
});

Deno.test("detectPlatform - returns article for unknown domains", () => {
  assertEquals(detectPlatform("https://example.com/blog/post"), "article");
  assertEquals(detectPlatform("https://news.site.com/article/123"), "article");
});

Deno.test("detectPlatform - detects HackerNews URLs", () => {
  assertEquals(detectPlatform("https://news.ycombinator.com/item?id=123"), "hackernews");
});

// Content cleaning tests
function cleanMarkdownContent(content: string): string {
  return content
    .replace(/!\[.*?\]\(.*?\)/g, '') // Remove markdown images
    .replace(/<img[^>]*>/gi, '') // Remove HTML img tags
    .replace(/\[([^\]]+)\]\([^)]+\)/g, '$1') // Keep link text, remove URL
    .replace(/^[-*_]{3,}$/gm, '') // Remove horizontal rules
    .replace(/\n{3,}/g, '\n\n') // Collapse multiple newlines
    .trim();
}

Deno.test("cleanMarkdownContent - removes markdown images", () => {
  const content = "Some text ![alt text](https://example.com/image.png) more text";
  const cleaned = cleanMarkdownContent(content);
  assertEquals(cleaned, "Some text  more text");
});

Deno.test("cleanMarkdownContent - removes HTML img tags", () => {
  const content = 'Text <img src="image.jpg" alt="test"> more text';
  const cleaned = cleanMarkdownContent(content);
  assertEquals(cleaned, "Text  more text");
});

Deno.test("cleanMarkdownContent - preserves link text", () => {
  const content = "Check out [this article](https://example.com) for more";
  const cleaned = cleanMarkdownContent(content);
  assertEquals(cleaned, "Check out this article for more");
});

Deno.test("cleanMarkdownContent - collapses multiple newlines", () => {
  const content = "First paragraph\n\n\n\n\nSecond paragraph";
  const cleaned = cleanMarkdownContent(content);
  assertEquals(cleaned, "First paragraph\n\nSecond paragraph");
});

// Tweet ID extraction test
function extractTweetId(url: string): string | null {
  const match = url.match(/status\/(\d+)/);
  return match ? match[1] : null;
}

Deno.test("extractTweetId - extracts ID from twitter.com URL", () => {
  assertEquals(extractTweetId("https://twitter.com/user/status/1234567890"), "1234567890");
});

Deno.test("extractTweetId - extracts ID from x.com URL", () => {
  assertEquals(extractTweetId("https://x.com/user/status/9876543210"), "9876543210");
});

Deno.test("extractTweetId - returns null for non-tweet URL", () => {
  assertEquals(extractTweetId("https://twitter.com/user"), null);
});
