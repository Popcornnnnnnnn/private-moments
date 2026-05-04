# M005: AI Media Summaries

**Gathered:** 2026-04-30
**Status:** Implemented; document-block summary rendering added; fresh real-device AI UAT pending
**Depends on:** M004 Audio and Video Moments, especially reliable audio/video upload to the Mac server. M004 real-device UAT should be closed or explicitly risk-accepted before implementation.

## Project Description

Add a quiet AI summarization layer for audio and video moments. The current version is server-side: after iOS uploads audio/video media, the Mac server transcribes the stored media file locally with `mlx-whisper`, summarizes the internal transcript through the configured summary API, stores generated summary metadata, and syncs the result back to iOS.

This milestone intentionally starts with utility. Later AI persona/reviewer/social-simulation ideas can build on the same AI artifact model, but they are out of scope for the first version.

## User-Visible Outcome

When this milestone is complete, the user can:

- See no Summary entry until the Mac has generated a ready summary.
- Tap `Summary ready` on an audio or video moment after the generated summary syncs back.
- Open a bottom sheet that shows only the ready AI summary rendered as native document blocks.
- Read a short top-level summary first, then expand detailed grouped sections when needed.
- Get a summary whose density adapts to transcript length and media duration:
  - very short media: one-liner plus minimal blocks;
  - medium media: one-liner plus key facts/reflections;
  - long media: one-liner plus grouped collapsible sections;
  - very long media: chunked processing with a concise top-level result and structured detail blocks.
- Regenerate, delete, or copy the summary from the bottom sheet.
- Keep the original moment text, comments, and media unchanged.

## Product Principles

- AI is a private organizing tool in this phase, not a visible social actor.
- AI never writes into the comment list and never changes the original post text.
- The main timeline remains quiet: generated content and transcript body text stay behind a button/status and a bottom sheet.
- AI calls may run automatically for newly uploaded audio/video media, but should not scan the whole archive in the background.
- Failures are lightweight status, not blocking alerts.
- API keys and external AI configuration live only on the Mac server.

## Scope

### In Scope

- Audio/video media summaries only.
- Summary input comes from server-side local transcription of the stored media file; transcript body is not returned to iOS.
- Mac server calls an external AI API for summary generation; local processing is limited to speech transcription.
- New server-side AI configuration through environment variables such as provider, model, API key, and optional base URL.
- Server-side persistent AI summary records with status, prompt version, provider, model, input length/hash metadata, error metadata, timestamps, and soft deletion.
- iOS local persistence for summary status/content so results are available after sync/restart.
- A server endpoint for requesting/regenerating/deleting a media summary.
- Server changes so summary create/update/delete state can recover through normal sync.
- A pull path for server-originated summary changes even when the iPhone has no pending outbox/upload work.
- A bottom sheet for ready summary display only.
- Summary copy/regenerate/delete actions.
- Logs and diagnostics that record IDs/statuses/lengths only, not private transcript or summary bodies.
- Focused eval/reference dataset for summary quality before calling the feature done.

### Out of Scope / Non-Goals

- AI comments in the feed.
- AI reviewer/persona/private-society behavior.
- Automatic background summarization.
- Direct iPhone calls to an external AI API.
- Local LLM deployment.
- Direct iPhone calls to transcription or summary providers.
- Full transcript reader redesign.
- AI-generated search embeddings, semantic search, fuzzy search, tagging automation, daily digests, or timeline-wide analysis.
- Admin UI content playback or AI content management beyond minimal diagnostics needed for operations.

## Architectural Decisions

- Use the Mac server as the only AI API caller.
- Treat AI outputs as generated metadata attached to media, not as comments or edited post text.
- Keep summary records separate from `media.transcription_text`; transcript is internal source material, summary is derived sync metadata.
- Prefer a small provider adapter over a heavyweight AI framework in the first version. This is a single structured-output content-generation call, not an agent or RAG system.
- Store prompt version and model/provider metadata with every result so future regenerations are explainable.
- New `media-summary-v2` records use `documentTitle`, `oneLiner`, and `documentBlocks` as the render source. Legacy `overview` / `keyPoints` / `sections` remain only for compatibility and copy text derivation.
- Make provider/model configurable through server `.env`; do not hard-code personal keys, base URLs, or models into reusable code or docs.
- Summaries should be idempotent at the request level where practical: repeated taps while a summary is pending should not create duplicate visible results.
- Summary failures should not mark media upload/sync as failed and should not block normal timeline use.

## Suggested Data Model

Server table candidate: `ai_summaries`

- `id`
- `post_id`
- `media_id`
- `kind` (`media_summary` in first version)
- `status` (`transcribing`, `summarizing`, `ready`, `failed`, `deleted`)
- `summary_json` or structured columns for overview/sections/key points
- `document_title`
- `one_liner`
- `document_blocks_json`
- `summary_text` optional denormalized plain text for copy/search if later needed
- `language`
- `input_transcript_hash`
- `input_transcript_length`
- `input_duration_seconds`
- `prompt_version`
- `provider`
- `model`
- `error_code`
- `error_message`
- `requested_by_device_id`
- `created_at`
- `updated_at`
- `deleted_at`

iOS table candidate: `local_ai_summaries` with the same stable IDs and local status/content fields.

## Suggested API / Sync Shape

API candidates:

- `POST /api/v1/ai/media-summary`
  - request: `{ postId, mediaId, forceRegenerate?: boolean }`
  - response: `202` with summary status or `200` with ready summary if completed inline
- `DELETE /api/v1/ai/media-summary/{summaryId}`
  - soft-deletes the generated summary

Server change candidates:

- `ai_summary_requested`
- `ai_summary_updated`
- `ai_summary_deleted`

The implementation may choose a synchronous first version if it remains responsive enough for personal use, but the contract should still store durable status and emit server changes so a disconnected iPhone can recover the result.

## Dynamic Summary Rules

Use server-side transcript character count as the primary signal and media duration as a secondary signal:

- Tiny: under roughly 300 transcript characters or under 60 seconds.
  - Output: one-liner plus minimal blocks.
- Short: roughly 300-1,500 characters.
  - Output: one-liner plus a short facts/reflections block.
- Medium: roughly 1,500-6,000 characters.
  - Output: one-liner plus grouped facts, reflections, and optional `AI suggested` next steps.
- Long: roughly 6,000-18,000 characters.
  - Output: one-liner plus several collapsible section groups.
- Very long: over roughly 18,000 characters.
  - Output: chunk, summarize chunks, then synthesize a top-level one-liner and document blocks.

The exact thresholds can shift during implementation, but output density must scale with content length and stay readable in the bottom sheet.

## Failure Semantics

- Missing media file, empty transcript, provider/network failure, or invalid output: store failed summary metadata for diagnostics, but do not show timeline Summary UI unless a ready summary exists.
- AI not configured: store lightweight failure metadata; do not block media upload.
- Output validation failure: retry once with a stricter repair prompt, then mark failed.
- Token/context limit: chunk and summarize if possible; otherwise mark failed with a lightweight status.

## Security And Privacy

- Keep the selected uploaded media file on the Mac for local transcription, and send only the resulting transcript to the summary provider.
- Do not return transcript body to iOS.
- Do not log transcript text, post text, comments, or summary body.
- Do not expose provider API key to iOS or Admin UI.
- Server logs may include media ID, summary ID, status, provider, model, duration, input length, and error code.
- Reusable docs must not contain real API keys or personal endpoint values.

## High-Risk Areas

- Introducing external API calls into a local-first private product.
- SQLite/server schema migration and sync recovery for generated AI artifacts.
- Avoiding leaks through logs, Admin diagnostics, errors, or request traces.
- Keeping the timeline quiet while still making the feature discoverable.
- Handling long media/transcripts without blocking the sync pipeline or creating duplicate summaries.
- Ensuring AI output is grounded in transcript text and does not invent content.
- Ensuring fresh audio/video uploads produce useful ready summaries through the Mac-local transcription pipeline and render correctly on the paired iPhone.

## Final Integrated Acceptance

To call this milestone complete, prove:

- A clear-speech audio moment uploaded from iOS triggers Mac server summary generation and syncs back `Summary ready`.
- A clear-speech video moment uploaded from iOS triggers Mac server summary generation and syncs back `Summary ready`.
- The timeline shows no Summary UI until ready, and never shows full summary or transcript text inline.
- `Summary ready` opens a bottom sheet with the full adaptive summary.
- New ready summaries render with title, one-liner, at most two heading levels, default-collapsed details, list blocks, and clearly labeled `AI suggested` callouts.
- Regenerate replaces the previous generated result with new metadata and preserves the original post/media.
- Delete summary removes/hides only the AI summary, not the media, transcript, post, or comments.
- Missing media, empty transcript, no-speech, and provider failures do not show intrusive alerts or block media/post sync.
- Provider failures show lightweight retryable state and do not poison media/post sync.
- API key stays on the server and transcript/summary bodies do not appear in normal logs.
- A device reinstall or local DB recovery can pull ready summary state from the server.
- A paired iPhone with stale `lastSyncCursor` can pull server-only `ai_summary_updated` changes and update `local_ai_summaries` without requiring new local content.
- Evaluation examples cover short, medium, long, no-speech, mixed-language, and rambling media/transcripts.

## Open Questions

- Exact provider and model names are intentionally not locked in this discussion. Implementation should choose from current official provider docs and keep it server-configurable.
- Whether AI summaries should participate in search is deferred. The first version should not expand search unless the user explicitly wants generated text searchable.
- Whether Admin should show AI summary diagnostics beyond counts/status is deferred.
