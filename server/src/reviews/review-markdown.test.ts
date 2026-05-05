import test from "node:test";
import assert from "node:assert/strict";

import type { Review } from "@prisma/client";

import type { ReviewOutput } from "../ai/review-generation.js";
import { reviewToMarkdown } from "./review-markdown.js";

test("reviewToMarkdown stays within the app-supported H1/H2 subset", () => {
  const content: ReviewOutput = {
    title: "Weekly Review",
    oneLiner: "A quiet week.",
    keywords: [{ label: "Study", note: "Several focused sessions." }],
    themes: [{ title: "Momentum", body: "Small steps kept accumulating." }],
    emotionalReflection: { tone: "calm_observation", body: "Mostly steady." },
    progressAndOpenLoops: { progress: ["Finished a draft."], openLoops: ["Follow up tomorrow."] },
    rhythm: { body: "", observations: [] },
    notableMoments: [],
    gentleSuggestions: [],
    uncertainty: [],
  };
  const review = {
    rangeStart: new Date("2026-05-01T00:00:00.000Z"),
    rangeEnd: new Date("2026-05-08T00:00:00.000Z"),
  } as Review;

  const markdown = reviewToMarkdown(content, review);

  assert.match(markdown, /^# Weekly Review/m);
  assert.match(markdown, /^## Themes/m);
  assert.doesNotMatch(markdown, /^### /m);
  assert.match(markdown, /^- Momentum: Small steps kept accumulating\./m);
});
