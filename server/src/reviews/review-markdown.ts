import type { Review } from "@prisma/client";

import type { ReviewOutput } from "../ai/review-generation.js";

export function reviewToMarkdown(content: ReviewOutput, review: Review): string {
  const lines = [
    `# ${content.title || "Weekly Review"}`,
    "",
    content.oneLiner,
    "",
    `Range: ${review.rangeStart.toISOString().slice(0, 10)} to ${review.rangeEnd.toISOString().slice(0, 10)}`,
    "",
    "## Keywords",
    ...content.keywords.map((keyword) => `- ${keyword.label}: ${keyword.note}`),
    "",
    "## Themes",
    ...content.themes.map((theme) => `- ${theme.title}: ${theme.body}`),
    "",
    "## Reflection",
    content.emotionalReflection.body,
    "",
    "## Progress",
    ...content.progressAndOpenLoops.progress.map((item) => `- ${item}`),
    "",
    "## Open loops",
    ...content.progressAndOpenLoops.openLoops.map((item) => `- ${item}`),
  ];

  return lines.filter((line, index, all) => line.length > 0 || all[index - 1]?.length).join("\n");
}
