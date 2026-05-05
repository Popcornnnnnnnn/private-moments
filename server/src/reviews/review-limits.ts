export const MAX_REVIEW_RANGE_DAYS = 35;
export const MAX_REVIEW_INPUT_MOMENTS = 240;

const MS_PER_DAY = 24 * 60 * 60 * 1000;

export class ReviewInputLimitError extends Error {
  readonly code = "review_input_too_large";

  constructor(message: string) {
    super(message);
    this.name = "ReviewInputLimitError";
  }
}

export function validateReviewRange(rangeStart: Date, rangeEnd: Date): string | null {
  if (rangeStart >= rangeEnd) {
    return "rangeStart must be before rangeEnd";
  }

  const rangeDays = (rangeEnd.getTime() - rangeStart.getTime()) / MS_PER_DAY;
  if (rangeDays > MAX_REVIEW_RANGE_DAYS) {
    return `Review range must be ${MAX_REVIEW_RANGE_DAYS} days or less`;
  }

  return null;
}

export function assertReviewMomentCount(count: number): void {
  if (count > MAX_REVIEW_INPUT_MOMENTS) {
    throw new ReviewInputLimitError(`Review input exceeds ${MAX_REVIEW_INPUT_MOMENTS} moments`);
  }
}
