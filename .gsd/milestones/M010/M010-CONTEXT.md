# M010: AI Periodic Reviews

**Gathered:** 2026-05-05
**Status:** Implementation pass complete; verification and human UAT pending
**Depends on:** iOS Calendar Review, Timeline local data, comments, tags, server-side AI media summaries, Mac server AI provider config, Prisma/SQLite schema, auth, sync, and Settings feature toggles.

## Project Description

M010 adds a general AI review system. The first delivered review kind is `Weekly Review`, but data model, API, and UI vocabulary use generic `Review` / `Review Artifact` concepts so monthly or custom-range reviews can be added later.

Weekly Review is a private retrospective artifact. It is not a moment by default and it does not appear in Timeline unless the user explicitly publishes it as a moment. Its product role is to understand a rolling seven-day stream of moments, extract themes and keywords, describe time rhythm, offer calm observation plus moderate encouragement, and surface a few quiet anchors back to original moments.

## Root Decision

Weekly Review should be retrospective first and reflective second:

- It is not a task manager, KPI report, therapist, or evidence-based audit of individual moments.
- AI should read the week as a whole. It should not attach evidence to every judgment.
- Only the `Worth Revisiting` / `Review Anchors` section may link to source moments.
- Moment anchors open inside the review context rather than jumping to Timeline or changing Timeline filters.
- Tone is calm observation plus moderate encouragement.

## User-Visible Outcome

The user can:

- Open `Calendar -> Reviews`.
- Generate a rolling seven-day Weekly Review manually.
- See recent Weekly Reviews.
- Read structured sections: title, one-liner, keywords, themes, state response, progress/open loops, rhythm, worth revisiting, gentle suggestions, and uncertainty.
- Regenerate a review without overwriting the old ready artifact until the new call completes.
- Send lightweight feedback such as useful, too much inference, too dry, missed the point, or hide this theme.
- Optionally publish a ready review as a normal moment.
- Enable server-side Sunday-evening automatic Weekly Review generation in Settings. This default is off and does not notify or publish.

## Product Boundaries

### In Scope

- Generic server `reviews` table with period kind/range fields.
- `review_feedback`, `review_memory`, and `review_settings` foundations.
- Rolling-seven-day manual generation.
- Sunday-evening scheduled rolling-seven-day generation when enabled.
- Review input from text moments, comments, ready audio/video AI summaries, tags, favorite, media kind, and occurred time.
- Image moments as metadata/statistical signals only; no first-version visual understanding.
- Structured JSON output rendered by iOS.
- Hidden review anchors only under `Worth Revisiting`.
- Optional publish-as-moment action.

### Out Of Scope

- Automatic notifications.
- Default Timeline insertion.
- Image understanding/OCR.
- Full review version history UI.
- Monthly/custom reviews in first implementation, beyond data/API extensibility.
- Per-claim evidence links or evidence-bound AI reasoning.
- Psychological diagnosis or prescriptive coaching.

## Technical Shape

- Server owns review generation and scheduled jobs.
- iOS calls review APIs directly; review artifacts are not part of local-first sync in v1.
- The server stores generated review content as structured JSON in `reviews.content_json`.
- Review memory is explicit and coarse: feedback counters and latest feedback context. It must not store private post/comment/transcript bodies.
- Auto-generation uses Mac server local time: Sunday evening at or after 21:00. It records `last_auto_weekly_date` to avoid duplicate runs on the same local Sunday.
- Publishing a review creates a normal server post with a `post_created` server change so iOS can pull it by normal sync.

## Completion Bar

- Prisma schema/migration compiles and deploys.
- Server typecheck/build pass.
- iOS build passes.
- Review routes support list, get, generate, regenerate, feedback, publish, and settings.
- Calendar has a Reviews entry and review detail page.
- Settings exposes auto-generate and publish-to-moments toggles, both default off.
- Logs and job metadata avoid private body content.
- Human UAT can manually generate a review from real data and judge tone/structure.
