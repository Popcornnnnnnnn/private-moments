import test from "node:test";
import assert from "node:assert/strict";

import {
  estimateTokensFromChars,
  extractProviderTokenUsage,
  recordCompletionUsage,
  type AIUsageEventInput,
} from "./usage.js";

test("extractProviderTokenUsage reads OpenAI chat usage fields", () => {
  const usage = extractProviderTokenUsage({
    usage: {
      prompt_tokens: 120,
      completion_tokens: 30,
      total_tokens: 150,
      prompt_tokens_details: {
        cached_tokens: 40,
      },
    },
  });

  assert.deepEqual(usage, {
    inputTokens: 120,
    outputTokens: 30,
    totalTokens: 150,
    cachedInputTokens: 40,
  });
});

test("recordCompletionUsage falls back to local estimates without provider usage", async () => {
  const events: AIUsageEventInput[] = [];
  await recordCompletionUsage(
    {
      feature: "weekly_review",
      subjectType: "review",
      subjectId: "review-1",
      promptVersion: "weekly-review-v1",
      recorder: (event) => events.push(event),
    },
    {
      provider: "test",
      model: "test-model",
      status: "success",
      inputChars: 300,
      outputChars: 90,
      durationMs: 50,
    },
  );

  assert.equal(events.length, 1);
  assert.equal(events[0]?.totalTokens, null);
  assert.equal(events[0]?.estimatedInputTokens, estimateTokensFromChars(300));
  assert.equal(events[0]?.estimatedOutputTokens, estimateTokensFromChars(90));
  assert.equal(events[0]?.estimatedTotalTokens, 130);
});
