# AI-SPEC — M005: AI Media Summaries

> AI design contract for the planned M005 milestone. This is a lightweight, project-specific version of the GSD AI integration contract because the first feature is a single server-side content-generation call, not an agent, RAG system, or multi-step autonomous workflow.

## 1. System Classification

**System Type:** Content generation with structured output.

**Description:** The Mac server summarizes one audio/video moment by transcribing the uploaded media file locally with `mlx-whisper`, then sending the internal transcript to an external summary API. Good output is grounded in the transcript, appropriately concise for the input length, readable in Chinese/English as the media warrants, and useful as a memory aid without pretending to know anything outside the input.

**Critical Failure Modes:**

1. Sending private media/transcript content beyond the selected uploaded media item.
2. Logging or exposing transcript/summary bodies through server logs, Admin diagnostics, errors, or reusable docs.
3. Inventing facts, actions, emotions, or conclusions not supported by the transcript.
4. Blocking or corrupting normal post/media/comment sync when the AI provider fails.
5. Cluttering the main timeline with generated content.
6. Generating a ready summary on Mac but leaving iPhone stale because no local pending work triggers a sync pull.

## 1b. Domain Context

**Domain:** Private personal timeline / voice memo organization.

**User Population:** Single owner of the local-first Moments app.

**Stakes Level:** Medium. The output is not medical/legal/financial advice, but it summarizes private personal material and can distort memory if it invents content.

**Output Consequence:** The summary helps the user understand and revisit a voice/video note. It should not overwrite original data or become the source of truth.

### What Good Looks Like

| Dimension | Good | Bad | Stakes |
|---|---|---|---|
| Grounding | Only summarizes what is present in the transcript; uncertainty stays modest. | Adds unsupported events, opinions, or conclusions. | Distorts private memory. |
| Density | Short notes get short summaries; long notes get structured summaries. | Every note gets the same template regardless of length. | Makes the feature feel noisy or useless. |
| Tone | Quiet, practical, non-judgmental. | Sounds like public social feedback, praise, scolding, or therapy. | Breaks the product's no-audience feel. |
| Language | Follows the transcript's dominant language; Chinese summaries should read naturally. | Forced English, awkward translation, or mixed language without reason. | Reduces usefulness. |
| Boundaries | Shows only `Summary ready` in the timeline and keeps generated output in the bottom sheet. | Pushes AI content into comments, replaces post text, or shows transcript/status placeholders in the timeline. | Clutters the timeline. |

### Known Failure Modes

- Hallucinated tasks or interpretations from rambling speech.
- Over-compressing long audio into a bland sentence.
- Over-structuring a tiny clip into fake sections.
- Treating transcription errors as reliable facts.
- Leaking private bodies through convenience logging.

## 2. Framework Decision

**Selected Approach:** Direct server-side provider adapter in TypeScript.

**Rationale:** M005 is a small server-owned media understanding pipeline: local Mac transcription followed by structured-output summary. A large agent framework would add state and abstraction that the product does not need yet. The server already owns auth, SQLite, sync, logs, and media storage, so a small adapter fits the current architecture.

**Implemented Path:** `server/src/ai/media-summary.ts` shells out to `server/scripts/local-transcribe.py` with the configured `mlx-whisper` model, then calls Chat Completions with structured JSON output, `store: false`, timeout handling, and local validation before persistence. `server/src/ai/media-summary-service.ts` owns persistence, `transcribing` / `summarizing` / `ready` / `failed` state changes, failure metadata, server changes, and upload-triggered background jobs.

**Alternatives Considered:**

| Alternative | Ruled Out Because |
|---|---|
| iPhone direct provider SDK | Exposes API key and duplicates retry/privacy handling in the client. |
| Local LLM on Mac | Summary generation should stay on an external API for now; local Mac work is limited to speech transcription. |
| Agent framework | First version has no tools, planning, memory, or handoffs. |
| RAG framework | Summary input is one uploaded media item / transcript, not a retrieved document corpus. |

**Vendor Lock-In:** Partial and acceptable for first version. Provider/model are server-configurable, but output quality and API behavior will depend on the selected external provider.

## 3. Implementation Guidance

### Server Boundary

- Add a dedicated `server/src/ai/` area for provider adapter, prompt construction, output validation, and summary service logic.
- Keep API key and provider config in `server/.env`.
- Do not include provider keys in iOS settings, shared docs, or Admin UI.
- Prefer structured JSON output validated by TypeScript code before persisting.
- Current env defaults: `AI_SUMMARY_PROVIDER=openai`, `AI_SUMMARY_BASE_URL=https://api.openai.com/v1`, `AI_SUMMARY_MODEL=gpt-4o-mini`, `AI_TRANSCRIPTION_PROVIDER=local`, `AI_LOCAL_TRANSCRIPTION_PYTHON=./.venv/bin/python`, `AI_LOCAL_TRANSCRIPTION_SCRIPT=./scripts/local-transcribe.py`, `AI_LOCAL_TRANSCRIPTION_MODEL=mlx-community/whisper-turbo`, `AI_LOCAL_TRANSCRIPTION_TIMEOUT_MS=600000`, `AI_SUMMARY_TIMEOUT_MS=60000`.

### Candidate Output Shape

```ts
type MediaSummaryOutput = {
  format: "document";
  language: "zh" | "en" | "mixed" | "unknown";
  documentTitle: string | null;
  oneLiner: string;
  documentBlocks: Array<{
    kind: "heading" | "paragraph" | "bullets" | "numbered_list" | "ai_suggested";
    level: 0 | 1 | 2;
    text: string;
    items: string[];
  }>;
  overview: string; // legacy compatibility
  keyPoints: string[]; // legacy compatibility
  sections: Array<{ heading: string; bullets: string[] }>; // legacy compatibility
};
```

Rules:

- `oneLiner` is required and non-empty.
- `documentBlocks` is the source of truth for new `media-summary-v2` rendering.
- Use at most two heading levels.
- Separate objective facts from speaker reflections when the transcript supports that distinction.
- Put inferred next steps only in `ai_suggested` blocks, labeled as suggestions rather than facts.
- Keep `overview`, `keyPoints`, and `sections` available for old clients and copy/search-neutral compatibility; summary text still does not participate in search.

### Prompt Discipline

- System prompt: define the product role, privacy tone, grounding rule, language behavior, and output schema.
- User prompt: include only server-side transcript text plus media duration and optional moment text if intentionally allowed later. Do not include original post text or comments in the first version.
- First version should use server-side transcript text or selected media audio only for summary generation. Adding original post text as extra context can be evaluated later.
- Store `promptVersion` with every summary.

### Context Strategy

- Use direct single-call summary for transcripts that fit the provider context comfortably.
- For long transcripts, chunk by transcript boundaries when available, otherwise by character/token budget.
- Summarize chunks first, then synthesize final output from chunk summaries.
- Never drop the user's original transcript; summary is derived metadata only.

### Error Handling

- Validate provider configuration before enabling the button.
- Retry transient provider failures sparingly; do not create automatic cost loops.
- If provider output fails schema validation, attempt one repair call or mark `failed`.
- Convert all AI errors into lightweight status for iOS.

## 4. Evaluation Strategy

### Dimensions

| Dimension | Rubric | Measurement Approach | Priority |
|---|---|---|---|
| Output schema validity | Parses as the required structure; required fields present and length-bounded. | Code-based validator | Critical |
| Grounding | No claims that are unsupported by transcript. | Human review first; optional LLM judge later | Critical |
| Adaptive density | Short/medium/long transcripts produce appropriately different structures. | Code + human review | High |
| Tone fit | Quiet, useful, non-social, non-judgmental. | Human review | High |
| Privacy/log safety | Logs contain no transcript/summary body. | Code/log inspection | Critical |
| Failure isolation | Provider failure does not break post/media sync. | Integration tests | Critical |

### Reference Dataset

Start with 12-20 examples:

- 3 very short clips.
- 3 medium voice notes.
- 3 long rambling notes.
- 2 mixed Chinese/English clips.
- 2 no-speech or unusable transcript cases.
- 2 transcripts with obvious recognition errors.
- 1 video transcript with visual context intentionally absent, to verify the AI does not infer from video content.

Labeling is human review by the project owner. The initial pass does not need an LLM judge until the output format stabilizes.

## 5. Guardrails

### Online

| Guardrail | Trigger | Intervention |
|---|---|---|
| Missing media/transcript | Media file missing, transcription fails, or transcript empty | Store failed summary metadata; show no timeline Summary UI unless ready. |
| Local transcription unavailable | Missing `.venv`, `mlx-whisper`, script, model, or source media file | Store failed metadata with `local_transcription_*`; show no timeline Summary UI. |
| Summary API failure | Provider timeout, HTTP error, invalid JSON, or invalid schema | Store failed metadata with provider error code; show no timeline Summary UI. |
| Provider not configured | Missing API key/model/provider | Disable or return `AI not configured`. |
| Output validation failure | Provider response fails schema | One repair attempt, then mark `failed`. |
| Oversized input | Transcript exceeds direct context budget | Chunk summarization or fail gracefully. |
| Client cursor stale | Server has newer `ai_summary_updated` changes than iPhone `lastSyncCursor` | Trigger foreground/manual diagnostic sync; surface the mismatch in Settings-level troubleshooting, not Timeline. |
| Private body logging | Any code path attempts to log transcript/summary | Treat as a blocker in code review/testing. |

### Offline / Flywheel

| Metric | Sampling Strategy | Action |
|---|---|---|
| User regenerates repeatedly | Track regenerate count per summary | Inspect prompt/quality problem. |
| Summary failed rate | Aggregate by provider/model/error code | Adjust retry/config or surface setup issue. |
| Long-summary latency | Track duration without bodies | Tune chunking/model. |
| Human quality notes | Manual review of reference set | Update prompt/eval examples. |

## 6. Production Monitoring

**Tracing default:** Do not add hosted tracing in the first version because transcript content is private. Use local structured logs with IDs/statuses/lengths only.

**Track:**

- Summary request count.
- Ready/failed/deleted counts.
- Provider/model/promptVersion.
- Input transcript length bucket.
- Transcription model/error bucket.
- Latency and error code.
- Client/server cursor mismatch when investigating missing summaries.

**Never track in logs:**

- Transcript body.
- Summary body.
- Original post text.
- Comment text.

## Checklist

- [x] System type classified.
- [x] Critical failure modes identified.
- [x] Domain context documented.
- [x] Framework/approach selected.
- [x] Structured output shape proposed.
- [x] Prompt/context strategy documented.
- [x] Evaluation dimensions defined.
- [x] Reference dataset specified.
- [x] Online guardrails defined.
- [x] Production monitoring boundaries defined.
