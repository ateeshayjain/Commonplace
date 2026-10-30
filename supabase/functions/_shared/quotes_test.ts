import { assertEquals } from "jsr:@std/assert@1";
import { verbatimQuotes } from "./quotes.ts";

const content = "Hello,\n\nAs I watched a child die on the table, a sentence arrived in my head unbidden.\n\nSome suffering cannot be redeemed — only witnessed.";

Deno.test("keeps lines found word for word, despite case, spacing and quote styles", () => {
  assertEquals(
    verbatimQuotes(["“As I watched a child die on the table,  a sentence arrived in my head unbidden.”", "some suffering cannot be redeemed - only witnessed."], content),
    ["As I watched a child die on the table,  a sentence arrived in my head unbidden.", "some suffering cannot be redeemed - only witnessed."],
  );
});

Deno.test("drops paraphrases, duplicates and fragments", () => {
  assertEquals(
    verbatimQuotes([
      "Not all suffering makes you stronger.",
      "Some suffering cannot be redeemed — only witnessed.",
      "SOME SUFFERING CANNOT BE REDEEMED — ONLY WITNESSED.",
      "Hello,",
    ], content),
    ["Some suffering cannot be redeemed — only witnessed."],
  );
});
