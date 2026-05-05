export type AIUsageStatus = "success" | "failed";

export interface AIUsageEventInput {
  feature: string;
  subjectType: string;
  subjectId?: string | null;
  provider?: string | null;
  model?: string | null;
  promptVersion?: string | null;
  status: AIUsageStatus;
  inputChars?: number | null;
  outputChars?: number | null;
  inputTokens?: number | null;
  outputTokens?: number | null;
  totalTokens?: number | null;
  cachedInputTokens?: number | null;
  estimatedInputTokens?: number | null;
  estimatedOutputTokens?: number | null;
  estimatedTotalTokens?: number | null;
  durationMs?: number | null;
  errorCode?: string | null;
}

export type AIUsageRecorder = (event: AIUsageEventInput) => Promise<void> | void;

export interface AIUsageContext {
  feature: string;
  subjectType: string;
  subjectId?: string | null;
  promptVersion?: string | null;
  recorder?: AIUsageRecorder;
}

export interface ProviderTokenUsage {
  inputTokens: number | null;
  outputTokens: number | null;
  totalTokens: number | null;
  cachedInputTokens: number | null;
}

export function estimateTokensFromChars(characters: number | null | undefined): number | null {
  if (!characters || characters <= 0) {
    return null;
  }

  return Math.max(1, Math.ceil(characters / 3));
}

export function extractProviderTokenUsage(response: unknown): ProviderTokenUsage {
  const usage = isRecord(response) && isRecord(response.usage) ? response.usage : {};
  const inputTokens =
    readNumber(usage.prompt_tokens) ??
    readNumber(usage.input_tokens);
  const outputTokens =
    readNumber(usage.completion_tokens) ??
    readNumber(usage.output_tokens);
  const totalTokens =
    readNumber(usage.total_tokens) ??
    (inputTokens !== null && outputTokens !== null ? inputTokens + outputTokens : null);
  const cachedInputTokens =
    cachedTokensFromDetails(usage.prompt_tokens_details) ??
    cachedTokensFromDetails(usage.input_tokens_details) ??
    readNumber(usage.cached_tokens) ??
    readNumber(usage.cache_read_input_tokens);

  return {
    inputTokens,
    outputTokens,
    totalTokens,
    cachedInputTokens,
  };
}

export async function recordCompletionUsage(
  context: AIUsageContext | undefined,
  input: {
    provider: string;
    model: string;
    status: AIUsageStatus;
    inputChars: number;
    outputChars?: number | null;
    response?: unknown;
    durationMs: number;
    errorCode?: string | null;
  },
): Promise<void> {
  if (!context?.recorder) {
    return;
  }

  const usage = extractProviderTokenUsage(input.response);
  const estimatedInputTokens = estimateTokensFromChars(input.inputChars);
  const estimatedOutputTokens = estimateTokensFromChars(input.outputChars);
  const estimatedTotalTokens =
    estimatedInputTokens !== null || estimatedOutputTokens !== null
      ? (estimatedInputTokens ?? 0) + (estimatedOutputTokens ?? 0)
      : null;

  try {
    await context.recorder({
      feature: context.feature,
      subjectType: context.subjectType,
      subjectId: context.subjectId ?? null,
      provider: input.provider,
      model: input.model,
      promptVersion: context.promptVersion ?? null,
      status: input.status,
      inputChars: input.inputChars,
      outputChars: input.outputChars ?? null,
      inputTokens: usage.inputTokens,
      outputTokens: usage.outputTokens,
      totalTokens: usage.totalTokens,
      cachedInputTokens: usage.cachedInputTokens,
      estimatedInputTokens,
      estimatedOutputTokens,
      estimatedTotalTokens,
      durationMs: input.durationMs,
      errorCode: input.errorCode ?? null,
    });
  } catch {
    // Usage metering should never block the AI feature it observes.
  }
}

function cachedTokensFromDetails(value: unknown): number | null {
  if (!isRecord(value)) {
    return null;
  }

  return readNumber(value.cached_tokens) ?? readNumber(value.cached_input_tokens);
}

function readNumber(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? Math.max(0, Math.round(value)) : null;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
