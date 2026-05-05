import { createHash } from "node:crypto";

import type { AISummaryConfig } from "../config/app-config.js";
import { AISummaryProviderError } from "./media-summary.js";

export const REVIEW_PROMPT_VERSION = "weekly-review-v1";

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
): Promise<ReviewOutput> {
  if (!config.apiKey) {
    throw new AISummaryProviderError("not_configured", "AI review provider is not configured");
  }

  const response = await callReviewCompletions(config, input);
  return validateReviewOutput(response);
}

async function callReviewCompletions(
  config: AISummaryConfig,
  input: ReviewInputPack,
): Promise<unknown> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), config.timeoutMs);

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
            content: reviewSystemPrompt(),
          },
          {
            role: "user",
            content: JSON.stringify(input),
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
      throw new AISummaryProviderError(
        `provider_http_${response.status}`,
        `AI provider returned HTTP ${response.status}`,
      );
    }

    const parsed = (await response.json()) as unknown;
    const content = extractMessageContent(parsed);
    if (!content) {
      throw new AISummaryProviderError("empty_response", "AI provider returned no review");
    }

    try {
      return parseJsonContent(content);
    } catch {
      throw new AISummaryProviderError("invalid_json", "AI provider returned invalid JSON");
    }
  } catch (error) {
    if (error instanceof AISummaryProviderError) {
      throw error;
    }

    if (error instanceof Error && error.name === "AbortError") {
      throw new AISummaryProviderError("provider_timeout", "AI provider request timed out");
    }

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
      title: { type: "string" },
      oneLiner: { type: "string" },
      keywords: {
        type: "array",
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
          body: { type: "string" },
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
          body: { type: "string" },
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
      gentleSuggestions: { type: "array", maxItems: 5, items: { type: "string" } },
      uncertainty: { type: "array", maxItems: 5, items: { type: "string" } },
    },
  };
}

function validateReviewOutput(value: unknown): ReviewOutput {
  if (!isRecord(value)) {
    throw new AISummaryProviderError("invalid_response", "AI review response was invalid");
  }

  return {
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
        momentIds: getStringArray(item.momentIds).slice(0, 4),
      }))
      .filter((item) => item.title && item.note)
      .slice(0, 8),
    gentleSuggestions: getStringArray(value.gentleSuggestions).slice(0, 5),
    uncertainty: getStringArray(value.uncertainty).slice(0, 5),
  };
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
