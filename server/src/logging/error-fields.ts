export function errorLogFields(error: unknown): Record<string, unknown> {
  if (error instanceof Error) {
    return {
      errorName: error.name,
      errorMessage: error.message,
      ...(typeof error.stack === "string" ? { errorStack: error.stack } : {}),
    };
  }

  return {
    errorMessage: String(error),
  };
}
