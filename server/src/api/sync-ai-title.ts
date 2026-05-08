const MAX_AI_TITLE_LENGTH = 40;

export function cleanedAITitle(value: string | null): string | null {
  if (!value) {
    return null;
  }

  const withoutMarker = value.replace(/^\s*#{1,6}\s*/u, "");
  const title = withoutMarker.replace(/\s+/gu, " ").trim();
  if (!title || Array.from(title).length > MAX_AI_TITLE_LENGTH) {
    return null;
  }

  return title;
}

export function hasLeadingMarkdownTitle(text: string): boolean {
  const lines = text.split(/\r?\n/u);
  for (const line of lines) {
    if (line.trim().length === 0) {
      continue;
    }

    return markdownHeadingText(line) !== null;
  }

  return false;
}

export function markdownHeadingText(line: string): string | null {
  let value: string | null = null;
  if (line.startsWith("## ")) {
    value = line.slice(3);
  } else if (line.startsWith("# ")) {
    value = line.slice(2);
  }

  if (value === null) {
    return null;
  }

  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

export function insertAITitleIntoText(title: string, text: string): string {
  const heading = `## ${title}`;
  if (text.trim().length === 0) {
    return heading;
  }

  return `${heading}\n\n${text}`;
}
