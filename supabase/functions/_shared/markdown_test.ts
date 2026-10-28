import { assertEquals } from "jsr:@std/assert@1";
import { bodyToBlocks, cleanArticleMarkdown, cleanInline, looksLikeMarkdown } from "./markdown.ts";

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
});

Deno.test("plain bodies (X posts) are not treated as Markdown", () => {
  assertEquals(looksLikeMarkdown("Thread on #AI 🧵\n\n1/ the_point is simple"), false);
  assertEquals(looksLikeMarkdown("See [this](https://ex.com)"), true);
});

Deno.test("bodyToBlocks marks stored headings in plain text", () => {
  const blocks = bodyToBlocks("Intro\n\n1. A section\n\nBody text\n\n• one\n• two", "T", ["1. A section"]);
  assertEquals(blocks.map((b) => b.kind), ["paragraph", "heading", "paragraph", "list"]);
});
