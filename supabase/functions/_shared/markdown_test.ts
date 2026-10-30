import { assertEquals } from "jsr:@std/assert@1";
import { bodyToBlocks, cleanArticleMarkdown, cleanInline, looksLikeMarkdown, scribdPagesToText } from "./markdown.ts";

Deno.test("cleanInline drops images, keeps link text and footnote numbers", () => {
  assertEquals(
    cleanInline("[![Image 4](https://cdn.example.com/a,w_1456/b.jpeg)](https://cdn.example.com/b.jpeg)See **this** [report](https://ex.com/r?a=1) [[29](https://ex.com/#f29)]"),
    "See this report [29]",
  );
});

Deno.test("cleanInline leaves snake_case, hashtags and arithmetic alone", () => {
  assertEquals(cleanInline("set max_retry_count to 3 #buildinpublic 2 * 3 * 4"), "set max_retry_count to 3 #buildinpublic 2 * 3 * 4");
  assertEquals(cleanInline("an *emphasised* word and _another_ one"), "an emphasised word and another one");
});

Deno.test("Substack masthead, byline, counts and comments are removed", () => {
  const md = [
    "[![Image 1: Pub](https://substackcdn.com/x.png)](https://pub.example/)",
    "# [Pub](https://pub.example/)",
    "Subscribe Sign in",
    "Discover more from Pub",
    "# The Title",
    "### The subtitle",
    "[Jane Doe](https://substack.com/@jane)",
    "Oct 27, 2026",
    "261",
    "34",
    "Share",
    "",
    "First paragraph with a [link](https://ex.com).",
    "",
    "#### 1. A section",
    "",
    "> A quoted",
    "> passage.",
    "",
    "- one",
    "- two",
    "",
    "* * *",
    "Subscribe",
    "[261 Likes](https://pub.example/p/x)∙",
    "#### Discussion about this post",
    "Comment text that must not appear.",
  ].join("\n");
  const result = cleanArticleMarkdown(md, "The Title");
  assertEquals(result.text, [
    "The subtitle",
    "First paragraph with a link.",
    "1. A section",
    "A quoted passage.",
    "• one\n• two",
  ].join("\n\n"));
  assertEquals(result.headings, ["The subtitle", "1. A section"]);
  assertEquals(result.byline, "Jane Doe");
});

Deno.test("a co-authored Substack byline becomes the author, not body text", () => {
  const md = [
    "# The Title",
    "### The subtitle",
    "[![Image 4: A's avatar](https://substackcdn.com/a.jpeg)](https://substack.com/@clubx)[![Image 5: B's avatar](https://substackcdn.com/b.png)](https://substack.com/@readyourself)",
    "",
    "[Thee Book Club](https://substack.com/@clubx) and [LN James](https://substack.com/@readyourself)",
    "",
    "Oct 23, 2026",
    "",
    "Hello,",
  ].join("\n");
  const result = cleanArticleMarkdown(md, "The Title");
  assertEquals(result.byline, "Thee Book Club and LN James");
  assertEquals(result.text, "The subtitle\n\nHello,");
});

Deno.test("profile links inside the body are not taken as the byline", () => {
  const md = "# T\n\nFirst paragraph.\n\n[Jane Doe](https://substack.com/@jane)\n\nMore.";
  assertEquals(cleanArticleMarkdown(md, "T").byline, undefined);
});

Deno.test("Medium reading time, sign-up box and author footer are removed", () => {
  const md = [
    "# Title",
    "9 min read",
    "",
    "Body one.",
    "",
    "## Get Jane Doe’s stories in your inbox",
    "Join Medium for free to get updates from this writer.",
    "Subscribe",
    "- [x] ",
    "Remember me for faster sign in",
    "",
    "## A real section",
    "Body two.",
    "",
    "## [Written by Jane Doe](https://medium.com/@jane)",
    "I write about things.",
  ].join("\n");
  const result = cleanArticleMarkdown(md, "Title");
  assertEquals(result.text, "Body one.\n\nA real section\n\nBody two.");
  assertEquals(result.headings, ["A real section"]);
});

Deno.test("a guest post opening with 'Written by' keeps its body", () => {
  const result = cleanArticleMarkdown("# Title\n\nWritten by our guest, Jane Doe.\n\nThe argument.", "Title");
  assertEquals(result.text, "Written by our guest, Jane Doe.\n\nThe argument.");
});

Deno.test("plain bodies (X posts) are not treated as Markdown", () => {
  assertEquals(looksLikeMarkdown("Thread on #AI 🧵\n\n1/ the_point is simple"), false);
  assertEquals(looksLikeMarkdown("See [this](https://ex.com)"), true);
});

Deno.test("bodyToBlocks marks stored headings in plain text", () => {
  const blocks = bodyToBlocks("Intro\n\n1. A section\n\nBody text\n\n• one\n• two", "T", ["1. A section"]);
  assertEquals(blocks.map((b) => b.kind), ["paragraph", "heading", "paragraph", "list"]);
});

Deno.test("hostile lines are cleaned in linear time", () => {
  // 200k characters of unclosed emphasis and link openers took 6-10 s before spans were bounded
  for (const unit of ["*a ", "_a ", "[a ", "**a "]) {
    const started = performance.now();
    cleanInline(unit.repeat(200_000 / unit.length));
    const elapsed = performance.now() - started;
    if (elapsed > 1000) throw new Error(`"${unit}" line took ${Math.round(elapsed)} ms`);
  }
});

Deno.test("images whose alt text spans lines are removed whole (Scribd pages)", () => {
  const md = [
    "# Vigyan Bhairava Tantra",
    "",
    "Intro line.",
    "",
    "![Image 2: VIJNANA BHAIRAVA ",
    "Commentary by ",
    "Swami Lakshman Joo ",
    "](https://screenshots.scribd.com/Scribd/252_100_85/395/441070610/1.jpeg)",
    "",
    "![Image 4: Verses translated ",
    "",
    "Cover illustration](https://screenshots.scribd.com/Scribd/252_100_85/395/441070610/3.jpeg)",
    "",
    "Closing line.",
  ].join("\n");
  assertEquals(cleanArticleMarkdown(md, "Vigyan Bhairava Tantra").text, "Intro line.\n\nClosing line.");
});

Deno.test("Scribd page furniture and footer are removed", () => {
  const md = [
    "# Vigyan Bhairava Tantra",
    "97%(39)97% found this document useful (39 votes)",
    "",
    "15K views 221 pages",
    "",
    "AI-enhanced title",
    "",
    "Full description",
    "",
    "Download",
    "",
    "You are on page 1",
    "",
    "221",
    "",
    "The text itself.",
    "",
    "adDownload to read ad-free",
    "",
    "ad",
    "",
    "## You might also like",
    "",
    "Other document",
  ].join("\n");
  assertEquals(cleanArticleMarkdown(md, "Vigyan Bhairava Tantra").text, "The text itself.");
});

Deno.test("image alt text with brackets inside is removed whole", () => {
  assertEquals(
    cleanInline("Before ![Image 44: Energy is mukham [the mouth of Siva]. More](https://screenshots.scribd.com/a/44.jpeg) after"),
    "Before after",
  );
});

Deno.test("image alt text cut off inside a bracket is removed whole", () => {
  assertEquals(
    cleanInline("A ![Image 127: 102 Vijnana Bhairava [The explanation which follows was given by Swami Ji, here he takes up the variant re](https://screenshots.scribd.com/a/126.jpeg) B"),
    "A B",
  );
});

Deno.test("Scribd page snippets become paragraphs, marked where Scribd cut them", () => {
  const md = [
    "# Vigyan Bhairava Tantra",
    "",
    "![Image 10: FOREWORD The guru's grace is spontaneous ",
    "and unconditional.](https://screenshots.scribd.com/Scribd/252_100_85/395/441070610/9.jpeg)",
    "",
    "9",
    "",
    `![Image 11: ${"word ".repeat(26).trim()}](https://screenshots.scribd.com/Scribd/252_100_85/395/441070610/10.jpeg)`,
  ].join("\n");
  assertEquals(
    cleanArticleMarkdown(scribdPagesToText(md), "Vigyan Bhairava Tantra").text,
    `FOREWORD The guru's grace is spontaneous and unconditional.\n\n${"word ".repeat(26).trim()}…`,
  );
});
