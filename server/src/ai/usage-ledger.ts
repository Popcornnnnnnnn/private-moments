import type { AiUsageEvent, PrismaClient } from "@prisma/client";

import type { AIUsageEventInput } from "./usage.js";

export interface AIUsageWindowDiagnostics {
  requests: number;
  successfulRequests: number;
  failedRequests: number;
  totalTokens: number;
  inputTokens: number;
  outputTokens: number;
  cachedInputTokens: number;
  estimatedRequests: number;
}

export interface AIUsageFeatureDiagnostics extends AIUsageWindowDiagnostics {
  feature: string;
}

export interface AIUsageDiagnostics {
  today: AIUsageWindowDiagnostics;
  currentWeek: AIUsageWindowDiagnostics;
  currentMonth: AIUsageWindowDiagnostics;
  allTime: AIUsageWindowDiagnostics;
  byFeatureCurrentMonth: AIUsageFeatureDiagnostics[];
  recentFailures: Array<{
    id: string;
    feature: string;
    subjectType: string;
    subjectId: string | null;
    provider: string | null;
    model: string | null;
    errorCode: string | null;
    createdAt: string;
  }>;
}

export async function recordAIUsageEvent(
  prisma: PrismaClient,
  input: AIUsageEventInput,
): Promise<void> {
  await prisma.aiUsageEvent.create({
    data: {
      feature: input.feature,
      subjectType: input.subjectType,
      subjectId: input.subjectId ?? null,
      provider: input.provider ?? null,
      model: input.model ?? null,
      promptVersion: input.promptVersion ?? null,
      status: input.status,
      inputChars: integerOrNull(input.inputChars),
      outputChars: integerOrNull(input.outputChars),
      inputTokens: integerOrNull(input.inputTokens),
      outputTokens: integerOrNull(input.outputTokens),
      totalTokens: integerOrNull(input.totalTokens),
      cachedInputTokens: integerOrNull(input.cachedInputTokens),
      estimatedInputTokens: integerOrNull(input.estimatedInputTokens),
      estimatedOutputTokens: integerOrNull(input.estimatedOutputTokens),
      estimatedTotalTokens: integerOrNull(input.estimatedTotalTokens),
      durationMs: integerOrNull(input.durationMs),
      errorCode: input.errorCode ?? null,
    },
  });
}

export async function collectAIUsageDiagnostics(
  prisma: PrismaClient,
  now = new Date(),
): Promise<AIUsageDiagnostics> {
  const todayStart = startOfDay(now);
  const weekStart = startOfCalendarWeek(now);
  const monthStart = startOfMonth(now);

  const [todayEvents, weekEvents, monthEvents, allEvents, recentFailures] = await Promise.all([
    usageEventsSince(prisma, todayStart),
    usageEventsSince(prisma, weekStart),
    usageEventsSince(prisma, monthStart),
    usageEventsSince(prisma, null),
    prisma.aiUsageEvent.findMany({
      where: {
        status: "failed",
      },
      orderBy: {
        createdAt: "desc",
      },
      take: 5,
    }),
  ]);

  return {
    today: summarizeUsageWindow(todayEvents),
    currentWeek: summarizeUsageWindow(weekEvents),
    currentMonth: summarizeUsageWindow(monthEvents),
    allTime: summarizeUsageWindow(allEvents),
    byFeatureCurrentMonth: summarizeByFeature(monthEvents),
    recentFailures: recentFailures.map((event) => ({
      id: event.id,
      feature: event.feature,
      subjectType: event.subjectType,
      subjectId: event.subjectId,
      provider: event.provider,
      model: event.model,
      errorCode: event.errorCode,
      createdAt: event.createdAt.toISOString(),
    })),
  };
}

async function usageEventsSince(
  prisma: PrismaClient,
  since: Date | null,
): Promise<AiUsageEvent[]> {
  return prisma.aiUsageEvent.findMany({
    where: since
      ? {
          createdAt: {
            gte: since,
          },
        }
      : undefined,
  });
}

function summarizeByFeature(events: AiUsageEvent[]): AIUsageFeatureDiagnostics[] {
  const groups = new Map<string, AiUsageEvent[]>();
  for (const event of events) {
    groups.set(event.feature, [...(groups.get(event.feature) ?? []), event]);
  }

  return [...groups.entries()]
    .map(([feature, featureEvents]) => ({
      feature,
      ...summarizeUsageWindow(featureEvents),
    }))
    .sort((lhs, rhs) => rhs.totalTokens - lhs.totalTokens);
}

function summarizeUsageWindow(events: AiUsageEvent[]): AIUsageWindowDiagnostics {
  return events.reduce<AIUsageWindowDiagnostics>(
    (summary, event) => {
      summary.requests += 1;
      if (event.status === "success") {
        summary.successfulRequests += 1;
      } else if (event.status === "failed") {
        summary.failedRequests += 1;
      }

      summary.inputTokens += event.inputTokens ?? event.estimatedInputTokens ?? 0;
      summary.outputTokens += event.outputTokens ?? event.estimatedOutputTokens ?? 0;
      summary.totalTokens += event.totalTokens ?? event.estimatedTotalTokens ?? 0;
      summary.cachedInputTokens += event.cachedInputTokens ?? 0;
      if (event.totalTokens === null) {
        summary.estimatedRequests += 1;
      }

      return summary;
    },
    emptyWindow(),
  );
}

function emptyWindow(): AIUsageWindowDiagnostics {
  return {
    requests: 0,
    successfulRequests: 0,
    failedRequests: 0,
    totalTokens: 0,
    inputTokens: 0,
    outputTokens: 0,
    cachedInputTokens: 0,
    estimatedRequests: 0,
  };
}

function startOfDay(date: Date): Date {
  return new Date(date.getFullYear(), date.getMonth(), date.getDate());
}

function startOfCalendarWeek(date: Date): Date {
  const start = startOfDay(date);
  const day = start.getDay();
  const mondayOffset = day === 0 ? -6 : 1 - day;
  start.setDate(start.getDate() + mondayOffset);
  return start;
}

function startOfMonth(date: Date): Date {
  return new Date(date.getFullYear(), date.getMonth(), 1);
}

function integerOrNull(value: number | null | undefined): number | null {
  return typeof value === "number" && Number.isFinite(value) ? Math.max(0, Math.round(value)) : null;
}
