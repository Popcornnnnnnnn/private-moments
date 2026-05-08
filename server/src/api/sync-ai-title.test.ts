import assert from "node:assert/strict";
import test from "node:test";

import {
  cleanedAITitle,
  hasLeadingMarkdownTitle,
  insertAITitleIntoText,
  markdownHeadingText,
} from "./sync-ai-title.js";

test("cleanedAITitle strips markdown markers, collapses whitespace, and enforces length", () => {
  assert.equal(cleanedAITitle("##  Study notes\nfor today  "), "Study notes for today");
  assert.equal(cleanedAITitle(""), null);
  assert.equal(cleanedAITitle("x".repeat(41)), null);
});

test("hasLeadingMarkdownTitle only treats the first non-empty line as the title boundary", () => {
  assert.equal(hasLeadingMarkdownTitle("\n\n## Existing title\nbody"), true);
  assert.equal(hasLeadingMarkdownTitle("\nplain text\n## later heading"), false);
  assert.equal(markdownHeadingText("# Title"), "Title");
  assert.equal(markdownHeadingText("### Not supported"), null);
});

test("insertAITitleIntoText inserts only an H2 heading and preserves body text", () => {
  assert.equal(insertAITitleIntoText("Audio note", ""), "## Audio note");
  assert.equal(insertAITitleIntoText("Audio note", "body"), "## Audio note\n\nbody");
});
