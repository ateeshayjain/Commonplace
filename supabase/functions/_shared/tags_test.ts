import { assertEquals } from "jsr:@std/assert@1";
import { normalizeTagNames, slugify } from "./tags.ts";

Deno.test("slugify collapses spacing, case and ASCII punctuation", () => {
  assertEquals(slugify("Design Trends"), "designtrends");
  assertEquals(slugify("design-trends"), "designtrends");
  assertEquals(slugify("DesignTrends"), "designtrends");
  assertEquals(slugify("Fin_Tech #2026!"), "fintech2026");
});

Deno.test("slugify keeps non-Latin scripts intact", () => {
  // Devanagari virama and other combining marks must not be stripped
  assertEquals(slugify("संग्रह ज्ञान"), "संग्रहज्ञान");
});

Deno.test("normalizeTagNames dedupes by slug, keeps first spelling, caps at 6", () => {
  const names = ["AI", " ai ", "A.I.", "Fintech", "", "Design", "Health", "Science", "Culture", "Politics"];
  assertEquals(normalizeTagNames(names), ["AI", "Fintech", "Design", "Health", "Science", "Culture"]);
});
