import { assertEquals } from "jsr:@std/assert@1";
import { screenshotPaths, SCREENSHOT_MAX_COUNT } from "./screenshots.ts";

const user = "3f2b6a1c-1d2e-4f50-9a8b-7c6d5e4f3a2b";
const batch = "a1b2c3d4-e5f6-4789-8abc-def012345678";
const path = (n: number, u = user, b = batch) => `${u}/${b}/${n}.jpg`;

Deno.test("keeps the user's own paths in the order given", () => {
  assertEquals(screenshotPaths([path(2), path(1), path(3)], user), [path(2), path(1), path(3)]);
});

Deno.test("rejects another user's folder", () => {
  const other = "00000000-0000-4000-8000-000000000000";
  assertEquals(screenshotPaths([path(1), path(2, other)], user), null);
});

Deno.test("rejects traversal, other shapes and mixed batches", () => {
  assertEquals(screenshotPaths([`${user}/../x/${batch}/1.jpg`], user), null);
  assertEquals(screenshotPaths([`${user}/${batch}/1.png`], user), null);
  assertEquals(screenshotPaths([`${user}/${batch}/sub/1.jpg`], user), null);
  assertEquals(screenshotPaths([path(1), path(2, user, "b1b2c3d4-e5f6-4789-8abc-def012345678")], user), null);
});

Deno.test("rejects empty, repeated, non-string and too many", () => {
  assertEquals(screenshotPaths([], user), null);
  assertEquals(screenshotPaths("x", user), null);
  assertEquals(screenshotPaths([path(1), path(1)], user), null);
  assertEquals(screenshotPaths([path(1), 7], user), null);
  assertEquals(screenshotPaths(Array.from({ length: SCREENSHOT_MAX_COUNT + 1 }, (_, i) => path(i)), user), null);
});
