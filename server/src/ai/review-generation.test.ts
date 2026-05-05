import test from "node:test";
import assert from "node:assert/strict";

import { AISummaryProviderError } from "./media-summary.js";
import {
  createLocalFallbackReview,
  generateReview,
  validateReviewOutput,
  type ReviewInputPack,
} from "./review-generation.js";

const inputPack: ReviewInputPack = {
  kind: "weekly",
  rangeMode: "rolling_7_days",
  rangeStart: "2026-05-01T00:00:00.000Z",
  rangeEnd: "2026-05-08T00:00:00.000Z",
  generatedAt: "2026-05-08T00:00:00.000Z",
  totals: {
    moments: 12,
    textMoments: 8,
    imageMoments: 2,
    audioMoments: 2,
    videoMoments: 0,
    comments: 3,
    favorites: 1,
  },
  rhythm: {
    byDay: [{ date: "2026-05-07", count: 3 }],
    byHourBucket: [{ bucket: "evening", count: 5 }],
  },
  moments: [],
  reviewMemory: [],
};

const inputPackWithMoments: ReviewInputPack = {
  ...inputPack,
  moments: [
    {
      id: "moment-1",
      occurredAt: "2026-05-07T12:00:00.000Z",
      text: "# 测试 Weekly Review\n修复 regenerate 后的状态问题",
      mediaKinds: ["audio"],
      comments: ["需要继续确认真机表现"],
      tags: ["产品", "开发"],
      favorite: true,
      aiSummaries: [],
    },
    {
      id: "moment-2",
      occurredAt: "2026-05-07T20:00:00.000Z",
      text: "为什么 provider 会返回 502",
      mediaKinds: [],
      comments: [],
      tags: ["开发"],
      favorite: false,
      aiSummaries: [],
    },
  ],
};

test("validateReviewOutput rejects sparse ready-looking output for non-empty ranges", () => {
  assert.throws(
    () => validateReviewOutput({
      title: "这一周：产品在长出来，生活也在不断试运行",
      oneLiner: "",
      keywords: [],
      themes: [],
      emotionalReflection: { tone: "mixed", body: "" },
      progressAndOpenLoops: { progress: [], openLoops: [] },
      rhythm: { body: "", observations: [] },
      notableMoments: [],
      gentleSuggestions: [],
      uncertainty: [],
    }, inputPack),
    (error) => error instanceof AISummaryProviderError && error.code === "empty_review_content",
  );
});

test("validateReviewOutput accepts substantive output for non-empty ranges", () => {
  const output = validateReviewOutput({
    title: "Weekly Review",
    oneLiner: "A focused week with several concrete product steps.",
    keywords: [{ label: "Product", note: "Several notes were about shaping and testing product behavior." }],
    themes: [{ title: "Iteration", body: "The week showed repeated small corrections around actual usage." }],
    emotionalReflection: {
      tone: "gentle_encouragement",
      body: "There is a steady effort here, with enough visible progress to deserve some credit.",
    },
    progressAndOpenLoops: { progress: ["Improved the review flow."], openLoops: [] },
    rhythm: { body: "Most captured moments clustered around implementation and verification.", observations: [] },
    notableMoments: [{ title: "Review flow", note: "Worth revisiting as a product decision.", momentIds: ["moment-1"] }],
    gentleSuggestions: ["Keep the next pass focused on the parts that felt confusing in real use."],
    uncertainty: [],
  }, inputPack);

  assert.equal(output.title, "Weekly Review");
  assert.equal(output.keywords.length, 1);
});

test("createLocalFallbackReview returns substantive content for non-empty ranges", () => {
  const output = createLocalFallbackReview(
    inputPackWithMoments,
    new AISummaryProviderError("provider_http_502", "AI provider returned HTTP 502"),
  );

  assert.equal(output.title, "最近 7 天回顾");
  assert.ok(output.keywords.length > 0);
  assert.ok(output.themes.length > 0);
  assert.ok(output.emotionalReflection.body.length > 30);
  assert.ok(output.uncertainty.some((item) => item.includes("provider_http_502")));
});

test("generateReview falls back after retryable provider HTTP failures", async (t) => {
  const originalFetch = globalThis.fetch;
  let calls = 0;
  globalThis.fetch = async () => {
    calls += 1;
    return new Response("bad gateway", { status: 502 });
  };
  t.after(() => {
    globalThis.fetch = originalFetch;
  });

  const output = await generateReview({
    provider: "test",
    baseUrl: "https://provider.invalid/v1",
    apiKey: "test-key",
    model: "test-model",
    transcriptionProvider: "local",
    transcriptionModel: "test-transcribe",
    localTranscriptionPythonPath: "python",
    localTranscriptionScriptPath: "script.py",
    localTranscriptionModel: "local-model",
    localTranscriptionTimeoutMs: 1000,
    timeoutMs: 1000,
  }, inputPackWithMoments);

  assert.equal(calls, 3);
  assert.equal(output.title, "最近 7 天回顾");
  assert.ok(output.uncertainty.some((item) => item.includes("provider_http_502")));
});
