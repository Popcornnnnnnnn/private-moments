import { randomUUID } from "node:crypto";
import { access } from "node:fs/promises";
import path from "node:path";
import { setTimeout as sleep } from "node:timers/promises";

import type { AiSummary, Prisma, PrismaClient } from "@prisma/client";

import {
  AISummaryProviderError,
  generateMediaSummaryFromFile,
  MEDIA_SUMMARY_PROMPT_VERSION,
  summaryText,
  type AILanguagePreference,
  type MediaSummaryOutput,
  type MediaSummaryTopicTagHint,
} from "./media-summary.js";
import { recordAIUsageEvent } from "./usage-ledger.js";
import type { AppConfig } from "../config/app-config.js";
import type { FileLogger } from "../logging/file-logger.js";
import type { DataPaths } from "../storage/data-dir.js";
import { applyAITagsFromSummary } from "../tags/tagging.js";

export interface MediaSummaryJobContext {
  config: AppConfig;
  paths: DataPaths;
  prisma: PrismaClient;
  fileLogger: FileLogger;
}

export interface MediaSummaryJobInput {
  postId: string;
  mediaId: string;
  requestedByDeviceId: string | null;
  forceRegenerate?: boolean;
  aiLanguage?: AILanguagePreference;
}

const inFlightMediaSummaries = new Set<string>();
let mediaSummaryQueueTail: Promise<void> = Promise.resolve();
const MAX_GENERATION_ATTEMPTS = 2;
const SUMMARY_RETRY_DELAY_MS = 2_000;
const RETRYABLE_ERROR_CODES = new Set([
  "provider_timeout",
  "provider_request_failed",
  "transcription_timeout",
  "transcription_failed",
  "local_transcription_timeout",
  "audio_input_timeout",
  "audio_input_failed",
]);
type AITagApplicationResult = Awaited<ReturnType<typeof applyAITagsFromSummary>>;

export function enqueueMediaSummaryJob(
  context: MediaSummaryJobContext,
  input: MediaSummaryJobInput,
): void {
  if (inFlightMediaSummaries.has(input.mediaId)) {
    return;
  }

  inFlightMediaSummaries.add(input.mediaId);
  const runJob = async () => {
    try {
      await generateAndSaveMediaSummary(context, input);
    } catch (error: unknown) {
      await context.fileLogger.warn("ai.summary_job_failed", {
        postId: input.postId,
        mediaId: input.mediaId,
        message: error instanceof Error ? error.message : String(error),
      });
    } finally {
      inFlightMediaSummaries.delete(input.mediaId);
    }
  };

  mediaSummaryQueueTail = mediaSummaryQueueTail
    .catch(() => undefined)
    .then(runJob);
  void mediaSummaryQueueTail;
}

export async function generateAndSaveMediaSummary(
  context: MediaSummaryJobContext,
  input: MediaSummaryJobInput,
): Promise<AiSummary> {
  const jobStartedAt = Date.now();
  const media = await context.prisma.media.findUnique({
    where: {
      id: input.mediaId,
    },
    include: {
      post: true,
    },
  });

  if (!media || media.deletedAt || media.postId !== input.postId || media.post.deletedAt) {
    throw new AISummaryProviderError("media_not_found", "Media not found");
  }

  if (media.kind !== "audio" && media.kind !== "video") {
    throw new AISummaryProviderError("unsupported_media", "AI summaries are only available for audio or video media");
  }

  const existing = await context.prisma.aiSummary.findUnique({
    where: {
      mediaId: media.id,
    },
  });

  if (existing && !input.forceRegenerate && existing.deletedAt === null) {
    if (existing.status === "ready" || existing.status === "transcribing" || existing.status === "summarizing") {
      return existing;
    }
  }

  if (!media.compressedPath) {
    return saveAndLogSummaryFailure(context, {
      existingId: existing?.id,
      postId: media.postId,
      mediaId: media.id,
      deviceId: input.requestedByDeviceId,
      durationSeconds: media.durationSeconds,
      provider: context.config.aiSummary.provider,
      model: context.config.aiSummary.model,
      errorCode: "media_file_missing",
      errorMessage: "Media file is not available on the Mac server",
    });
  }

  const filePath = path.join(context.paths.dataDir, media.compressedPath);
  if (!isPathInside(context.paths.dataDir, filePath) || !(await fileExists(filePath))) {
    return saveAndLogSummaryFailure(context, {
      existingId: existing?.id,
      postId: media.postId,
      mediaId: media.id,
      deviceId: input.requestedByDeviceId,
      durationSeconds: media.durationSeconds,
      provider: context.config.aiSummary.provider,
      model: context.config.aiSummary.model,
      errorCode: "media_file_missing",
      errorMessage: "Media file is not available on the Mac server",
    });
  }

  const transcribing = await saveSummaryStatus(context.prisma, {
    existingId: existing?.id,
    postId: media.postId,
    mediaId: media.id,
    deviceId: input.requestedByDeviceId,
    durationSeconds: media.durationSeconds,
    provider: context.config.aiSummary.provider,
    model: context.config.aiSummary.model,
  });

  await context.fileLogger.info("ai.summary_started", {
    summaryId: transcribing.id,
    postId: media.postId,
    mediaId: media.id,
    stage: "transcribing",
    provider: context.config.aiSummary.provider,
    model: context.config.aiSummary.model,
    transcriptionProvider: context.config.aiSummary.transcriptionProvider,
    transcriptionModel: context.config.aiSummary.transcriptionModel,
    elapsedMs: Date.now() - jobStartedAt,
  });

  let transcriptReadyAt: number | null = null;
  try {
    const existingTopicTags = await loadExistingTopicTagHints(context.prisma);
    const output = await generateMediaSummaryFromFileWithRetry(context, {
      summaryId: transcribing.id,
      postId: media.postId,
      mediaId: media.id,
      jobStartedAt,
      getTranscriptReadyAt: () => transcriptReadyAt,
      onTranscriptReady: async () => {
        transcriptReadyAt = Date.now();
        await saveSummaryStage(context.prisma, transcribing.id, "summarizing");
        await context.fileLogger.info("ai.summary_stage", {
          summaryId: transcribing.id,
          postId: media.postId,
          mediaId: media.id,
          stage: "summarizing",
          elapsedMs: transcriptReadyAt - jobStartedAt,
          transcriptionMs: transcriptReadyAt - jobStartedAt,
        });
      },
      filePath,
      fileName: path.basename(filePath),
      mimeType: media.mimeType,
      durationSeconds: media.durationSeconds,
      aiLanguage: input.aiLanguage ?? "auto",
      existingTopicTags,
    });
    const readyResult = await saveSummaryReady(
      context.prisma,
      transcribing.id,
      output.summary,
      {
        transcriptHash: output.transcriptHash,
        transcriptLength: output.transcriptLength,
      },
      {
        mediaKind: media.kind,
        forceRegenerate: input.forceRegenerate === true,
      },
    );
    const ready = readyResult.summary;

    const completedAt = Date.now();
    await context.fileLogger.info("ai.summary_ready", {
      summaryId: ready.id,
      postId: ready.postId,
      mediaId: ready.mediaId,
      provider: ready.provider,
      model: ready.model,
      inputTranscriptLength: ready.inputTranscriptLength,
      elapsedMs: completedAt - jobStartedAt,
      transcriptionMs: transcriptReadyAt ? transcriptReadyAt - jobStartedAt : null,
      summarizationMs: transcriptReadyAt ? completedAt - transcriptReadyAt : null,
    });
    await logAITagResult(context.fileLogger, {
      summaryId: ready.id,
      postId: ready.postId,
      mediaId: ready.mediaId,
      mediaKind: media.kind,
      forceRegenerate: input.forceRegenerate === true,
      tagResult: readyResult.tagResult,
      output: output.summary,
    });

    return ready;
  } catch (error) {
    const providerError =
      error instanceof AISummaryProviderError
        ? error
        : new AISummaryProviderError("summary_failed", "AI summary failed");

    await context.fileLogger.warn("ai.summary_stage_failed", {
      summaryId: transcribing.id,
      postId: media.postId,
      mediaId: media.id,
      stage: transcriptReadyAt ? "summarizing" : "transcribing",
      elapsedMs: Date.now() - jobStartedAt,
      errorCode: providerError.code,
    });

    return saveAndLogSummaryFailure(context, {
      existingId: transcribing.id,
      postId: media.postId,
      mediaId: media.id,
      deviceId: input.requestedByDeviceId,
      durationSeconds: media.durationSeconds,
      provider: context.config.aiSummary.provider,
      model: context.config.aiSummary.model,
      errorCode: providerError.code,
      errorMessage: providerError.message,
    });
  }
}

interface GenerateMediaSummaryRetryInput {
  summaryId: string;
  postId: string;
  mediaId: string;
  jobStartedAt: number;
  getTranscriptReadyAt: () => number | null;
  onTranscriptReady: () => Promise<void>;
  filePath: string;
  fileName: string;
  mimeType: string | null;
  durationSeconds: number | null;
  aiLanguage: AILanguagePreference;
  existingTopicTags: MediaSummaryTopicTagHint[];
}

async function generateMediaSummaryFromFileWithRetry(
  context: MediaSummaryJobContext,
  input: GenerateMediaSummaryRetryInput,
): Promise<Awaited<ReturnType<typeof generateMediaSummaryFromFile>>> {
  for (let attempt = 1; attempt <= MAX_GENERATION_ATTEMPTS; attempt += 1) {
    try {
      await context.fileLogger.info("ai.summary_attempt_started", {
        summaryId: input.summaryId,
        postId: input.postId,
        mediaId: input.mediaId,
        attempt,
        maxAttempts: MAX_GENERATION_ATTEMPTS,
        stage: "transcribing",
        elapsedMs: Date.now() - input.jobStartedAt,
      });

      return await generateMediaSummaryFromFile(
        context.config.aiSummary,
        {
          filePath: input.filePath,
          fileName: input.fileName,
          mimeType: input.mimeType,
          durationSeconds: input.durationSeconds,
          aiLanguage: input.aiLanguage,
          existingTopicTags: input.existingTopicTags,
        },
        {
          onTranscriptReady: input.onTranscriptReady,
          usageContext: {
            feature: "media_summary",
            subjectType: "media",
            subjectId: input.mediaId,
            promptVersion: MEDIA_SUMMARY_PROMPT_VERSION,
            recorder: (event) => recordAIUsageEvent(context.prisma, event),
          },
        },
      );
    } catch (error) {
      const providerError =
        error instanceof AISummaryProviderError
          ? error
          : new AISummaryProviderError("summary_failed", "AI summary failed");
      const canRetry = attempt < MAX_GENERATION_ATTEMPTS && isRetryableErrorCode(providerError.code);

      if (!canRetry) {
        throw providerError;
      }

      await context.fileLogger.warn("ai.summary_retry_scheduled", {
        summaryId: input.summaryId,
        postId: input.postId,
        mediaId: input.mediaId,
        attempt,
        nextAttempt: attempt + 1,
        maxAttempts: MAX_GENERATION_ATTEMPTS,
        stage: input.getTranscriptReadyAt() ? "summarizing" : "transcribing",
        elapsedMs: Date.now() - input.jobStartedAt,
        errorCode: providerError.code,
      });
      await sleep(SUMMARY_RETRY_DELAY_MS);
    }
  }

  throw new AISummaryProviderError("summary_failed", "AI summary failed");
}

async function loadExistingTopicTagHints(
  prisma: PrismaClient,
): Promise<MediaSummaryTopicTagHint[]> {
  const topicTags = await prisma.tag.findMany({
    where: {
      type: "topic",
      isArchived: false,
    },
    include: {
      aliases: {
        where: {
          deletedAt: null,
        },
        orderBy: {
          alias: "asc",
        },
      },
    },
    orderBy: {
      name: "asc",
    },
  });

  return topicTags.map((tag) => ({
    name: tag.name,
    aliases: tag.aliases.map((alias) => alias.alias),
  }));
}

function isRetryableErrorCode(code: string): boolean {
  if (RETRYABLE_ERROR_CODES.has(code)) {
    return true;
  }

  return /^(provider|transcription|audio_input)_http_(429|5\d\d)$/.test(code);
}

interface SaveSummaryStatusInput {
  existingId: string | undefined;
  postId: string;
  mediaId: string;
  deviceId: string | null;
  durationSeconds: number | null;
  provider: string;
  model: string;
}

async function saveSummaryStatus(
  prisma: PrismaClient,
  input: SaveSummaryStatusInput,
): Promise<AiSummary> {
  return prisma.$transaction(async (tx) => {
    const summary = await tx.aiSummary.upsert({
      where: {
        mediaId: input.mediaId,
      },
      create: {
        id: input.existingId ?? randomUUID(),
        postId: input.postId,
        mediaId: input.mediaId,
        status: "transcribing",
        promptVersion: MEDIA_SUMMARY_PROMPT_VERSION,
        provider: input.provider,
        model: input.model,
        inputDurationSeconds: input.durationSeconds,
        requestedByDeviceId: input.deviceId,
        deletedAt: null,
      },
      update: {
        status: "transcribing",
        inputDurationSeconds: input.durationSeconds,
        promptVersion: MEDIA_SUMMARY_PROMPT_VERSION,
        provider: input.provider,
        model: input.model,
        errorCode: null,
        errorMessage: null,
        requestedByDeviceId: input.deviceId,
        deletedAt: null,
      },
    });

    await emitAISummaryChange(tx, summary, "ai_summary_updated");
    return summary;
  });
}

async function saveSummaryStage(
  prisma: PrismaClient,
  summaryId: string,
  status: "summarizing",
): Promise<AiSummary> {
  return prisma.$transaction(async (tx) => {
    const summary = await tx.aiSummary.update({
      where: {
        id: summaryId,
      },
      data: {
        status,
        errorCode: null,
        errorMessage: null,
      },
    });

    await emitAISummaryChange(tx, summary, "ai_summary_updated");
    return summary;
  });
}

async function saveSummaryReady(
  prisma: PrismaClient,
  summaryId: string,
  output: MediaSummaryOutput,
  transcriptStats: { transcriptHash: string | null; transcriptLength: number | null },
  tagInput: { mediaKind: string; forceRegenerate: boolean },
): Promise<{ summary: AiSummary; tagResult: AITagApplicationResult }> {
  return prisma.$transaction(async (tx) => {
    const summary = await tx.aiSummary.update({
      where: {
        id: summaryId,
      },
      data: {
        status: "ready",
        format: output.format,
        language: output.language,
        overview: output.overview,
        keyPointsJson: JSON.stringify(output.keyPoints),
        sectionsJson: JSON.stringify(output.sections),
        summaryText: summaryText(output),
        documentTitle: output.documentTitle,
        oneLiner: output.oneLiner,
        documentBlocksJson: JSON.stringify(output.documentBlocks),
        inputTranscriptHash: transcriptStats.transcriptHash,
        inputTranscriptLength: transcriptStats.transcriptLength,
        errorCode: null,
        errorMessage: null,
      },
    });

    await emitAISummaryChange(tx, summary, "ai_summary_updated");
    const tagResult = await applyAITagsFromSummary(tx, {
      postId: summary.postId,
      mediaKind: tagInput.mediaKind,
      summaryId: summary.id,
      output,
      forceRegenerate: tagInput.forceRegenerate,
    });
    return { summary, tagResult };
  });
}

async function logAITagResult(
  fileLogger: FileLogger,
  input: {
    summaryId: string;
    postId: string;
    mediaId: string;
    mediaKind: string;
    forceRegenerate: boolean;
    tagResult: AITagApplicationResult;
    output: MediaSummaryOutput;
  },
): Promise<void> {
  await fileLogger.info("ai.tags_processed", {
    summaryId: input.summaryId,
    postId: input.postId,
    mediaId: input.mediaId,
    mediaKind: input.mediaKind,
    forceRegenerate: input.forceRegenerate,
    appliedPrimary: input.tagResult.appliedPrimary,
    appliedTopics: input.tagResult.appliedTopics,
    primarySkippedReason: input.tagResult.primarySkippedReason,
    skippedReason: input.tagResult.skippedReason,
    suggestedPrimaryConfidence: input.output.suggestedTags.primary?.confidence ?? null,
    suggestedTopicCount: input.output.suggestedTags.topics.length,
    suggestedTopicConfidences: input.output.suggestedTags.topics.map((tag) => tag.confidence),
  });
}

interface SaveSummaryFailureInput {
  existingId: string | undefined;
  postId: string;
  mediaId: string;
  deviceId: string | null;
  durationSeconds: number | null;
  provider?: string;
  model?: string;
  errorCode: string;
  errorMessage: string;
}

async function saveAndLogSummaryFailure(
  context: MediaSummaryJobContext,
  input: SaveSummaryFailureInput,
): Promise<AiSummary> {
  const summary = await saveSummaryFailure(context.prisma, input);

  await context.fileLogger.warn("ai.summary_failed", {
    summaryId: summary.id,
    postId: summary.postId,
    mediaId: summary.mediaId,
    provider: summary.provider,
    model: summary.model,
    errorCode: summary.errorCode,
  });

  return summary;
}

async function saveSummaryFailure(
  prisma: PrismaClient,
  input: SaveSummaryFailureInput,
): Promise<AiSummary> {
  return prisma.$transaction(async (tx) => {
    const summary = await tx.aiSummary.upsert({
      where: {
        mediaId: input.mediaId,
      },
      create: {
        id: input.existingId ?? randomUUID(),
        postId: input.postId,
        mediaId: input.mediaId,
        status: "failed",
        promptVersion: MEDIA_SUMMARY_PROMPT_VERSION,
        inputDurationSeconds: input.durationSeconds,
        provider: input.provider ?? null,
        model: input.model ?? null,
        errorCode: input.errorCode,
        errorMessage: input.errorMessage,
        requestedByDeviceId: input.deviceId,
        deletedAt: null,
      },
      update: {
        status: "failed",
        inputDurationSeconds: input.durationSeconds,
        promptVersion: MEDIA_SUMMARY_PROMPT_VERSION,
        provider: input.provider ?? null,
        model: input.model ?? null,
        errorCode: input.errorCode,
        errorMessage: input.errorMessage,
        requestedByDeviceId: input.deviceId,
        deletedAt: null,
      },
    });

    await emitAISummaryChange(tx, summary, "ai_summary_updated");
    return summary;
  });
}

async function emitAISummaryChange(
  tx: Prisma.TransactionClient,
  summary: AiSummary,
  changeType: "ai_summary_updated" | "ai_summary_deleted",
): Promise<void> {
  const change = await tx.serverChange.create({
    data: {
      entityType: "ai_summary",
      entityId: summary.id,
      changeType,
      payloadJson: JSON.stringify(serializeAISummary(summary)),
    },
  });

  await tx.post.update({
    where: {
      id: summary.postId,
    },
    data: {
      serverVersion: change.version,
    },
  });
}

export function serializeAISummary(summary: AiSummary): Record<string, unknown> {
  return {
    id: summary.id,
    postId: summary.postId,
    mediaId: summary.mediaId,
    status: summary.status,
    format: summary.format,
    language: summary.language,
    overview: summary.overview,
    keyPoints: parseJsonArray(summary.keyPointsJson),
    sections: parseJsonArray(summary.sectionsJson),
    summaryText: summary.summaryText,
    documentTitle: summary.documentTitle,
    oneLiner: summary.oneLiner,
    documentBlocks: parseJsonArray(summary.documentBlocksJson),
    inputTranscriptLength: summary.inputTranscriptLength,
    inputDurationSeconds: summary.inputDurationSeconds,
    promptVersion: summary.promptVersion,
    provider: summary.provider,
    model: summary.model,
    errorCode: summary.errorCode,
    errorMessage: summary.errorMessage,
    createdAt: summary.createdAt.toISOString(),
    updatedAt: summary.updatedAt.toISOString(),
    deletedAt: summary.deletedAt?.toISOString() ?? null,
  };
}

function parseJsonArray(value: string): unknown[] {
  try {
    const parsed = JSON.parse(value) as unknown;
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}

async function fileExists(absolutePath: string): Promise<boolean> {
  try {
    await access(absolutePath);
    return true;
  } catch {
    return false;
  }
}

function isPathInside(parent: string, child: string): boolean {
  const relative = path.relative(parent, child);
  return Boolean(relative) && !relative.startsWith("..") && !path.isAbsolute(relative);
}
