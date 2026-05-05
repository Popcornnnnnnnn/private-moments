# M010: AI Periodic Reviews — Roadmap

## Goal

Deliver an extensible AI review system whose first artifact is a Weekly Review: a rolling seven-day, private, reflective review generated from moments, comments, ready audio/video summaries, and metadata.

## Slices

### S01 — Review Contract And Schema

**Status:** Implemented.

**Goal:** Add generic review persistence instead of a weekly-only table.

**Outcome:** Server has `reviews`, `review_feedback`, `review_memory`, and `review_settings`, with `kind`, `rangeMode`, `rangeStart`, `rangeEnd`, `trigger`, status, model/prompt metadata, generated content JSON, and optional publish linkage.

**Primary requirements:** R040, R041.

### S02 — Review Input Builder

**Status:** Implemented.

**Goal:** Build a privacy-conscious structured input pack from period data.

**Outcome:** Server gathers text moments, comments, ready audio/video AI summaries, tags, favorite, media kind, occurred time, and rhythm counts. Images are metadata-only in v1.

**Primary requirements:** R040, R042.

### S03 — Weekly Review Generator

**Status:** Implemented.

**Goal:** Generate structured Weekly Review JSON from a rolling seven-day input pack.

**Outcome:** `weekly-review-v1` asks for title, one-liner, keywords, themes, emotional reflection, progress/open loops, rhythm, notable moments, gentle suggestions, and uncertainty. It forbids per-claim evidence and allows moment IDs only for notable/review anchor output.

**Primary requirements:** R040, R043.

### S04 — Server APIs And Scheduler

**Status:** Implemented.

**Goal:** Expose review artifacts and default-off scheduled generation.

**Outcome:** APIs support list/get/generate/regenerate/feedback/publish/settings. Mac server scheduler checks Sunday evening local time and creates rolling-seven-day weekly reviews only when enabled.

**Primary requirements:** R041, R044.

### S05 — iOS Reviews UI

**Status:** Implemented.

**Goal:** Put Weekly Review under Calendar without changing Timeline semantics.

**Outcome:** Calendar has a low-noise Reviews toolbar entry. Reviews list supports manual generation and recent reviews. Detail renders structured sections and opens review anchors in a local moment preview sheet.

**Primary requirements:** R040, R045.

### S06 — Settings And Feedback

**Status:** Implemented.

**Goal:** Add default-off controls and feedback that feeds review memory.

**Outcome:** Settings exposes `Auto-generate Weekly Review` and `Publish Weekly Review to Moments`. Detail supports useful / too much inference / too dry / missed point / hide theme feedback.

**Primary requirements:** R044, R046.

### S07 — Verification And UAT

**Status:** Automated verification in progress; human UAT pending.

**Goal:** Prove compile/build/API basics and leave clear human test criteria.

**Outcome:** Required checks: Prisma generate/migrate, server typecheck/build, iOS generic build, HTTP smoke for review settings/list/generate failure or success path, and human review of generated tone/quality on real data.

**Primary requirements:** R001, R002, R003, R040-R046.
