import { createHash } from "node:crypto";
import { execFile } from "node:child_process";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { promisify } from "node:util";

import type { AISummaryConfig } from "../config/app-config.js";
import { recordCompletionUsage, type AIUsageContext } from "./usage.js";

export const MEDIA_SUMMARY_PROMPT_VERSION = "media-summary-v4";
const execFileAsync = promisify(execFile);
const LOCAL_TRANSCRIPTION_MAX_BUFFER_BYTES = 20 * 1024 * 1024;
const SHORT_TOPIC_AUDIO_SECONDS = 3 * 60;
const SHORT_TOPIC_TRANSCRIPT_CHARACTERS = 600;
const STRONG_ADDITIONAL_TOPIC_CONFIDENCE = 0.78;
const MAX_DOCUMENT_TITLE_CHARS = 40;
const MAX_TOPIC_ALIASES_IN_PROMPT = 6;

export type AILanguagePreference = "auto" | "zh" | "en";

export interface MediaSummaryTopicTagHint {
  name: string;
  aliases: string[];
}

export interface MediaSummarySection {
  heading: string;
  bullets: string[];
}

export type MediaSummaryDocumentBlockKind =
  | "heading"
  | "paragraph"
  | "bullets"
  | "numbered_list"
  | "ai_suggested";

export interface MediaSummaryDocumentBlock {
  kind: MediaSummaryDocumentBlockKind;
  level: 0 | 1 | 2;
  text: string;
  items: string[];
}

export interface MediaSummaryTagSuggestion {
  name: string;
  confidence: number;
}

export interface MediaSummaryTagOutput {
  primary: MediaSummaryTagSuggestion | null;
  topics: MediaSummaryTagSuggestion[];
}

export interface MediaSummaryOutput {
  format: "sentence" | "summary_with_points" | "sectioned" | "document";
  language: "zh" | "en" | "mixed" | "unknown";
  documentTitle: string | null;
  oneLiner: string;
  documentBlocks: MediaSummaryDocumentBlock[];
  suggestedTags: MediaSummaryTagOutput;
  overview: string;
  keyPoints: string[];
  sections: MediaSummarySection[];
}

export interface MediaSummaryInput {
  transcriptText: string;
  durationSeconds: number | null;
  aiLanguage?: AILanguagePreference;
  existingTopicTags?: MediaSummaryTopicTagHint[];
}

export interface MediaFileSummaryInput {
  filePath: string;
  fileName: string;
  mimeType: string | null;
  durationSeconds: number | null;
  aiLanguage?: AILanguagePreference;
  existingTopicTags?: MediaSummaryTopicTagHint[];
}

export interface MediaFileSummaryOutput {
  transcriptHash: string | null;
  transcriptLength: number | null;
  summary: MediaSummaryOutput;
}

export interface MediaSummaryGenerationHooks {
  onTranscriptReady?: () => Promise<void>;
  usageContext?: AIUsageContext;
}

interface TopicTagContext {
  transcriptText?: string;
  durationSeconds: number | null;
  existingTopicTags?: MediaSummaryTopicTagHint[];
}

export class AISummaryProviderError extends Error {
  constructor(
    readonly code: string,
    message: string,
  ) {
    super(message);
    this.name = "AISummaryProviderError";
  }
}

export function transcriptHash(transcriptText: string): string {
  return createHash("sha256").update(transcriptText, "utf8").digest("hex");
}

function inferLanguageFromText(text: string): MediaSummaryOutput["language"] {
  let cjkCount = 0;
  let latinCount = 0;

  for (const character of text) {
    if (/[\u3400-\u9fff]/u.test(character)) {
      cjkCount += 1;
    } else if (/[a-z]/iu.test(character)) {
      latinCount += 1;
    }
  }

  if (cjkCount >= 8 && latinCount >= 8) {
    return cjkCount >= latinCount * 2 ? "zh" : "mixed";
  }

  if (cjkCount >= 8) {
    return "zh";
  }

  if (latinCount >= 16) {
    return "en";
  }

  return "unknown";
}

export function summaryText(output: MediaSummaryOutput): string {
  if (output.documentBlocks.length > 0) {
    return documentSummaryText(output);
  }

  const lines = [output.overview.trim()];

  if (output.keyPoints.length > 0) {
    lines.push("", ...output.keyPoints.map((point) => `- ${point}`));
  }

  for (const section of output.sections) {
    lines.push("", section.heading, ...section.bullets.map((bullet) => `- ${bullet}`));
  }

  return lines.filter((line, index, all) => line.length > 0 || all[index - 1]?.length).join("\n");
}

function documentSummaryText(output: MediaSummaryOutput): string {
  const lines: string[] = [];
  if (output.documentTitle) {
    lines.push(`# ${output.documentTitle}`);
    lines.push("");
  }

  lines.push(output.oneLiner.trim());

  for (const block of output.documentBlocks) {
    if (block.kind === "heading") {
      lines.push("", `${block.level === 2 ? "###" : "##"} ${block.text}`);
      continue;
    }

    if (block.kind === "paragraph") {
      lines.push("", block.text);
      continue;
    }

    if (block.kind === "bullets") {
      if (block.text) {
        lines.push("", block.text);
      } else {
        lines.push("");
      }
      lines.push(...block.items.map((item) => `- ${item}`));
      continue;
    }

    if (block.kind === "numbered_list") {
      if (block.text) {
        lines.push("", block.text);
      } else {
        lines.push("");
      }
      lines.push(...block.items.map((item, index) => `${index + 1}. ${item}`));
      continue;
    }

    if (block.kind === "ai_suggested") {
      lines.push("", `> AI suggested${block.text ? `: ${block.text}` : ""}`);
      lines.push(...block.items.map((item) => `> - ${item}`));
    }
  }

  return lines.filter((line, index, all) => line.length > 0 || all[index - 1]?.length).join("\n");
}

export async function generateMediaSummary(
  config: AISummaryConfig,
  input: MediaSummaryInput,
  usageContext?: AIUsageContext,
): Promise<MediaSummaryOutput> {
  if (!config.apiKey) {
    throw new AISummaryProviderError("not_configured", "AI summary provider is not configured");
  }

  const response = await callChatCompletions(config, input, usageContext);
  let output = ensureDocumentTitleForRecognizableSummary(
    normalizeSummaryTagsForContext(validateSummaryOutput(response), input),
  );
  if (needsTagFallback(output.suggestedTags) && input.transcriptText.trim().length >= 8) {
    const fallbackTags = await generateTagSuggestions(config, input, usageContext);
    output = normalizeSummaryTagsForContext(
      {
        ...output,
        suggestedTags: mergeSuggestedTags(output.suggestedTags, fallbackTags),
      },
      input,
    );
  }

  if (output.language === "unknown") {
    return {
      ...output,
      language: inferLanguageFromText(input.transcriptText),
    };
  }

  return output;
}

export async function generateMediaSummaryFromFile(
  config: AISummaryConfig,
  input: MediaFileSummaryInput,
  hooks: MediaSummaryGenerationHooks = {},
): Promise<MediaFileSummaryOutput> {
  let transcriptText: string;
  try {
    transcriptText = await transcribeMediaFile(config, input);
  } catch (error) {
    if (shouldFallbackToAudioInput(error)) {
      return generateMediaSummaryFromAudioInput(config, input, hooks);
    }

    throw error;
  }

  const trimmedTranscript = transcriptText.trim();
  if (!trimmedTranscript) {
    throw new AISummaryProviderError("empty_transcript", "AI transcription returned no text");
  }

  await hooks.onTranscriptReady?.();

  return {
    transcriptHash: transcriptHash(trimmedTranscript),
    transcriptLength: trimmedTranscript.length,
    summary: await generateMediaSummary(config, {
      transcriptText: trimmedTranscript,
      durationSeconds: input.durationSeconds,
      aiLanguage: input.aiLanguage ?? "auto",
      existingTopicTags: input.existingTopicTags,
    }, hooks.usageContext),
  };
}

async function generateMediaSummaryFromAudioInput(
  config: AISummaryConfig,
  input: MediaFileSummaryInput,
  hooks: MediaSummaryGenerationHooks,
): Promise<MediaFileSummaryOutput> {
  const summary = ensureDocumentTitleForRecognizableSummary(
    normalizeSummaryTagsForContext(validateSummaryOutput(await callChatCompletionsWithAudio(
      config,
      input,
      hooks.usageContext,
    )), {
      durationSeconds: input.durationSeconds,
    }),
  );
  if (isAudioInputUnusableSummary(summary)) {
    throw new AISummaryProviderError(
      "audio_input_unusable",
      "AI audio input provider did not access the audio content",
    );
  }

  return {
    transcriptHash: null,
    transcriptLength: null,
    summary,
  };
}

function shouldFallbackToAudioInput(error: unknown): boolean {
  return (
    error instanceof AISummaryProviderError &&
    (error.code === "transcription_http_404" || error.code === "transcription_http_405")
  );
}

async function transcribeMediaFile(
  config: AISummaryConfig,
  input: MediaFileSummaryInput,
): Promise<string> {
  if (config.transcriptionProvider === "local") {
    return transcribeMediaFileLocally(config, input);
  }

  if (config.transcriptionProvider !== "openai") {
    throw new AISummaryProviderError(
      "transcription_provider_unsupported",
      "AI transcription provider is not supported",
    );
  }

  return transcribeMediaFileWithOpenAI(config, input);
}

async function transcribeMediaFileLocally(
  config: AISummaryConfig,
  input: MediaFileSummaryInput,
): Promise<string> {
  try {
    const { stdout } = await execFileAsync(
      config.localTranscriptionPythonPath,
      [
        config.localTranscriptionScriptPath,
        "--audio",
        input.filePath,
        "--model",
        config.localTranscriptionModel,
      ],
      {
        timeout: config.localTranscriptionTimeoutMs,
        maxBuffer: LOCAL_TRANSCRIPTION_MAX_BUFFER_BYTES,
      },
    );
    const parsed = parseLocalTranscriptionOutput(stdout);
    const transcript = extractTranscriptionText(parsed);
    if (!transcript) {
      throw new AISummaryProviderError("empty_transcript", "Local transcription returned no text");
    }

    return transcript;
  } catch (error) {
    if (error instanceof AISummaryProviderError) {
      throw error;
    }

    if (error instanceof Error && /timed out|timeout/i.test(error.message)) {
      throw new AISummaryProviderError("local_transcription_timeout", "Local transcription timed out");
    }

    throw new AISummaryProviderError("local_transcription_failed", "Local transcription failed");
  }
}

function parseLocalTranscriptionOutput(stdout: string): unknown {
  const candidates = stdout
    .split("\n")
    .map((line) => line.trim())
    .filter((line) => line.startsWith("{") && line.endsWith("}"));

  const jsonLine = candidates.at(-1);
  if (!jsonLine) {
    throw new AISummaryProviderError("local_transcription_invalid_output", "Local transcription output was invalid");
  }

  try {
    return JSON.parse(jsonLine) as unknown;
  } catch {
    throw new AISummaryProviderError("local_transcription_invalid_output", "Local transcription output was invalid");
  }
}

async function transcribeMediaFileWithOpenAI(
  config: AISummaryConfig,
  input: MediaFileSummaryInput,
): Promise<string> {
  if (!config.apiKey) {
    throw new AISummaryProviderError("not_configured", "AI summary provider is not configured");
  }

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), config.timeoutMs);

  try {
    const fileData = await readFile(input.filePath);
    const formData = new FormData();
    formData.append("model", config.transcriptionModel);
    formData.append("response_format", "json");
    formData.append(
      "file",
      new Blob([fileData], { type: input.mimeType ?? "application/octet-stream" }),
      input.fileName,
    );

    const response = await fetch(`${config.baseUrl}/audio/transcriptions`, {
      method: "POST",
      signal: controller.signal,
      headers: {
        Authorization: `Bearer ${config.apiKey}`,
      },
      body: formData,
    });

    if (!response.ok) {
      throw new AISummaryProviderError(
        `transcription_http_${response.status}`,
        `AI transcription provider returned HTTP ${response.status}`,
      );
    }

    const parsed = (await response.json()) as unknown;
    const transcript = extractTranscriptionText(parsed);
    if (!transcript) {
      throw new AISummaryProviderError("empty_transcript", "AI transcription returned no text");
    }

    return transcript;
  } catch (error) {
    if (error instanceof AISummaryProviderError) {
      throw error;
    }

    if (error instanceof Error && error.name === "AbortError") {
      throw new AISummaryProviderError("transcription_timeout", "AI transcription request timed out");
    }

    throw new AISummaryProviderError("transcription_failed", "AI transcription request failed");
  } finally {
    clearTimeout(timeout);
  }
}

async function callChatCompletions(
  config: AISummaryConfig,
  input: MediaSummaryInput,
  usageContext?: AIUsageContext,
): Promise<unknown> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), config.timeoutMs);
  const systemContent = systemPrompt(input.aiLanguage ?? "auto");
  const userContent = userPrompt(input);
  const inputChars = systemContent.length + userContent.length + JSON.stringify(summaryJsonSchema()).length;
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
        temperature: 0.2,
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
            name: "media_summary",
            strict: true,
            schema: summaryJsonSchema(),
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
      throw new AISummaryProviderError("empty_response", "AI provider returned no summary");
    }

    try {
      const parsedContent = JSON.parse(content) as unknown;
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

async function generateTagSuggestions(
  config: AISummaryConfig,
  input: MediaSummaryInput,
  parentUsageContext?: AIUsageContext,
): Promise<MediaSummaryTagOutput> {
  try {
    const value = await callTagCompletions(config, input, parentUsageContext);
    const suggestedTags = parseSuggestedTags(value);
    return normalizeSuggestedTagsForContext(
      {
        ...suggestedTags,
        primary: suggestedTags.primary ?? inferPrimaryTagSuggestion(input.transcriptText),
      },
      input,
    );
  } catch {
    return {
      primary: inferPrimaryTagSuggestion(input.transcriptText),
      topics: [],
    };
  }
}

async function callTagCompletions(
  config: AISummaryConfig,
  input: MediaSummaryInput,
  parentUsageContext?: AIUsageContext,
): Promise<unknown> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), config.timeoutMs);
  const usageContext = parentUsageContext
    ? {
        ...parentUsageContext,
        feature: "tag_suggestion",
      }
    : undefined;

  try {
    const transcript = input.transcriptText.trim();
    const systemContent = [
      "You classify private spoken notes into organization tags for a personal timeline app.",
      "Return only the requested JSON object.",
      "primary must be one of 日记, 想法, 学习整理, 情绪, 碎碎念, 复盘, or null only when the transcript has no meaningful content.",
      "Use primary 想法 for product ideas, feature requests, app/UI design thoughts, opinions, plans, and design discussions.",
      "Use primary 学习整理 for learning notes, primary 日记 for day recaps, primary 情绪 for explicit emotional venting, primary 复盘 for after-event reflection, and primary 碎碎念 for pure casual/test notes.",
      "topics must be concrete reusable subjects from the transcript, at most 3 items. Use Chinese canonical names when natural.",
      "When existing active topic tags are provided, prefer those canonical names and aliases before creating a new topic. Return the exact existing canonical name when it fits, even if the transcript contains a more specific wording.",
      "Be conservative with topic count: one clear subject should produce one topic. Multiple topics are only for clearly separate themes, not details under the same theme.",
      "For short notes, prefer exactly one topic unless the transcript explicitly covers multiple unrelated subjects with high confidence.",
      "Return confidence numbers from 0 to 1. For recognizable content, primary confidence should normally be at least 0.6.",
    ].join("\n");
    const userContent = [
      `Media duration seconds: ${input.durationSeconds ?? "unknown"}`,
      `Transcript characters: ${transcript.length}`,
      `Suggested topic count: ${topicCountHint(input)}`,
      "",
      topicVocabularyPrompt(input.existingTopicTags),
      "",
      "Transcript:",
      transcript,
    ].join("\n");
    const inputChars = systemContent.length + userContent.length + JSON.stringify(tagSuggestionJsonSchema()).length;
    const startedAt = Date.now();
    const response = await fetch(`${config.baseUrl}/chat/completions`, {
      method: "POST",
      signal: controller.signal,
      headers: {
        Authorization: `Bearer ${config.apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: config.model,
        temperature: 0.1,
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
            name: "media_tags",
            strict: true,
            schema: tagSuggestionJsonSchema(),
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
        errorCode: `tag_provider_http_${response.status}`,
      });
      throw new AISummaryProviderError(
        `tag_provider_http_${response.status}`,
        `AI tag provider returned HTTP ${response.status}`,
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
        errorCode: "tag_empty_response",
      });
      throw new AISummaryProviderError("tag_empty_response", "AI provider returned no tags");
    }

    const parsedContent = JSON.parse(content) as unknown;
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
  } catch (error) {
    if (error instanceof AISummaryProviderError) {
      throw error;
    }

    if (error instanceof Error && error.name === "AbortError") {
      await recordCompletionUsage(usageContext, {
        provider: config.provider,
        model: config.model,
        status: "failed",
        inputChars: 0,
        durationMs: config.timeoutMs,
        errorCode: "tag_provider_timeout",
      });
      throw new AISummaryProviderError("tag_provider_timeout", "AI tag request timed out");
    }

    await recordCompletionUsage(usageContext, {
      provider: config.provider,
      model: config.model,
      status: "failed",
      inputChars: 0,
      durationMs: 0,
      errorCode: "tag_provider_failed",
    });
    throw new AISummaryProviderError("tag_provider_failed", "AI tag request failed");
  } finally {
    clearTimeout(timeout);
  }
}

async function callChatCompletionsWithAudio(
  config: AISummaryConfig,
  input: MediaFileSummaryInput,
  usageContext?: AIUsageContext,
): Promise<unknown> {
  if (!config.apiKey) {
    throw new AISummaryProviderError("not_configured", "AI summary provider is not configured");
  }

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), config.timeoutMs);
  const systemContent = audioSystemPrompt(input.aiLanguage ?? "auto");
  const userText = audioUserPrompt(input);
  const inputChars = systemContent.length + userText.length + JSON.stringify(summaryJsonSchema()).length;
  const startedAt = Date.now();

  try {
    const audioData = await convertMediaFileToWavBase64(input.filePath);
    const response = await fetch(`${config.baseUrl}/chat/completions`, {
      method: "POST",
      signal: controller.signal,
      headers: {
        Authorization: `Bearer ${config.apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: config.model,
        temperature: 0.2,
        store: false,
        modalities: ["text"],
        messages: [
          {
            role: "system",
            content: systemContent,
          },
          {
            role: "user",
            content: [
              {
                type: "text",
                text: userText,
              },
              {
                type: "input_audio",
                input_audio: {
                  data: audioData,
                  format: "wav",
                },
              },
            ],
          },
        ],
        response_format: {
          type: "json_schema",
          json_schema: {
            name: "media_summary",
            strict: true,
            schema: summaryJsonSchema(),
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
        errorCode: `audio_input_http_${response.status}`,
      });
      throw new AISummaryProviderError(
        `audio_input_http_${response.status}`,
        `AI audio input provider returned HTTP ${response.status}`,
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
      throw new AISummaryProviderError("empty_response", "AI provider returned no summary");
    }

    try {
      const parsedContent = JSON.parse(content) as unknown;
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
        errorCode: "audio_input_timeout",
      });
      throw new AISummaryProviderError("audio_input_timeout", "AI audio input request timed out");
    }

    await recordCompletionUsage(usageContext, {
      provider: config.provider,
      model: config.model,
      status: "failed",
      inputChars,
      durationMs: Date.now() - startedAt,
      errorCode: "audio_input_failed",
    });
    throw new AISummaryProviderError("audio_input_failed", "AI audio input request failed");
  } finally {
    clearTimeout(timeout);
  }
}

async function convertMediaFileToWavBase64(filePath: string): Promise<string> {
  const tempDirectory = await mkdtemp(path.join(tmpdir(), "private-moments-audio-"));
  const outputPath = path.join(tempDirectory, "input.wav");

  try {
    await execFileAsync("afconvert", ["-f", "WAVE", "-d", "LEI16", filePath, outputPath]);
    const output = await readFile(outputPath);
    return output.toString("base64");
  } catch {
    throw new AISummaryProviderError(
      "audio_input_prepare_failed",
      "Failed to prepare media file for AI audio input",
    );
  } finally {
    await rm(tempDirectory, { recursive: true, force: true });
  }
}

function systemPrompt(aiLanguage: AILanguagePreference = "auto"): string {
  return [
    "You organize private spoken notes for a personal local-first timeline app.",
    "The transcript may be casual, rambling, diary-like, emotional, or practical rather than a polished lecture.",
    "Be quiet, practical, non-judgmental, and useful as a memory aid for the speaker.",
    "Use only information present in the transcript. Do not infer visual content, speaker identity, emotion, intent, or facts that are not supported.",
    "Separate objective events/facts from the speaker's reflections or judgments when that distinction is useful.",
    "You may include lightweight next-step suggestions only in ai_suggested blocks. Keep them clearly framed as suggestions and do not mix them into factual summary blocks.",
    languageInstruction(aiLanguage, "transcript"),
    "Preserve concrete details that help future recall: events, places, people labels, decisions, lessons, body/rehab instructions, interview reflections, and explicit next actions.",
    "Distinguish facts from feelings when the speaker is reflecting. Do not turn private reflection into public feedback or motivational coaching.",
    "Adapt density to transcript length and substance. Tiny notes should not become fake structured reports; long or multi-topic notes should use heading blocks, short paragraphs, and lists.",
    "Also suggest private organization tags. Tagging is independent of summary density: even tiny notes should get tags when the transcript has clear content.",
    "For primary, choose the best expression type for every non-empty note with recognizable words; return null only when the transcript is content-free, unintelligible, or only silence/noise. Use confidence to express uncertainty.",
    "Primary mapping: 日记 = day recap/life log; 想法 = product idea, feature thought, opinion, plan, or design discussion; 学习整理 = learning notes or concept review; 情绪 = explicit emotion/venting; 碎碎念 = casual low-purpose note or test note; 复盘 = reflection after an event, interview, workout, meeting, or decision.",
    "Topics should be concrete reusable subjects from the transcript, such as LLM, 面试, 运动康复, 高斯分布, 标签系统, or 颜色设置, with at most 3 items. Do not leave topics empty when clear reusable subjects are present.",
    "When existing active topic tags are provided, prefer those canonical names and aliases before creating a new topic. Return the exact existing canonical name when it fits, even if the transcript contains a more specific wording.",
    "Topic count should be conservative: one clear subject should produce one topic. For short notes under about 3 minutes or 600 transcript characters, return more than one topic only when there are clearly separate themes.",
    "Returning { primary: null, topics: [] } for a recognizable spoken note is a failure. For a short app/product feature note, use primary 想法 and topic tags like 标签系统 or 颜色设置 when present. For a pure test note, use primary 碎碎念.",
    "Return structured JSON only. Do not return Markdown text; the app renders the JSON as a Markdown-like document.",
  ].join("\n");
}

function audioSystemPrompt(aiLanguage: AILanguagePreference = "auto"): string {
  return [
    "You summarize private audio from a personal local-first timeline app.",
    "Be quiet, practical, non-judgmental, and useful as a memory aid.",
    "Use only information you can hear in the audio. Do not infer visual content, speaker identity, emotion, intent, or facts that are not supported.",
    "Separate objective events/facts from the speaker's reflections or judgments when that distinction is useful.",
    "You may include lightweight next-step suggestions only in ai_suggested blocks. Keep them clearly framed as suggestions and do not mix them into factual summary blocks.",
    languageInstruction(aiLanguage, "audio"),
    "Adapt density to the length of the note. Tiny notes should not become fake structured reports; long notes should use heading blocks, short paragraphs, and lists.",
    "Also suggest private organization tags. Tagging is independent of summary density: even tiny notes should get tags when the audio has clear content.",
    "For primary, choose the best expression type for every non-empty note with recognizable words; return null only when the audio is content-free, unintelligible, or only silence/noise. Use confidence to express uncertainty.",
    "Primary mapping: 日记 = day recap/life log; 想法 = product idea, feature thought, opinion, plan, or design discussion; 学习整理 = learning notes or concept review; 情绪 = explicit emotion/venting; 碎碎念 = casual low-purpose note or test note; 复盘 = reflection after an event, interview, workout, meeting, or decision.",
    "Topics should be concrete reusable subjects from the audio, such as LLM, 面试, 运动康复, 高斯分布, 标签系统, or 颜色设置, with at most 3 items. Do not leave topics empty when clear reusable subjects are present.",
    "When existing active topic tags are provided, prefer those canonical names and aliases before creating a new topic. Return the exact existing canonical name when it fits, even if the audio uses a more specific wording.",
    "Topic count should be conservative: one clear subject should produce one topic. For short notes under about 3 minutes, return more than one topic only when there are clearly separate themes.",
    "Returning { primary: null, topics: [] } for a recognizable spoken note is a failure. For a short app/product feature note, use primary 想法 and topic tags like 标签系统 or 颜色设置 when present. For a pure test note, use primary 碎碎念.",
    "Return structured JSON only. Do not return Markdown text; the app renders the JSON as a Markdown-like document.",
  ].join("\n");
}

function languageInstruction(aiLanguage: AILanguagePreference, sourceLabel: "transcript" | "audio"): string {
  if (aiLanguage === "zh") {
    return "Write the summary and documentTitle in natural Chinese. Preserve necessary English technical terms when they are part of the source.";
  }

  if (aiLanguage === "en") {
    return "Write the summary and documentTitle in natural English. Preserve necessary Chinese names or terms when they are part of the source.";
  }

  return `Follow the ${sourceLabel}'s dominant language. If it is mostly Chinese, write natural Chinese even when English technical terms appear. If it is mostly English, write natural English. If it is genuinely mixed, keep the summary naturally mixed.`;
}

function userPrompt(input: MediaSummaryInput): string {
  const transcript = input.transcriptText.trim();
  return [
    `Media duration seconds: ${input.durationSeconds ?? "unknown"}`,
    `Transcript characters: ${transcript.length}`,
    `Suggested density: ${densityHint(transcript.length, input.durationSeconds)}`,
    `Suggested topic count: ${topicCountHint(input)}`,
    "",
    "Organization guidance:",
    `- For any recognizable non-empty note, return a concise documentTitle of ${MAX_DOCUMENT_TITLE_CHARS} characters or fewer. Return null only when the transcript is content-free, unintelligible, or only silence/noise.`,
    "- oneLiner is the quick top-level summary.",
    "- Use heading blocks for major themes and level 2 heading blocks for subtopics; do not exceed two heading levels.",
    "- Keep paragraph blocks short. Prefer bullets or numbered_list blocks for dense information.",
    "- Use ai_suggested blocks only for AI-inferred lightweight next steps; explicit next actions from the transcript belong in normal content blocks.",
    "- If this is a daily diary, summarize the day around memorable events, mood, decisions, and loose threads.",
    "- If this is an interview or meeting reflection, capture what happened, what the speaker learned, concerns, and next steps if explicit.",
    "- If this is rehab, training, or learning notes, preserve instructions, corrections, exercises, cues, warnings, and follow-up actions.",
    "- If this is a casual observation, keep it compact and concrete instead of forcing a lecture-like structure.",
    "- Suggested tags: choose one primary for any note with recognizable content. Use topics for concrete reusable subjects, not broad expression types. Tag suggestions are still required even when the summary is oneLiner-only. Do not return primary null and empty topics unless the transcript is content-free.",
    "- Topic tags should be sparse. Prefer one topic for one subject; use multiple only for genuinely separate themes.",
    "- Topic vocabulary reuse: if an existing active topic tag or alias fits the transcript, return that exact canonical topic name. Create a new topic only when no existing tag fits.",
    "",
    topicVocabularyPrompt(input.existingTopicTags),
    "",
    "Transcript:",
    transcript,
  ].join("\n");
}

function audioUserPrompt(input: MediaFileSummaryInput): string {
  return [
    `Media duration seconds: ${input.durationSeconds ?? "unknown"}`,
    `Suggested density: ${mediaDensityHint(input.durationSeconds)}`,
    `Suggested topic count: ${topicCountHint({ durationSeconds: input.durationSeconds })}`,
    "",
    "Listen to the attached audio and summarize it for the private timeline.",
    "If this came from a video, summarize only the audible content and do not describe visuals.",
    `For any recognizable non-empty note, return a concise documentTitle of ${MAX_DOCUMENT_TITLE_CHARS} characters or fewer. Return null only when the audio is content-free, unintelligible, or only silence/noise.`,
    "oneLiner is the quick top-level summary. Use heading blocks for major themes and level 2 heading blocks for subtopics; do not exceed two heading levels.",
    "Use ai_suggested blocks only for AI-inferred lightweight next steps; explicit next actions from the audio belong in normal content blocks.",
    "Suggested tags: choose one primary for any note with recognizable content. Use topics for concrete reusable subjects, not broad expression types. Tag suggestions are still required even when the summary is oneLiner-only. Do not return primary null and empty topics unless the audio is content-free.",
    "Topic tags should be sparse. Prefer one topic for one subject; use multiple only for genuinely separate themes.",
    "Topic vocabulary reuse: if an existing active topic tag or alias fits the audio, return that exact canonical topic name. Create a new topic only when no existing tag fits.",
    "",
    topicVocabularyPrompt(input.existingTopicTags),
  ].join("\n");
}

function topicVocabularyPrompt(topicTags: MediaSummaryTopicTagHint[] | undefined): string {
  const cleanedTopicTags = cleanTopicTagHints(topicTags);
  if (cleanedTopicTags.length === 0) {
    return "Existing active topic tags: none yet.";
  }

  return [
    "Existing active topic tags. Reuse the exact canonical name before inventing a new topic:",
    ...cleanedTopicTags.map((tag) => {
      const aliases = tag.aliases.slice(0, MAX_TOPIC_ALIASES_IN_PROMPT);
      return aliases.length > 0
        ? `- ${tag.name} (aliases: ${aliases.join(", ")})`
        : `- ${tag.name}`;
    }),
  ].join("\n");
}

function cleanTopicTagHints(topicTags: MediaSummaryTopicTagHint[] | undefined): MediaSummaryTopicTagHint[] {
  if (!topicTags) {
    return [];
  }

  const seenNames = new Set<string>();
  const cleaned: MediaSummaryTopicTagHint[] = [];
  for (const tag of topicTags) {
    const name = tag.name.normalize("NFKC").trim().replace(/\s+/g, " ");
    if (!name) {
      continue;
    }

    const normalizedName = name.toLocaleLowerCase("zh-Hans-CN");
    if (seenNames.has(normalizedName)) {
      continue;
    }
    seenNames.add(normalizedName);

    const seenAliases = new Set<string>();
    const aliases = tag.aliases
      .map((alias) => alias.normalize("NFKC").trim().replace(/\s+/g, " "))
      .filter((alias) => {
        if (!alias) {
          return false;
        }

        const normalizedAlias = alias.toLocaleLowerCase("zh-Hans-CN");
        if (normalizedAlias === normalizedName || seenAliases.has(normalizedAlias)) {
          return false;
        }

        seenAliases.add(normalizedAlias);
        return true;
      });

    cleaned.push({ name, aliases });
  }

  return cleaned;
}

function normalizeSummaryTagsForContext(
  output: MediaSummaryOutput,
  context: TopicTagContext,
): MediaSummaryOutput {
  return {
    ...output,
    suggestedTags: normalizeSuggestedTagsForContext(output.suggestedTags, context),
  };
}

function normalizeSuggestedTagsForContext(
  suggestedTags: MediaSummaryTagOutput,
  context: TopicTagContext,
): MediaSummaryTagOutput {
  const topics = [...suggestedTags.topics]
    .filter((topic) => topic.name.trim().length > 0)
    .sort((lhs, rhs) => rhs.confidence - lhs.confidence);
  const limit = topicLimitForContext(topics, context);

  return {
    ...suggestedTags,
    topics: topics.slice(0, limit),
  };
}

function topicLimitForContext(
  topics: MediaSummaryTagSuggestion[],
  context: TopicTagContext,
): number {
  if (topics.length <= 1) {
    return topics.length;
  }

  if (!isShortTopicContext(context)) {
    return Math.min(topics.length, 3);
  }

  const strongAdditionalTopicCount = topics
    .slice(1)
    .filter((topic) => topic.confidence >= STRONG_ADDITIONAL_TOPIC_CONFIDENCE).length;

  return Math.min(1 + strongAdditionalTopicCount, topics.length, 3);
}

function topicCountHint(context: TopicTagContext): string {
  if (isShortTopicContext(context)) {
    return "prefer 1 topic; use 2-3 only for clearly separate themes, each with high confidence";
  }

  return "prefer the minimum useful topic count; use 2-3 only for clearly separate themes";
}

function isShortTopicContext(context: TopicTagContext): boolean {
  const transcriptCharacters = context.transcriptText?.trim().length;
  const isShortByTranscript =
    typeof transcriptCharacters === "number" && transcriptCharacters < SHORT_TOPIC_TRANSCRIPT_CHARACTERS;
  const isShortByDuration =
    context.durationSeconds !== null && context.durationSeconds < SHORT_TOPIC_AUDIO_SECONDS;

  return isShortByTranscript || isShortByDuration;
}

function mediaDensityHint(durationSeconds: number | null): string {
  if (durationSeconds !== null && durationSeconds < 60) {
    return "oneLiner only, no blocks unless essential";
  }

  if (durationSeconds !== null && durationSeconds < 5 * 60) {
    return "oneLiner plus 2-3 concise blocks if useful";
  }

  if (durationSeconds !== null && durationSeconds < 20 * 60) {
    return "oneLiner plus 3-6 structured blocks";
  }

  if (durationSeconds === null) {
    return "oneLiner plus 2-3 concise blocks if useful";
  }

  return "oneLiner plus heading blocks, short paragraphs, and concise lists";
}

function densityHint(length: number, durationSeconds: number | null): string {
  if (length < 300 || (durationSeconds !== null && durationSeconds < 60)) {
    return "oneLiner only, no blocks unless essential";
  }

  if (length < 1_500) {
    return "oneLiner plus 2-3 concise blocks if useful";
  }

  if (length < 6_000) {
    return "oneLiner plus 3-6 structured blocks";
  }

  return "oneLiner plus heading blocks, short paragraphs, and concise lists";
}

function summaryJsonSchema(): Record<string, unknown> {
  return {
    type: "object",
    additionalProperties: false,
    required: ["format", "language", "documentTitle", "oneLiner", "blocks", "suggestedTags"],
    properties: {
      format: {
        type: "string",
        enum: ["sentence", "summary_with_points", "sectioned", "document"],
      },
      language: {
        type: "string",
        enum: ["zh", "en", "mixed", "unknown"],
      },
      documentTitle: {
        type: ["string", "null"],
      },
      oneLiner: {
        type: "string",
      },
      blocks: {
        type: "array",
        items: {
          type: "object",
          additionalProperties: false,
          required: ["kind", "level", "text", "items"],
          properties: {
            kind: {
              type: "string",
              enum: ["heading", "paragraph", "bullets", "numbered_list", "ai_suggested"],
            },
            level: {
              type: "integer",
              enum: [0, 1, 2],
            },
            text: {
              type: "string",
            },
            items: {
              type: "array",
              items: {
                type: "string",
              },
            },
          },
        },
      },
      suggestedTags: {
        type: "object",
        additionalProperties: false,
        required: ["primary", "topics"],
        properties: {
          primary: {
            anyOf: [
              {
                type: "object",
                additionalProperties: false,
                required: ["name", "confidence"],
                properties: {
                  name: {
                    type: "string",
                    enum: ["日记", "想法", "学习整理", "情绪", "碎碎念", "复盘"],
                  },
                  confidence: {
                    type: "number",
                    minimum: 0,
                    maximum: 1,
                  },
                },
              },
              {
                type: "null",
              },
            ],
          },
          topics: {
            type: "array",
            maxItems: 3,
            items: {
              type: "object",
              additionalProperties: false,
              required: ["name", "confidence"],
              properties: {
                name: {
                  type: "string",
                },
                confidence: {
                  type: "number",
                  minimum: 0,
                  maximum: 1,
                },
              },
            },
          },
        },
      },
    },
  };
}

function tagSuggestionJsonSchema(): Record<string, unknown> {
  return {
    type: "object",
    additionalProperties: false,
    required: ["primary", "topics"],
    properties: {
      primary: {
        anyOf: [
          {
            type: "object",
            additionalProperties: false,
            required: ["name", "confidence"],
            properties: {
              name: {
                type: "string",
                enum: ["日记", "想法", "学习整理", "情绪", "碎碎念", "复盘"],
              },
              confidence: {
                type: "number",
                minimum: 0,
                maximum: 1,
              },
            },
          },
          {
            type: "null",
          },
        ],
      },
      topics: {
        type: "array",
        maxItems: 3,
        items: {
          type: "object",
          additionalProperties: false,
          required: ["name", "confidence"],
          properties: {
            name: {
              type: "string",
            },
            confidence: {
              type: "number",
              minimum: 0,
              maximum: 1,
            },
          },
        },
      },
    },
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

  return null;
}

function extractTranscriptionText(value: unknown): string | null {
  if (!isRecord(value) || typeof value.text !== "string") {
    return null;
  }

  const trimmed = value.text.trim();
  return trimmed.length > 0 ? trimmed : null;
}

function validateSummaryOutput(value: unknown): MediaSummaryOutput {
  if (!isRecord(value)) {
    throw new AISummaryProviderError("invalid_output", "AI summary output is not an object");
  }

  const language = normalizeLanguage(value.language);
  const documentTitle = parseOptionalString(value.documentTitle ?? value.title, 180);
  const oneLiner = parseNonEmptyString(
    value.oneLiner ?? value.one_liner ?? value.overview ?? value.summary ?? value.text,
    1_000,
  );
  const documentBlocks =
    parseDocumentBlocks(value.blocks ?? value.documentBlocks ?? value.content) ??
    documentBlocksFromLegacyValue(value);
  const suggestedTags = parseSuggestedTags(value.suggestedTags ?? value.tags);

  if (!language || !oneLiner) {
    throw new AISummaryProviderError("invalid_output", "AI summary output failed validation");
  }

  const legacy = legacyShapeFromDocument({
    oneLiner,
    documentBlocks,
  });
  const format = normalizeFormat(value.format, legacy.keyPoints, legacy.sections, documentBlocks);

  return {
    format,
    language,
    documentTitle,
    oneLiner,
    documentBlocks,
    suggestedTags,
    overview: oneLiner,
    keyPoints: legacy.keyPoints,
    sections: legacy.sections,
  };
}

function ensureDocumentTitleForRecognizableSummary(output: MediaSummaryOutput): MediaSummaryOutput {
  const existingTitle = cleanedDocumentTitle(output.documentTitle);
  if (existingTitle) {
    return {
      ...output,
      documentTitle: existingTitle,
    };
  }

  const fallbackTitle = fallbackDocumentTitle(output.oneLiner);
  if (!fallbackTitle) {
    return output;
  }

  return {
    ...output,
    documentTitle: fallbackTitle,
  };
}

function cleanedDocumentTitle(value: string | null): string | null {
  if (!value) {
    return null;
  }

  const cleaned = normalizeTitleText(value);
  return charCount(cleaned) <= MAX_DOCUMENT_TITLE_CHARS ? cleaned : null;
}

function fallbackDocumentTitle(oneLiner: string): string | null {
  if (isContentFreeSummaryLine(oneLiner)) {
    return null;
  }

  const cleaned = normalizeTitleText(
    oneLiner
      .replace(/^(这|這)(是)?(一)?(条|條|段)?(语音|音频|錄音|录音|记录|筆記|笔记|note)\s*(主要)?(是|在|关于|圍繞|围绕)?\s*/i, "")
      .replace(/^(This|The)\s+(audio|voice note|recording|note)\s+(is|mainly|focuses on|discusses)\s+/i, ""),
  );
  if (!cleaned) {
    return null;
  }

  const firstSegment = firstUsefulTitleSegment(cleaned) ?? cleaned;
  return shortenTitle(firstSegment);
}

function firstUsefulTitleSegment(value: string): string | null {
  return (
    value
      .split(/[。.!?！？；;：:\n]/)
      .map((segment) => normalizeTitleText(segment))
      .find((segment) => charCount(segment) >= 2) ?? null
  );
}

function shortenTitle(value: string): string | null {
  const cleaned = normalizeTitleText(value);
  if (!cleaned) {
    return null;
  }

  if (charCount(cleaned) <= MAX_DOCUMENT_TITLE_CHARS) {
    return cleaned;
  }

  const shorterClause = cleaned
    .split(/[，,、]/)
    .map((segment) => normalizeTitleText(segment))
    .find((segment) => charCount(segment) >= 2 && charCount(segment) <= MAX_DOCUMENT_TITLE_CHARS);
  if (shorterClause) {
    return shorterClause;
  }

  const truncated = stripTrailingTitlePunctuation(
    Array.from(cleaned).slice(0, MAX_DOCUMENT_TITLE_CHARS).join(""),
  );
  return truncated.length > 0 ? truncated : null;
}

function normalizeTitleText(value: string): string {
  return stripTrailingTitlePunctuation(
    value
      .replace(/^#{1,6}\s+/, "")
      .replace(/\s+/g, " ")
      .trim(),
  );
}

function stripTrailingTitlePunctuation(value: string): string {
  return value.replace(/[\s,，、:：;；.!?。！？]+$/g, "").trim();
}

function charCount(value: string): number {
  return Array.from(value).length;
}

function isContentFreeSummaryLine(value: string): boolean {
  const normalized = value.trim().toLowerCase();
  return [
    "无法识别",
    "不可识别",
    "无法听清",
    "无法听到",
    "没有可识别",
    "只有噪音",
    "只有静音",
    "内容为空",
    "unintelligible",
    "not intelligible",
    "no recognizable",
    "only silence",
    "only noise",
    "empty audio",
  ].some((signal) => normalized.includes(signal));
}

function isAudioInputUnusableSummary(output: MediaSummaryOutput): boolean {
  const text = [
    output.documentTitle,
    output.oneLiner,
    ...output.documentBlocks.flatMap((block) => [block.text, ...block.items]),
    output.overview,
    ...output.keyPoints,
    ...output.sections.flatMap((section) => [section.heading, ...section.bullets]),
  ]
    .filter((item): item is string => typeof item === "string")
    .join("\n")
    .toLowerCase();

  const noAccessSignals = [
    "无法访问",
    "无法听到",
    "不能访问",
    "不能听到",
    "无法播放",
    "没有访问音频",
    "不能生成可靠摘要",
    "can't access",
    "cannot access",
    "can't hear",
    "cannot hear",
    "unable to access",
    "unable to hear",
    "do not have access to the audio",
    "don't have access to the audio",
  ];

  return noAccessSignals.some((signal) => text.includes(signal));
}

function normalizeFormat(
  value: unknown,
  keyPoints: string[],
  sections: MediaSummarySection[],
  documentBlocks: MediaSummaryDocumentBlock[] = [],
): MediaSummaryOutput["format"] {
  if (typeof value === "string") {
    const normalized = value.trim().toLowerCase().replaceAll("-", "_").replaceAll(" ", "_");
    if (normalized === "document" || normalized === "blocks" || normalized === "block_document") {
      return "document";
    }

    if (normalized === "sentence" || normalized === "brief" || normalized === "short") {
      return "sentence";
    }

    if (
      normalized === "summary_with_points" ||
      normalized === "structured" ||
      normalized === "bullet_points" ||
      normalized === "points"
    ) {
      return "summary_with_points";
    }

    if (normalized === "sectioned" || normalized === "detailed" || normalized === "sections") {
      return "sectioned";
    }
  }

  if (documentBlocks.length > 0) {
    return documentBlocks.some((block) => block.kind === "heading") ? "document" : "summary_with_points";
  }

  if (sections.length > 0) {
    return "sectioned";
  }

  return keyPoints.length > 0 ? "summary_with_points" : "sentence";
}

function normalizeLanguage(value: unknown): MediaSummaryOutput["language"] {
  if (typeof value !== "string") {
    return "unknown";
  }

  const normalized = value.trim().toLowerCase();
  if (normalized === "zh" || normalized.startsWith("zh-") || normalized.includes("chinese")) {
    return "zh";
  }

  if (normalized === "en" || normalized.startsWith("en-") || normalized.includes("english")) {
    return "en";
  }

  if (normalized.includes("mixed") || normalized.includes("multi")) {
    return "mixed";
  }

  if (normalized === "unknown" || normalized === "und") {
    return "unknown";
  }

  return "unknown";
}

function parseNonEmptyString(value: unknown, maxLength: number): string | null {
  if (typeof value !== "string") {
    return null;
  }

  const trimmed = value.trim();
  if (!trimmed || trimmed.length > maxLength) {
    return null;
  }

  return trimmed;
}

function parseOptionalString(value: unknown, maxLength: number): string | null {
  if (value === null || value === undefined) {
    return null;
  }

  return parseNonEmptyString(value, maxLength);
}

function parseStringArray(value: unknown, maxItems: number, maxLength: number): string[] | null {
  if (!Array.isArray(value) || value.length > maxItems) {
    return null;
  }

  const result: string[] = [];
  for (const item of value) {
    const parsed = parseNonEmptyString(item, maxLength);
    if (parsed) {
      result.push(parsed);
    }
  }

  return result;
}

function parseSuggestedTags(value: unknown): MediaSummaryTagOutput {
  if (!isRecord(value)) {
    return {
      primary: null,
      topics: [],
    };
  }

  return {
    primary: parseTagSuggestion(value.primary),
    topics: parseTagSuggestionArray(value.topics, 3),
  };
}

function isEmptySuggestedTags(value: MediaSummaryTagOutput): boolean {
  return value.primary === null && value.topics.length === 0;
}

function needsTagFallback(value: MediaSummaryTagOutput): boolean {
  return value.primary === null || isEmptySuggestedTags(value);
}

function mergeSuggestedTags(
  current: MediaSummaryTagOutput,
  fallback: MediaSummaryTagOutput,
): MediaSummaryTagOutput {
  return {
    primary: current.primary ?? fallback.primary,
    topics: current.topics.length > 0 ? current.topics : fallback.topics,
  };
}

function inferPrimaryTagSuggestion(transcriptText: string): MediaSummaryTagSuggestion | null {
  const text = transcriptText.normalize("NFKC").toLocaleLowerCase("zh-Hans-CN");

  if (!text.trim() || text.trim().length < 4) {
    return null;
  }

  if (/(学习|课程|知识|概念|公式|数学|物理|高斯|神经网络|大语言模型|llm|reinforcement|强化学习)/iu.test(text)) {
    return { name: "学习整理", confidence: 0.74 };
  }

  if (/(复盘|回顾|反思|面试完|开完会|运动完|康复完)/u.test(text)) {
    return { name: "复盘", confidence: 0.74 };
  }

  if (/(想法|应用|功能|设计|系统|界面|产品|需求|插件|标签|tag|颜色|调色盘|优化|改进|方案)/iu.test(text)) {
    return { name: "想法", confidence: 0.78 };
  }

  if (/(情绪|心情|开心|高兴|难受|焦虑|生气|压力|烦|沮丧|崩溃)/u.test(text)) {
    return { name: "情绪", confidence: 0.7 };
  }

  if (/(日记|今天|早上|中午|晚上|昨晚|一天|周末)/u.test(text)) {
    return { name: "日记", confidence: 0.66 };
  }

  if (/(测试|随便|碎碎念|牢骚)/u.test(text)) {
    return { name: "碎碎念", confidence: 0.64 };
  }

  return null;
}

function parseTagSuggestionArray(value: unknown, maxItems: number): MediaSummaryTagSuggestion[] {
  if (!Array.isArray(value)) {
    return [];
  }

  const result: MediaSummaryTagSuggestion[] = [];
  const seen = new Set<string>();
  for (const item of value) {
    if (result.length >= maxItems) {
      break;
    }

    const parsed = parseTagSuggestion(item);
    if (!parsed) {
      continue;
    }

    const key = parsed.name.normalize("NFKC").trim().toLocaleLowerCase("zh-Hans-CN");
    if (seen.has(key)) {
      continue;
    }

    seen.add(key);
    result.push(parsed);
  }

  return result;
}

function parseTagSuggestion(value: unknown): MediaSummaryTagSuggestion | null {
  if (!isRecord(value)) {
    return null;
  }

  const name = parseNonEmptyString(value.name ?? value.label ?? value.tag, 40);
  if (!name) {
    return null;
  }

  const confidence = typeof value.confidence === "number" ? value.confidence : 0.5;
  return {
    name,
    confidence: Math.max(0, Math.min(1, confidence)),
  };
}

function parseDocumentBlocks(value: unknown): MediaSummaryDocumentBlock[] | null {
  if (!Array.isArray(value) || value.length > 40) {
    return null;
  }

  const blocks: MediaSummaryDocumentBlock[] = [];
  for (const item of value) {
    if (!isRecord(item)) {
      return null;
    }

    const kind = parseBlockKind(item.kind ?? item.type);
    const level = parseBlockLevel(item.level, kind);
    const text = parseOptionalString(item.text ?? item.heading ?? item.title, 2_000) ?? "";
    const items = parseStringArray(item.items ?? item.bullets ?? item.points, 16, 1_000) ?? [];

    if (!kind || level === null) {
      return null;
    }

    if (kind === "heading" && !text) {
      return null;
    }

    if ((kind === "paragraph" || kind === "ai_suggested") && !text && items.length === 0) {
      return null;
    }

    if ((kind === "bullets" || kind === "numbered_list") && items.length === 0) {
      return null;
    }

    blocks.push({
      kind,
      level,
      text,
      items,
    });
  }

  return blocks;
}

function parseBlockKind(value: unknown): MediaSummaryDocumentBlockKind | null {
  if (typeof value !== "string") {
    return null;
  }

  const normalized = value.trim().toLowerCase().replaceAll("-", "_").replaceAll(" ", "_");
  if (normalized === "heading" || normalized === "title" || normalized === "section") {
    return "heading";
  }

  if (normalized === "paragraph" || normalized === "text") {
    return "paragraph";
  }

  if (normalized === "bullets" || normalized === "bullet_list" || normalized === "unordered_list") {
    return "bullets";
  }

  if (normalized === "numbered_list" || normalized === "ordered_list" || normalized === "steps") {
    return "numbered_list";
  }

  if (normalized === "ai_suggested" || normalized === "suggested" || normalized === "suggestions") {
    return "ai_suggested";
  }

  return null;
}

function parseBlockLevel(value: unknown, kind: MediaSummaryDocumentBlockKind | null): 0 | 1 | 2 | null {
  if (kind !== "heading") {
    return 0;
  }

  if (typeof value !== "number") {
    return 1;
  }

  if (value === 1 || value === 2) {
    return value;
  }

  return null;
}

function legacyShapeFromDocument(input: {
  oneLiner: string;
  documentBlocks: MediaSummaryDocumentBlock[];
}): { keyPoints: string[]; sections: MediaSummarySection[] } {
  const keyPoints: string[] = [];
  const sections: MediaSummarySection[] = [];
  let currentSection: MediaSummarySection | null = null;

  for (const block of input.documentBlocks) {
    if (block.kind === "heading") {
      currentSection = {
        heading: block.text,
        bullets: [],
      };
      sections.push(currentSection);
      continue;
    }

    const lines = block.items.length > 0 ? block.items : block.text ? [block.text] : [];
    if (lines.length === 0) {
      continue;
    }

    if (currentSection) {
      currentSection.bullets.push(...lines);
    } else {
      keyPoints.push(...lines);
    }
  }

  return {
    keyPoints: keyPoints.slice(0, 12),
    sections: sections
      .map((section) => ({
        heading: section.heading,
        bullets: section.bullets.slice(0, 12),
      }))
      .filter((section) => section.bullets.length > 0),
  };
}

function documentBlocksFromLegacyValue(value: Record<string, unknown>): MediaSummaryDocumentBlock[] {
  const blocks: MediaSummaryDocumentBlock[] = [];
  const keyPoints = parseStringArray(value.keyPoints ?? value.key_points ?? value.points, 12, 1_000) ?? [];
  if (keyPoints.length > 0) {
    blocks.push({
      kind: "bullets",
      level: 0,
      text: "",
      items: keyPoints,
    });
  }

  const sections = parseSections(value.sections ?? value.sectioned ?? value.details) ?? [];
  for (const section of sections) {
    blocks.push({
      kind: "heading",
      level: 1,
      text: section.heading,
      items: [],
    });
    blocks.push({
      kind: "bullets",
      level: 0,
      text: "",
      items: section.bullets,
    });
  }

  return blocks;
}

function parseSections(value: unknown): MediaSummarySection[] | null {
  if (!Array.isArray(value) || value.length > 12) {
    return null;
  }

  const sections: MediaSummarySection[] = [];
  for (const item of value) {
    if (!isRecord(item)) {
      return null;
    }

    const heading = parseNonEmptyString(item.heading, 200);
    const bullets =
      parseStringArray(item.bullets, 12, 1_000) ??
      parseBodyAsBullets(item.body, 12, 1_000);
    if (!heading || bullets === null) {
      return null;
    }

    sections.push({ heading, bullets });
  }

  return sections;
}

function parseBodyAsBullets(
  value: unknown,
  maxItems: number,
  maxLength: number,
): string[] | null {
  if (typeof value !== "string") {
    return null;
  }

  const lines = value
    .split(/\r?\n/)
    .map((line) => line.replace(/^[-*•]\s*/, "").trim())
    .filter((line) => line.length > 0)
    .slice(0, maxItems);

  if (lines.length === 0) {
    return null;
  }

  const parsed = lines
    .map((line) => parseNonEmptyString(line, maxLength))
    .filter((line): line is string => line !== null);
  return parsed.length > 0 ? parsed : null;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
