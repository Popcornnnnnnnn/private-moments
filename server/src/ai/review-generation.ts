import { createHash } from "node:crypto";

import type { AISummaryConfig } from "../config/app-config.js";
import { AISummaryProviderError } from "./media-summary.js";
import { recordCompletionUsage, type AIUsageContext } from "./usage.js";

export const REVIEW_PROMPT_VERSION = "weekly-review-v2";
const REVIEW_PROVIDER_MAX_ATTEMPTS = 3;
const REVIEW_PROVIDER_RETRY_DELAYS_MS = [400, 1200];

export type ReviewKind = "weekly" | "monthly" | "custom";
export type ReviewRangeMode = "rolling_7_days" | "calendar_week" | "calendar_month" | "custom";
export type ReviewTrigger = "manual" | "scheduled" | "regenerate";

export interface ReviewInputPack {
  kind: ReviewKind;
  rangeMode: ReviewRangeMode;
  rangeStart: string;
  rangeEnd: string;
  generatedAt: string;
  totals: {
    moments: number;
    textMoments: number;
    imageMoments: number;
    audioMoments: number;
    videoMoments: number;
    comments: number;
    favorites: number;
  };
  rhythm: {
    byDay: Array<{ date: string; count: number }>;
    byHourBucket: Array<{ bucket: string; count: number }>;
  };
  moments: ReviewInputMoment[];
  reviewMemory: ReviewMemoryHint[];
}

export interface ReviewInputMoment {
  id: string;
  occurredAt: string;
  text: string;
  mediaKinds: string[];
  comments: string[];
  tags: string[];
  favorite: boolean;
  aiSummaries: ReviewInputAISummary[];
}

export interface ReviewInputAISummary {
  mediaId: string;
  kind: string;
  documentTitle: string | null;
  oneLiner: string | null;
  summaryText: string | null;
  documentBlocks: unknown[];
}

export interface ReviewMemoryHint {
  key: string;
  value: unknown;
}

export interface ReviewOutput {
  title: string;
  oneLiner: string;
  keywords: Array<{ label: string; note: string }>;
  themes: Array<{ title: string; body: string }>;
  emotionalReflection: {
    tone: "calm_observation" | "gentle_encouragement" | "mixed";
    body: string;
  };
  progressAndOpenLoops: {
    progress: string[];
    openLoops: string[];
  };
  rhythm: {
    body: string;
    observations: string[];
  };
  notableMoments: Array<{
    title: string;
    note: string;
    momentIds: string[];
  }>;
  gentleSuggestions: string[];
  uncertainty: string[];
}

export function reviewInputDigest(input: ReviewInputPack): string {
  return createHash("sha256").update(JSON.stringify(input), "utf8").digest("hex");
}

export async function generateReview(
  config: AISummaryConfig,
  input: ReviewInputPack,
  usageContext?: AIUsageContext,
): Promise<ReviewOutput> {
  if (!config.apiKey) {
    throw new AISummaryProviderError("not_configured", "AI review provider is not configured");
  }

  let lastError: unknown;
  for (let attempt = 1; attempt <= REVIEW_PROVIDER_MAX_ATTEMPTS; attempt += 1) {
    try {
      const response = await callReviewCompletions(config, input, usageContext);
      return validateReviewOutput(response, input);
    } catch (error) {
      lastError = error;
      if (attempt >= REVIEW_PROVIDER_MAX_ATTEMPTS || !isRetryableReviewProviderError(error)) {
        break;
      }

      await delay(REVIEW_PROVIDER_RETRY_DELAYS_MS[attempt - 1] ?? 1200);
    }
  }

  if (shouldUseLocalFallback(lastError)) {
    return createLocalFallbackReview(input, lastError);
  }

  throw lastError;
}

async function callReviewCompletions(
  config: AISummaryConfig,
  input: ReviewInputPack,
  usageContext?: AIUsageContext,
): Promise<unknown> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), config.timeoutMs);
  const systemContent = reviewSystemPrompt();
  const userContent = JSON.stringify(input);
  const inputChars = systemContent.length + userContent.length + JSON.stringify(reviewJsonSchema()).length;
  const startedAt = Date.now();

  try {
    const response = await fetch(`${config.baseUrl}/chat/completions`, {
      method: "POST",
      signal: controller.signal,
      headers: {
        Authorization: `Bearer ${config.apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: config.model,
        temperature: 0.35,
        store: false,
        messages: [
          {
            role: "system",
            content: systemContent,
          },
          {
            role: "user",
            content: userContent,
          },
        ],
        response_format: {
          type: "json_schema",
          json_schema: {
            name: "periodic_review",
            strict: true,
            schema: reviewJsonSchema(),
          },
        },
      }),
    });

    if (!response.ok) {
      await recordCompletionUsage(usageContext, {
        provider: config.provider,
        model: config.model,
        status: "failed",
        inputChars,
        durationMs: Date.now() - startedAt,
        errorCode: `provider_http_${response.status}`,
      });
      throw new AISummaryProviderError(
        `provider_http_${response.status}`,
        `AI provider returned HTTP ${response.status}`,
      );
    }

    const parsed = (await response.json()) as unknown;
    const content = extractMessageContent(parsed);
    if (!content) {
      await recordCompletionUsage(usageContext, {
        provider: config.provider,
        model: config.model,
        status: "failed",
        inputChars,
        response: parsed,
        durationMs: Date.now() - startedAt,
        errorCode: "empty_response",
      });
      throw new AISummaryProviderError("empty_response", "AI provider returned no review");
    }

    try {
      const parsedContent = parseJsonContent(content);
      await recordCompletionUsage(usageContext, {
        provider: config.provider,
        model: config.model,
        status: "success",
        inputChars,
        outputChars: content.length,
        response: parsed,
        durationMs: Date.now() - startedAt,
      });
      return parsedContent;
    } catch {
      await recordCompletionUsage(usageContext, {
        provider: config.provider,
        model: config.model,
        status: "failed",
        inputChars,
        outputChars: content.length,
        response: parsed,
        durationMs: Date.now() - startedAt,
        errorCode: "invalid_json",
      });
      throw new AISummaryProviderError("invalid_json", "AI provider returned invalid JSON");
    }
  } catch (error) {
    if (error instanceof AISummaryProviderError) {
      throw error;
    }

    if (error instanceof Error && error.name === "AbortError") {
      await recordCompletionUsage(usageContext, {
        provider: config.provider,
        model: config.model,
        status: "failed",
        inputChars,
        durationMs: Date.now() - startedAt,
        errorCode: "provider_timeout",
      });
      throw new AISummaryProviderError("provider_timeout", "AI provider request timed out");
    }

    await recordCompletionUsage(usageContext, {
      provider: config.provider,
      model: config.model,
      status: "failed",
      inputChars,
      durationMs: Date.now() - startedAt,
      errorCode: "provider_request_failed",
    });
    throw new AISummaryProviderError("provider_request_failed", "AI provider request failed");
  } finally {
    clearTimeout(timeout);
  }
}

function reviewSystemPrompt(): string {
  return [
    "You write Private Moments periodic reviews.",
    "The product is a no-audience private personal timeline. Treat the input as an aggregate life stream, not evidence for judging individual entries.",
    "The review should be retrospective first, with calm observation and moderate encouragement. It may comfort or affirm the user when the week shows effort or difficulty.",
    "Do not diagnose mental health, do not moralize, do not convert life into KPI/todos, and do not cite moment IDs except inside notableMoments.",
    "Use the same dominant language as the input unless the range is mixed; Chinese is acceptable when the input is Chinese-heavy.",
    "Prefer useful themes, keywords, rhythm, state response, progress, open loops, and quiet suggestions.",
    "Avoid generic template language. Use concrete signals from the provided text, tags, media kinds, comments, favorites, and rhythm counts without inventing facts.",
    "Do not claim completion, productivity, mood, health, or intent unless the input directly supports it.",
    "For non-empty input, write substantive content across the sections. Empty arrays or empty section bodies are only acceptable when the input range is truly empty.",
    "If notableMoments are included, put moment IDs only there. Other sections should summarize the whole range without binding claims to individual evidence.",
    "Return only one valid JSON object. Do not wrap it in Markdown, code fences, or explanatory text.",
  ].join("\n");
}

function reviewJsonSchema(): Record<string, unknown> {
  return {
    type: "object",
    additionalProperties: false,
    required: [
      "title",
      "oneLiner",
      "keywords",
      "themes",
      "emotionalReflection",
      "progressAndOpenLoops",
      "rhythm",
      "notableMoments",
      "gentleSuggestions",
      "uncertainty",
    ],
    properties: {
      title: { type: "string", minLength: 1 },
      oneLiner: { type: "string", minLength: 1 },
      keywords: {
        type: "array",
        minItems: 1,
        maxItems: 10,
        items: {
          type: "object",
          additionalProperties: false,
          required: ["label", "note"],
          properties: {
            label: { type: "string" },
            note: { type: "string" },
          },
        },
      },
      themes: {
        type: "array",
        minItems: 1,
        maxItems: 5,
        items: {
          type: "object",
          additionalProperties: false,
          required: ["title", "body"],
          properties: {
            title: { type: "string" },
            body: { type: "string" },
          },
        },
      },
      emotionalReflection: {
        type: "object",
        additionalProperties: false,
        required: ["tone", "body"],
        properties: {
          tone: { type: "string", enum: ["calm_observation", "gentle_encouragement", "mixed"] },
          body: { type: "string", minLength: 1 },
        },
      },
      progressAndOpenLoops: {
        type: "object",
        additionalProperties: false,
        required: ["progress", "openLoops"],
        properties: {
          progress: { type: "array", maxItems: 8, items: { type: "string" } },
          openLoops: { type: "array", maxItems: 8, items: { type: "string" } },
        },
      },
      rhythm: {
        type: "object",
        additionalProperties: false,
        required: ["body", "observations"],
        properties: {
          body: { type: "string", minLength: 1 },
          observations: { type: "array", maxItems: 6, items: { type: "string" } },
        },
      },
      notableMoments: {
        type: "array",
        maxItems: 8,
        items: {
          type: "object",
          additionalProperties: false,
          required: ["title", "note", "momentIds"],
          properties: {
            title: { type: "string" },
            note: { type: "string" },
            momentIds: { type: "array", maxItems: 4, items: { type: "string" } },
          },
        },
      },
      gentleSuggestions: { type: "array", minItems: 1, maxItems: 5, items: { type: "string" } },
      uncertainty: { type: "array", maxItems: 5, items: { type: "string" } },
    },
  };
}

export function validateReviewOutput(value: unknown, input?: ReviewInputPack): ReviewOutput {
  if (!isRecord(value)) {
    throw new AISummaryProviderError("invalid_response", "AI review response was invalid");
  }

  const validMomentIds = new Set(input?.moments.map((moment) => moment.id) ?? []);
  const output = {
    title: getString(value.title, "Untitled review").slice(0, 80),
    oneLiner: getString(value.oneLiner, ""),
    keywords: getObjectArray(value.keywords)
      .map((item) => ({
        label: getString(item.label, "").slice(0, 40),
        note: getString(item.note, ""),
      }))
      .filter((item) => item.label && item.note)
      .slice(0, 10),
    themes: getObjectArray(value.themes)
      .map((item) => ({
        title: getString(item.title, "").slice(0, 80),
        body: getString(item.body, ""),
      }))
      .filter((item) => item.title && item.body)
      .slice(0, 5),
    emotionalReflection: normalizeEmotionalReflection(value.emotionalReflection),
    progressAndOpenLoops: normalizeProgress(value.progressAndOpenLoops),
    rhythm: normalizeRhythm(value.rhythm),
    notableMoments: getObjectArray(value.notableMoments)
      .map((item) => ({
        title: getString(item.title, "").slice(0, 80),
        note: getString(item.note, ""),
        momentIds: getStringArray(item.momentIds)
          .filter((momentId) => validMomentIds.size === 0 || validMomentIds.has(momentId))
          .slice(0, 4),
      }))
      .filter((item) => item.title && item.note && (validMomentIds.size === 0 || item.momentIds.length > 0))
      .slice(0, 8),
    gentleSuggestions: getStringArray(value.gentleSuggestions).slice(0, 5),
    uncertainty: getStringArray(value.uncertainty).slice(0, 5),
  };

  if (input) {
    assertSubstantiveReviewOutput(output, input);
  }

  return output;
}

function assertSubstantiveReviewOutput(output: ReviewOutput, input: ReviewInputPack): void {
  if (input.totals.moments === 0) {
    return;
  }

  const substantiveSections = [
    output.oneLiner.length >= 12,
    output.keywords.length >= 1,
    output.themes.length >= 1,
    output.emotionalReflection.body.length >= 30,
    output.progressAndOpenLoops.progress.length + output.progressAndOpenLoops.openLoops.length >= 1,
    output.rhythm.body.length >= 20 || output.rhythm.observations.length >= 1,
    output.notableMoments.length >= 1,
    output.gentleSuggestions.length >= 1,
  ].filter(Boolean).length;

  if (substantiveSections < 5) {
    throw new AISummaryProviderError(
      "empty_review_content",
      "AI provider returned a review with too little usable content",
    );
  }
}

export function createLocalFallbackReview(input: ReviewInputPack, cause: unknown): ReviewOutput {
  const language = dominantInputLanguage(input);
  const zh = language === "zh";
  const totals = input.totals;
  const topTags = topValues(input.moments.flatMap((moment) => moment.tags), 5);
  const mediaKeywords = mediaKeywordLabels(input, zh);
  const notableMoments = fallbackNotableMoments(input, zh);
  const rhythmDescription = fallbackRhythm(input, zh);
  const progressItems = fallbackProgressItems(input, zh);
  const openLoopItems = fallbackOpenLoopItems(input, zh);
  const keywordLabels = [...topTags, ...mediaKeywords, zh ? "记录节奏" : "Capture rhythm"];

  if (totals.moments === 0) {
    return {
      title: zh ? "最近 7 天暂无可回看的记录" : "No Moments To Review",
      oneLiner: zh ? "这个时间段里还没有可用于总结的 moments。" : "There were no moments in this range to summarize.",
      keywords: [],
      themes: [],
      emotionalReflection: {
        tone: "calm_observation",
        body: zh ? "这一段时间没有留下可分析的记录，因此这里先保持空白，不做额外推断。" : "There is no recorded material in this range, so this review stays intentionally light.",
      },
      progressAndOpenLoops: { progress: [], openLoops: [] },
      rhythm: { body: zh ? "没有记录节奏可供观察。" : "No capture rhythm is available yet.", observations: [] },
      notableMoments: [],
      gentleSuggestions: [zh ? "如果这段时间确实发生了值得保留的事，可以补一两条 moment。" : "Add one or two moments if anything from this period still feels worth keeping."],
      uncertainty: [fallbackUncertainty(cause, zh)],
    };
  }

  return {
    title: zh ? "最近 7 天回顾" : "Last 7 Days Review",
    oneLiner: zh
      ? `这段时间一共留下 ${totals.moments} 条 moments，主要价值是把零散记录先稳定地收拢起来。`
      : `This range captured ${totals.moments} moments, giving you a stable aggregate view even without the AI provider.`,
    keywords: keywordLabels.slice(0, 8).map((label) => ({
      label,
      note: fallbackKeywordNote(totals, zh),
    })),
    themes: fallbackThemes(input, zh),
    emotionalReflection: {
      tone: "mixed",
      body: zh
        ? "从记录密度看，这一周并不是空白的。即使内容比较零散，它仍然说明你在持续捕捉想法、问题、测试和生活片段；这种持续记录本身就是一种很实际的推进。"
        : "The capture density shows this was not an empty week. Even if the material is scattered, it still reflects steady attention to ideas, issues, tests, and daily details.",
    },
    progressAndOpenLoops: {
      progress: progressItems,
      openLoops: openLoopItems,
    },
    rhythm: rhythmDescription,
    notableMoments,
    gentleSuggestions: [
      zh ? "先把最想继续推进的一两个开放问题挑出来，不需要把这一周所有线索都变成任务。" : "Pick one or two open threads to continue; this review does not need to turn every signal into a task.",
      zh ? "如果某些记录只是测试或临时片段，可以保留，但不用让它们主导你对这一周的判断。" : "Keep test or temporary moments if useful, but do not let them dominate how you read the week.",
    ],
    uncertainty: [fallbackUncertainty(cause, zh)],
  };
}

function fallbackThemes(input: ReviewInputPack, zh: boolean): ReviewOutput["themes"] {
  const totals = input.totals;
  const topTags = topValues(input.moments.flatMap((moment) => moment.tags), 3);
  const themes: ReviewOutput["themes"] = [
    {
      title: zh ? "零散记录被重新收拢" : "Scattered Capture Reassembled",
      body: zh
        ? `这段时间有 ${totals.moments} 条 moments、${totals.comments} 条 comments。单条记录可能很碎，但放在一起能看出你在持续把想法和现场情况留存下来。`
        : `The range includes ${totals.moments} moments and ${totals.comments} comments. Individual entries may be small, but together they preserve the shape of the period.`,
    },
  ];

  if (topTags.length > 0) {
    themes.push({
      title: zh ? "标签线索比较集中" : "Tag Signals",
      body: zh
        ? `比较明显的标签线索包括 ${topTags.join("、")}。这可以作为之后重新生成 AI review 时优先观察的主题入口。`
        : `The clearest tag signals are ${topTags.join(", ")}. They are useful anchors for a later AI-generated review.`,
    });
  }

  themes.push({
    title: zh ? "文本与媒体一起构成上下文" : "Text And Media Context",
    body: zh
      ? `这里包含 ${totals.textMoments} 条文本、${totals.audioMoments} 条音频、${totals.imageMoments} 条图片和 ${totals.videoMoments} 条视频相关 moments。回看时不适合只盯住某一条，而更适合看整体分布。`
      : `This includes ${totals.textMoments} text, ${totals.audioMoments} audio, ${totals.imageMoments} image, and ${totals.videoMoments} video moments. It is better read as a distribution than as one decisive entry.`,
  });

  return themes.slice(0, 5);
}

function fallbackNotableMoments(input: ReviewInputPack, zh: boolean): ReviewOutput["notableMoments"] {
  const candidates = [...input.moments]
    .filter((moment) => moment.favorite || moment.text.trim() || moment.aiSummaries.length > 0)
    .sort((left, right) => {
      if (left.favorite !== right.favorite) {
        return left.favorite ? -1 : 1;
      }
      return right.occurredAt.localeCompare(left.occurredAt);
    })
    .slice(0, 4);

  return candidates.map((moment) => {
    const title = firstMeaningfulLine(moment) || (zh ? "值得回看的 moment" : "Moment Worth Revisiting");
    return {
      title: clampText(title, 80),
      note: zh
        ? "这条记录在本地兜底回顾中被保留下来，适合作为之后重新阅读的入口。"
        : "This entry is kept as a lightweight revisit anchor in the local fallback review.",
      momentIds: [moment.id],
    };
  });
}

function fallbackProgressItems(input: ReviewInputPack, zh: boolean): string[] {
  const matches = input.moments
    .map(firstMeaningfulLine)
    .filter((line) => /完成|实现|修复|验证|测试|发布|上线|build|fixed|done|implemented|verified|test/i.test(line))
    .slice(-4)
    .map((line) => clampText(line, 120));

  if (matches.length > 0) {
    return matches;
  }

  return [
    zh
      ? `持续记录了 ${input.totals.moments} 条 moments，让这一周的上下文没有完全散掉。`
      : `Captured ${input.totals.moments} moments, keeping the week from disappearing into fragments.`,
  ];
}

function fallbackOpenLoopItems(input: ReviewInputPack, zh: boolean): string[] {
  const matches = input.moments
    .map(firstMeaningfulLine)
    .filter((line) => /问题|报错|需要|待|下一步|为什么|怎么|bug|error|todo|pending|next|fix/i.test(line))
    .slice(-5)
    .map((line) => clampText(line, 120));

  if (matches.length > 0) {
    return matches;
  }

  return [
    zh
      ? "本地兜底无法可靠判断真正的开放循环，建议等 provider 恢复后重新生成一次。"
      : "The local fallback cannot reliably identify every open loop; regenerate once the provider is stable.",
  ];
}

function fallbackRhythm(input: ReviewInputPack, zh: boolean): ReviewOutput["rhythm"] {
  const activeDays = input.rhythm.byDay.filter((day) => day.count > 0);
  const busiestDay = [...activeDays].sort((left, right) => right.count - left.count)[0];
  const busiestBucket = [...input.rhythm.byHourBucket].sort((left, right) => right.count - left.count)[0];
  const bucketLabel = busiestBucket ? localizedBucket(busiestBucket.bucket, zh) : null;

  return {
    body: zh
      ? `这段时间有 ${activeDays.length} 天留下记录${busiestDay ? `，其中 ${busiestDay.date} 最密集` : ""}${bucketLabel ? `，较多出现在${bucketLabel}` : ""}。`
      : `This range has captures on ${activeDays.length} days${busiestDay ? `, with ${busiestDay.date} being the densest` : ""}${bucketLabel ? ` and more activity around ${bucketLabel}` : ""}.`,
    observations: [
      zh
        ? "记录节奏本身比单条内容更适合作为这一版兜底回顾的主要依据。"
        : "Capture rhythm is a safer signal for this fallback than over-reading any single moment.",
    ],
  };
}

function mediaKeywordLabels(input: ReviewInputPack, zh: boolean): string[] {
  const labels: string[] = [];
  if (input.totals.audioMoments > 0) {
    labels.push(zh ? "音频记录" : "Audio");
  }
  if (input.totals.imageMoments > 0) {
    labels.push(zh ? "图片记录" : "Images");
  }
  if (input.totals.videoMoments > 0) {
    labels.push(zh ? "视频记录" : "Video");
  }
  return labels;
}

function fallbackKeywordNote(totals: ReviewInputPack["totals"], zh: boolean): string {
  return zh
    ? `来自 ${totals.moments} 条 moments 的本地聚合线索。`
    : `A local aggregate signal from ${totals.moments} moments.`;
}

function fallbackUncertainty(cause: unknown, zh: boolean): string {
  const code = cause instanceof AISummaryProviderError ? cause.code : "provider_unavailable";
  return zh
    ? `AI provider 生成失败（${code}），这篇是 server 根据本地 moments 输入包生成的保守兜底版本；细节深度会低于正常 AI review。`
    : `The AI provider failed (${code}), so this is a conservative local fallback generated from the review input pack. It is less detailed than a normal AI review.`;
}

function firstMeaningfulLine(moment: ReviewInputMoment): string {
  const textLine = moment.text
    .split("\n")
    .map((line) => line.replace(/^#{1,6}\s*/, "").trim())
    .find(Boolean);
  if (textLine) {
    return textLine;
  }

  for (const summary of moment.aiSummaries) {
    const line = summary.documentTitle || summary.oneLiner || summary.summaryText;
    if (line?.trim()) {
      return line.trim();
    }
  }

  return "";
}

function clampText(value: string, maxLength: number): string {
  const trimmed = value.trim();
  return trimmed.length > maxLength ? `${trimmed.slice(0, maxLength)}...` : trimmed;
}

function topValues(values: string[], limit: number): string[] {
  const counts = new Map<string, number>();
  for (const value of values) {
    const normalized = value.trim();
    if (normalized) {
      counts.set(normalized, (counts.get(normalized) ?? 0) + 1);
    }
  }

  return [...counts.entries()]
    .sort((left, right) => right[1] - left[1] || left[0].localeCompare(right[0]))
    .slice(0, limit)
    .map(([value]) => value);
}

function dominantInputLanguage(input: ReviewInputPack): "zh" | "en" {
  const text = input.moments
    .flatMap((moment) => [
      moment.text,
      ...moment.comments,
      ...moment.aiSummaries.flatMap((summary) => [
        summary.documentTitle ?? "",
        summary.oneLiner ?? "",
        summary.summaryText ?? "",
      ]),
    ])
    .join("\n");
  const cjk = [...text].filter((character) => /[\u3400-\u9fff]/u.test(character)).length;
  const latin = [...text].filter((character) => /[a-z]/iu.test(character)).length;
  return cjk >= 8 || cjk >= latin ? "zh" : "en";
}

function localizedBucket(bucket: string, zh: boolean): string {
  const labels: Record<string, { zh: string; en: string }> = {
    morning: { zh: "上午", en: "morning" },
    afternoon: { zh: "下午", en: "afternoon" },
    evening: { zh: "晚上", en: "evening" },
    late_night: { zh: "深夜", en: "late night" },
  };
  const label = labels[bucket];
  return label ? (zh ? label.zh : label.en) : bucket;
}

function isRetryableReviewProviderError(error: unknown): boolean {
  if (!(error instanceof AISummaryProviderError)) {
    return false;
  }

  if (["provider_timeout", "provider_request_failed", "invalid_json", "empty_response", "empty_review_content"].includes(error.code)) {
    return true;
  }

  const match = error.code.match(/^provider_http_(\d+)$/);
  if (!match) {
    return false;
  }

  const status = Number(match[1]);
  return status === 429 || status >= 500;
}

function shouldUseLocalFallback(error: unknown): boolean {
  return isRetryableReviewProviderError(error);
}

function delay(milliseconds: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

function normalizeEmotionalReflection(value: unknown): ReviewOutput["emotionalReflection"] {
  if (!isRecord(value)) {
    return { tone: "mixed", body: "" };
  }

  const tone = value.tone === "calm_observation" || value.tone === "gentle_encouragement"
    ? value.tone
    : "mixed";
  return {
    tone,
    body: getString(value.body, ""),
  };
}

function normalizeProgress(value: unknown): ReviewOutput["progressAndOpenLoops"] {
  if (!isRecord(value)) {
    return { progress: [], openLoops: [] };
  }

  return {
    progress: getStringArray(value.progress).slice(0, 8),
    openLoops: getStringArray(value.openLoops).slice(0, 8),
  };
}

function normalizeRhythm(value: unknown): ReviewOutput["rhythm"] {
  if (!isRecord(value)) {
    return { body: "", observations: [] };
  }

  return {
    body: getString(value.body, ""),
    observations: getStringArray(value.observations).slice(0, 6),
  };
}

function extractMessageContent(value: unknown): string | null {
  if (!isRecord(value) || !Array.isArray(value.choices)) {
    return null;
  }

  const firstChoice = value.choices[0] as unknown;
  if (!isRecord(firstChoice) || !isRecord(firstChoice.message)) {
    return null;
  }

  const content = firstChoice.message.content;
  if (typeof content === "string") {
    return content;
  }

  if (Array.isArray(content)) {
    const text = content
      .map((part) => (isRecord(part) && typeof part.text === "string" ? part.text : ""))
      .join("")
      .trim();
    return text.length > 0 ? text : null;
  }

  return null;
}

function parseJsonContent(content: string): unknown {
  const trimmed = content.trim();
  try {
    return JSON.parse(trimmed) as unknown;
  } catch {
    const fenced = trimmed.match(/^```(?:json)?\s*([\s\S]*?)\s*```$/i);
    if (fenced) {
      return JSON.parse(fenced[1].trim()) as unknown;
    }

    const start = trimmed.indexOf("{");
    const end = trimmed.lastIndexOf("}");
    if (start >= 0 && end > start) {
      return JSON.parse(trimmed.slice(start, end + 1)) as unknown;
    }

    throw new Error("No JSON object found");
  }
}

function getString(value: unknown, fallback: string): string {
  return typeof value === "string" ? value.trim() : fallback;
}

function getStringArray(value: unknown): string[] {
  return Array.isArray(value)
    ? value.filter((item): item is string => typeof item === "string").map((item) => item.trim()).filter(Boolean)
    : [];
}

function getObjectArray(value: unknown): Record<string, unknown>[] {
  return Array.isArray(value) ? value.filter(isRecord) : [];
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
