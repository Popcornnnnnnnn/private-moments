# Requirements

This file is the explicit capability and coverage contract for the project.

## Active

### R040 — AI Periodic Reviews must be generic review artifacts, with Weekly Review as the first period kind.
- Class: functional
- Status: active
- Description: The system stores and renders AI-generated Review artifacts using generic kind/range fields instead of a weekly-only model. Weekly Review is the first implementation and must leave room for monthly/custom range reviews.
- Why it matters: The user expects future monthly or longer-range summaries; hard-coding week semantics into the data model would force a later rewrite.
- Source: M010 discussion 2026-05-05
- Primary owning slice: M010/S01
- Validation: Schema/API use `reviews.kind`, `rangeMode`, `rangeStart`, and `rangeEnd`; iOS copy can say Weekly Review while server data remains period-generic.

### R041 — Weekly Review generation uses rolling seven-day ranges for both manual and scheduled generation.
- Class: functional
- Status: active
- Description: Manual generation summarizes the seven days before trigger time. Scheduled generation is optional, default off, runs Sunday evening on the Mac server, summarizes the previous seven days, and does not notify or publish.
- Why it matters: The user wants manual review at arbitrary points and a quiet automatic background option.
- Source: M010 discussion 2026-05-05
- Primary owning slice: M010/S04
- Validation: API accepts explicit ranges but defaults to rolling seven days; scheduler checks Sunday evening and `autoWeeklyEnabled`; settings default off.

### R042 — Review input uses text, comments, ready media summaries, and metadata while keeping image analysis out of v1.
- Class: functional
- Status: active
- Description: Weekly Review input includes post text, comments, ready audio/video AI Summary metadata, tags, favorite, media kind, occurred time, and rhythm statistics. Image content is not visually analyzed in v1.
- Why it matters: The first useful input set is already available and privacy/logging risk stays lower without image understanding.
- Source: M010 discussion 2026-05-05
- Primary owning slice: M010/S02
- Validation: Server input builder includes these fields and does not call image OCR/vision APIs.

### R043 — Review content should read the week as a whole and avoid per-claim evidence binding.
- Class: constraint
- Status: active
- Description: Themes, keywords, state response, progress, and rhythm should be generated from whole-period understanding. Only the `Worth Revisiting` section may include moment IDs as low-weight review anchors.
- Why it matters: Per-claim evidence would encourage over-reading isolated moments and make the review feel like an audit.
- Source: M010 discussion 2026-05-05
- Primary owning slice: M010/S03
- Validation: Prompt/schema only exposes `momentIds` under `notableMoments`; iOS only renders anchors in `Worth Revisiting`.

### R044 — Review settings and feedback must be explicit, visible, and non-invasive.
- Class: functional
- Status: active
- Description: Auto-generation and publish-to-moments controls default off. Feedback can mark a review useful, too inferential, too dry, missing the point, or hiding a theme, and updates review memory without changing original moments.
- Why it matters: Self-learning should remain under user control and not feel like hidden surveillance.
- Source: M010 discussion 2026-05-05
- Primary owning slice: M010/S06
- Validation: Settings toggles default false; feedback writes review feedback/memory records and does not mutate posts/comments.

### R045 — Weekly Review belongs in Calendar Reviews and keeps interactions inside the review context.
- Class: functional
- Status: active
- Description: Calendar exposes Reviews as a quiet review/navigation surface. Moment anchors open in a local preview/detail sheet within the Review flow rather than jumping to Timeline or applying Timeline filters.
- Why it matters: Weekly Review is a review artifact, not a feed item or Timeline filter mode.
- Source: M010 discussion 2026-05-05
- Primary owning slice: M010/S05
- Validation: Calendar has a Reviews entry; anchors in review detail present local moment preview and do not call the Calendar-to-Timeline route.

### R046 — Publish-as-moment must be explicit and never automatic by default.
- Class: constraint
- Status: active
- Description: A ready review may be published as a normal moment only through explicit user action or a future enabled setting. Default behavior is hidden/unpublished review artifacts.
- Why it matters: AI-generated weekly writing should not silently enter the user's personal timeline.
- Source: M010 discussion 2026-05-05
- Primary owning slice: M010/S04,M010/S06
- Validation: Settings default off; publish action creates a normal server post only when called explicitly.

### R047 — AI token usage must be measurable without storing private AI content.
- Class: operational
- Status: active
- Description: Server-side AI provider calls for media summaries, weekly reviews, and focused tag fallback calls must write privacy-safe usage events with feature, subject, provider/model, promptVersion, status, duration, token usage, cached input token count, local estimates when provider usage is unavailable, and safe error codes. Settings > Storage & Diagnostics should expose Today, current week, current month, all-time totals, failures, estimated request count, and current-month feature breakdown.
- Why it matters: The project now has multiple AI surfaces and recurring review generation; without usage accounting the user cannot reason about cost, retry loops, prompt/model changes, or runaway automatic jobs.
- Source: token usage planning 2026-05-06
- Primary owning slice: M010/S08
- Validation: Schema includes `ai_usage_events`; AI provider wrappers record usage without transcript/prompt/summary/review input bodies; `/api/v1/admin/status.aiUsage` returns safe aggregates; iOS Settings renders the token usage section.

### R048 — Parallel development must use feature worktrees while preserving live data safety.
- Class: operational
- Status: active
- Description: `main` remains the fixed integration/version line. Each feature branch must use its own Git worktree for development, testing, building, packaging, and real-device UAT. Feature worktrees must use isolated server runtime data by default, and real iPhone installs from worktrees must preserve the existing app container and protect unsynced local data unless an explicitly planned recovery flow says otherwise.
- Why it matters: Branch switching inside one working directory makes Codex threads, builds, and merges hard to reason about. More importantly, Private Moments contains personal SQLite/media data, so temporary code must not accidentally downgrade schema, wipe local data, or write experiments into the live archive.
- Source: branch/worktree workflow discussion 2026-05-06
- Validation: New feature work starts in a dedicated worktree; completion summaries name the worktree/branch used; high-risk worktree installs include Sync Health/outbox review plus backup/container-copy evidence or an explicit recovery checkpoint; merged worktrees and branches are removed after integration.

### R049 — Release candidate readiness must keep true-device and human UAT gates explicit.
- Class: operational
- Status: active
- Description: Any path that cannot be proven by build/test alone must stay visible in `docs/UAT-GATES.md` until real iPhone, Mac Archive, Share Extension, AI quality, or user-confirmed evidence closes it. `verify:uat-gates` reports open gates during normal work, while `verify:release-gates` fails with any open gate.
- Why it matters: The project has many implemented-but-not-accepted paths. A single gate list prevents accidental release overclaims while still allowing checkpoint commits for verified code.
- Source: quality gate maintenance 2026-05-07
- Primary owning slice: maintenance
- Supporting slices: R001,R003
- Validation: `npm run verify:uat-gates` reports current open gates; `npm run verify:release-gates` exits non-zero while any open gate remains; closing a gate requires updating `docs/UAT-GATES.md`, `docs/HANDOFF.md`, and affected `.gsd` facts with current-session evidence.

### R050 — New operational settings and diagnostics should prefer iOS Settings over Mac Admin.
- Class: constraint
- Status: active
- Description: New settings, monitoring, diagnostics, and safe repair controls should default to iOS Settings / Diagnostics. Mac Admin remains for low-frequency Mac-local operations such as Archive backup/restore, staged promote, export/import artifacts, server logs, LaunchAgent/process state, filesystem paths, and permissions.
- Why it matters: The owner uses the phone as the primary surface and rarely uses the Mac Admin UI. Moving routine operations toward iOS keeps daily maintenance close to the app while preserving Admin where Mac-only context is required.
- Source: admin direction follow-up 2026-05-07
- Primary owning slice: maintenance
- Supporting slices: R036,R037,R047
- Validation: Future planning/design docs justify any new Admin-only operational surface; affected user-facing docs state whether short-term Admin-only controls should later migrate to iOS Settings.

### R001 — Non-trivial work must end with a minimum closure loop: change summary, verification evidence, known issues or next steps, and updates to affected fact-source or human-facing docs.
- Class: operational
- Status: active
- Description: Non-trivial work must end with a minimum closure loop: change summary, verification evidence, known issues or next steps, and updates to affected fact-source or human-facing docs.
- Why it matters: This project spans iOS, server, admin, local storage, and real-device behavior; losing end-of-work context makes future maintenance risky.
- Source: workflow alignment discussion 2026-04-30
- Validation: A completed non-trivial change includes fresh verification output and either updated docs/fact sources or an explicit note that none were affected.

### R002 — High-risk work must use milestone/slice planning before implementation when it can affect sync semantics, schema migrations, media storage or recovery, backup or restore, auth/security boundaries, or cross-device behavior.
- Class: operational
- Status: active
- Description: High-risk work must use milestone/slice planning before implementation when it can affect sync semantics, schema migrations, media storage or recovery, backup or restore, auth/security boundaries, or cross-device behavior.
- Why it matters: These areas can corrupt data, hide records, break recovery, or weaken the private network boundary even when changes are small.
- Source: workflow alignment discussion 2026-04-30
- Validation: High-risk changes have a milestone or slice context/plan before code changes and include success criteria plus verification evidence.

### R003 — Verification depth must be proportional to change impact: server/admin changes require build and HTTP or browser checks; iOS changes require build; sync, media, storage, and real-device behavior require device install or device data inspection when feasible.
- Class: operational
- Status: active
- Description: Verification depth must be proportional to change impact: server/admin changes require build and HTTP or browser checks; iOS changes require build; sync, media, storage, and real-device behavior require device install or device data inspection when feasible.
- Why it matters: A single fixed verification rule is either too weak for data-risk changes or too heavy for low-risk maintenance.
- Source: workflow alignment discussion 2026-04-30
- Validation: Completion summaries name the verification class used and include the command or inspection evidence.

### R008 — The iOS main timeline supports single-user Comments directly in the feed: a comment action row, bottom input bar, latest-two preview, in-place expand/collapse, and long-press delete confirmation.
- Class: functional
- Status: active
- Description: The iOS main timeline supports single-user Comments directly in the feed: a comment action row, bottom input bar, latest-two preview, in-place expand/collapse, and long-press delete confirmation.
- Why it matters: The requested interaction should feel like WeChat Moments from the main feed, not like a hidden detail-only note feature.
- Source: M003 comments discussion 2026-04-30
- Primary owning slice: M003/S03
- Supporting slices: M003/S01,M003/S02,M003/S04
- Validation: Real iPhone UAT creates a comment from the timeline, keeps the input target clear, shows the new comment immediately, expands/collapses comments in place, and deletes a comment by long-pressing it and confirming `Delete comment?`.

### R009 — Comments sync as independent local-first data through the Mac server with idempotent create/delete operations, parent constraints, soft delete, cursor-safe recovery, and no per-comment sync badges.
- Class: functional
- Status: active
- Description: Comments sync as independent local-first data through the Mac server with idempotent create/delete operations, parent constraints, soft delete, cursor-safe recovery, and no per-comment sync badges.
- Why it matters: Comments are user content; they must survive sync/recovery without becoming orphan data or cluttering the feed with technical state.
- Source: M003 comments discussion 2026-04-30
- Primary owning slice: M003/S02
- Supporting slices: M003/S01,M003/S03,M003/S04
- Validation: Server/iOS sync checks prove `create_comment` and `delete_comment` idempotency, missing/deleted parent rejection, local unsynced create/delete short-circuit, parent delete cascade, and strict no-cursor-advance behavior when a comment change cannot be applied.

### R010 — Comments remain plain multiline text with a 500-character limit and no media, Markdown rendering, rich text, replies, likes, mentions, visible author identity, editing, or copy/selection in the first version.
- Class: constraint
- Status: active
- Description: Comments remain plain multiline text with a 500-character limit and no media, Markdown rendering, rich text, replies, likes, mentions, visible author identity, editing, or copy/selection in the first version.
- Why it matters: The feature should add lightweight follow-up expression without turning Moments into a social network, thread system, or second writing editor.
- Source: M003 comments discussion 2026-04-30
- Primary owning slice: M003/S03
- Supporting slices: M003/S01,M003/S02,M003/S04
- Validation: UI/tests verify multiline literal text display, Markdown-like text stays plain, over-500-character input disables `Send`, long press opens delete confirmation rather than edit/copy/reply, and no comment media/reply/edit operation exists.

### R011 — Timeline search matches comment text after existing filters are applied, and search results make comment hits visible without changing true comment counts.
- Class: functional
- Status: active
- Description: Timeline search matches comment text after existing filters are applied, and search results make comment hits visible without changing true comment counts.
- Why it matters: If comments are part of timeline memory, search should find them, but it must not bypass active filters or produce unexplained results.
- Source: M003 comments discussion 2026-04-30
- Primary owning slice: M003/S03
- Supporting slices: M003/S01,M003/S04
- Validation: Search applies current filters first, returns a moment when either moment text or comment text matches, prioritizes up to two matching comments in preview, lightly emphasizes matching comment rows, and keeps comment counts as the full undeleted count.

### R012 — Comment implementation must include migration, recovery, diagnostics, and real-device evidence appropriate to schema/sync/timeline-keyboard risk.
- Class: operational
- Status: active
- Description: Comment implementation must include migration, recovery, diagnostics, and real-device evidence appropriate to schema/sync/timeline-keyboard risk.
- Why it matters: The riskiest failures are not just compile errors: comment loss after migration/recovery, cursor loss, private body leakage in diagnostics, and real-device keyboard/gesture regressions.
- Source: M003 comments discussion 2026-04-30
- Primary owning slice: M003/S04
- Supporting slices: M003/S01,M003/S02,M003/S03
- Validation: Completion evidence includes server migration/build, iOS schema/build, sync smoke checks, SQLite aggregate inspection or equivalent recovery proof, Advanced Sync/outbox operation counts without comment bodies, and real iPhone UAT when feasible.

### R013 — Audio/video publishing does not rely on iOS on-device speech transcription; transcript handling is server-side/internal when used for AI.
- Class: functional
- Status: active
- Description: New iOS clients must not run local Speech transcription, request speech recognition permission, upload `transcriptionText`, or show transcript fallback/status in the timeline. Historical transcript sync remains accepted only for old-client compatibility.
- Why it matters: The local recognizer produced incomplete transcripts; visible/transferred transcript artifacts made AI summaries unreliable and cluttered the product.
- Source: server-side media summary follow-up 2026-05-01
- Primary owning slice: M004
- Supporting slices: none
- Validation: iOS build no longer links Speech framework or contains local transcription services; creating audio/video moments uploads media without `transcriptionText`; timeline shows no transcript fallback/status when no ready AI summary exists.

### R014 — Audio/video media support Mac-server AI summaries generated from uploaded media files through local Mac transcription and external summary APIs.
- Class: functional
- Status: active
- Description: After complete audio/video upload, the Mac server starts a background summary job that transcribes the stored media file locally with `mlx-whisper`, summarizes the internal transcript through the configured external summary provider, and syncs only generated summary metadata back to iOS.
- Why it matters: The first AI layer should help the user quietly organize long voice/video notes while avoiding poor local transcription quality and keeping provider credentials server-only.
- Source: M005 AI media summaries discussion 2026-04-30; server-side media summary follow-up 2026-05-01
- Primary owning slice: M005/S02
- Supporting slices: M005/S01,M005/S03,M005/S04
- Validation: On a real iPhone, create one audio and one video moment, confirm media upload triggers local Mac transcription plus server-side summary, ready summary records include provider/model/prompt metadata and transcript length/hash only, and the result syncs back to iOS without changing the original post, media, or comments.

### R015 — AI summary UI keeps the main timeline quiet: only button/status appears inline, while full adaptive document summaries are shown in a bottom sheet.
- Class: functional
- Status: active
- Description: AI summary UI keeps the main timeline quiet: only lightweight summary states appear inline, while full adaptive `media-summary-v3` document summaries are shown in a bottom sheet.
- Why it matters: AI should be available as a useful organizing tool without crowding the feed or breaking the product's no-audience feel.
- Source: M005 AI media summaries discussion 2026-04-30
- Primary owning slice: M005/S03
- Supporting slices: M005/S01,M005/S04
- Validation: Timeline rows show no Summary placeholder or transcript fallback before any result exists. After a summary exists, the inline control may show `Summary ready`, `Regenerating`, or `Summary failed`; full summary text and transcript text must not appear directly in the timeline row. Tapping the control opens a bottom sheet rendered from `documentTitle`, `oneLiner`, and `documentBlocks` with default-collapsed details and labeled `AI suggested` callouts. Regenerate shows immediate in-sheet progress feedback, prevents repeated taps, keeps showing `Regenerating` after sheet dismissal, preserves the previous readable summary until replacement succeeds, and exposes failure reason plus retry without clearing the old summary.

### R016 — AI summary implementation must preserve privacy, sync safety, and failure isolation.
- Class: operational
- Status: active
- Description: AI summary implementation must preserve privacy, sync safety, and failure isolation. Server-side media summary jobs should run through a serialized local transcription queue so offline recovery or batch media upload does not start multiple competing `mlx-whisper` processes.
- Why it matters: External AI calls touch private transcript content and new generated metadata, so failures must not leak content, poison sync, or block normal media usage.
- Source: M005 AI media summaries discussion 2026-04-30
- Primary owning slice: M005/S04
- Supporting slices: M005/S01,M005/S02,M005/S03
- Validation: API keys are server-only; transcript and summary bodies are absent from normal logs/Admin diagnostics; missing media file, empty transcript, provider failure, invalid model output, delete summary, regenerate, and device recovery paths are verified; provider failures leave post/media/comment sync functional.

### R018 — Timeline search and organization must support lightweight local fuzzy retrieval and composable filters without crowding the feed.
- Class: functional
- Status: active
- Description: iPhone Timeline search must cover post text, comments, synced AI summary generated metadata, and historical transcript metadata using lightweight local fuzzy matching; filters must compose across content type, favorite, commented, needs-sync, tags, and match source when a query exists. Calendar day selection may add a temporary clearable day filter.
- Why it matters: As audio/video summaries and comments grow, the user needs practical retrieval without turning the main timeline into a database UI or depending on server-side search for everyday browsing.
- Source: search and AI hardening follow-up 2026-05-01
- Primary owning slice: maintenance
- Supporting slices: M003/S03,M005/S03
- Validation: iOS build proves the Timeline search model and filter UI compile; manual UAT should verify multi-keyword search, Chinese substring, light English typo tolerance, summary hits, source badges, active chips, clear filters, Calendar day filter handoff, and non-persistent filter state.

### R019 — v0.1 close-out and open-source preparation must keep setup simple while blocking private data and secret exposure.
- Class: operational
- Status: active
- Description: The project must provide a simple local setup path, release checklist, open-source readiness assessment, and privacy/security notes before any public release. Public release remains blocked until license, Git history secret scan, and backup/restore/export closure are complete.
- Why it matters: A private local-first app can work well for the owner while still being unsafe or confusing to publish. Open-source readiness must cover setup reproducibility, private data boundaries, external AI privacy, and recoverability.
- Source: v0.1 close-out discussion 2026-05-02
- Primary owning slice: maintenance
- Supporting slices: none
- Validation: `npm run setup:local` exists and is non-destructive; README and runbook point to it; release/open-source/security docs list current gates; verification includes setup help output, server/admin build checks, health check, ignore-boundary checks, and a sensitive-string scan summary.

### R020 — iOS must support system Share Sheet capture through a thin `Save to Moments` extension that stages content for the main app composer.
- Class: functional
- Status: active
- Description: Photos, Files, Voice Memos, Safari, and other iOS apps may hand off supported content through a Share Extension named `Save to Moments`; the extension writes a pending import into the App Group inbox, then opens Moments so the existing composer can edit text/media before publishing.
- Why it matters: Opening Moments first and then choosing media is too slow for everyday capture. The extension gives a system-native entry point while keeping publish, compression, SQLite, sync, and media preparation inside the main app.
- Source: Share Extension capture-entry discussion 2026-05-03
- Primary owning slice: maintenance
- Supporting slices: R003,R013,R014
- Validation: XcodeGen project generation, iOS unit tests, and generic iOS build must prove the app and extension compile together; real iPhone UAT should verify Photos/Safari/Files/Voice Memos share flows, composer launch, publish, and import queue cleanup when the phone is available.

### R021 — Media upload must be atomic, retryable, and diagnosable under iPhone/Tailscale disconnects.
- Class: operational
- Status: active
- Description: Server media upload must write multipart streams to hidden temp files, commit by atomic rename only after complete receipt, remove only temp files on failure, and log safe staged upload metadata/error codes without media bodies. iOS media retry must keep interrupted audio/video uploadable after offline periods, prioritize fresh `pending` media before older `failed` retries, and avoid holding full audio/video multipart bodies in memory.
- Why it matters: Real-device uploads can disconnect mid-stream. A created post with missing media should remain retryable from the iPhone local queue instead of producing committed partial files or opaque failures.
- Source: media upload failure investigation 2026-05-03
- Primary owning slice: maintenance
- Supporting slices: R003,R014,R020
- Validation: Server typecheck/build pass; restarting the Mac server leaves no stale media write fds; media directory has no leftover `.tmp` files; logs expose `media.upload_started`, `media.upload_received`, `media.upload_completed`, and `media.upload_failed` with `client_premature_close` or `upload_timeout` when applicable. iOS build verifies file-backed multipart upload, pending-before-failed queue ordering, and explicit retry wiring.

### R022 — Smart Tags must use a small stable primary-tag taxonomy plus dynamic canonical topic tags.
- Class: functional
- Status: active
- Description: Tags must distinguish primary expression-type tags from topic tags. Default primary tags are `日记`, `想法`, `学习整理`, `情绪`, `碎碎念`, and `复盘`; topic tags are dynamic, flat, canonicalized, alias-aware, and default to Chinese canonical names when possible.
- Why it matters: The user wants lightweight retrieval, not a taxonomy wall. Stable primary tags keep the organizing spine small, while topic tags capture concrete concepts such as `大语言模型`, `强化学习`, or `高斯概率分布`.
- Source: M006 Smart Tags discussion 2026-05-03
- Primary owning slice: M006/S01
- Supporting slices: M006/S02,M006/S04,M006/S06
- Validation: Schema/seed checks prove default primary tags exist, names are globally unique, aliases match case-insensitively, topic tags are flat, default primary tags cannot be renamed/hidden, and custom primary/topic lifecycle rules behave as documented.

### R023 — Manual tagging must work for all moment types while keeping Composer and Timeline low-noise.
- Class: functional
- Status: active
- Description: Text, image, video, and audio moments must support manual tags. Composer offers an optional primary-tag picker only; the single-moment tag editor can edit primary and topic tags; Detail shows full tags only when `Show tags in Timeline` is enabled; Timeline and Day Review show at most a primary tag under the same switch. When the switch is off, Moment Detail must not show the Tags section or offer tag editing.
- Why it matters: Tags should reduce future retrieval cost without making publishing feel like filing paperwork or cluttering the feed.
- Source: M006 Smart Tags discussion 2026-05-03
- Primary owning slice: M006/S02
- Supporting slices: M006/S01,M006/S06
- Validation: iOS UAT verifies publishing with and without a primary tag, editing primary/topic tags later when tag display is enabled, hiding Timeline/Day Review/Detail tag display without disabling tag data, and keeping abnormal sync status/favorite visibility stable in the metadata row.

### R024 — AI automatic tags must be audio-only, sparse for short audio, and reuse the ready summary pipeline.
- Class: functional
- Status: active
- Description: New audio moments may receive AI tags once when their first server-side audio summary becomes ready. Short audio/transcripts should prefer one topic tag and keep multiple topics only when the content clearly has separate high-confidence themes. Video, image, text-only moments, historical audio backfill, old-summary open events, and `Regenerate tags` are out of scope. Summary regeneration must not regenerate or overwrite tags.
- Why it matters: The useful first AI tagging path is voice-note organization. Keeping it tied to first ready audio summary avoids extra background jobs, weird confirmation popups, and unintended tag churn.
- Source: M006 Smart Tags discussion 2026-05-03
- Primary owning slice: M006/S05
- Supporting slices: M005/S02,M005/S03,M006/S01,M006/S06
- Validation: Real iPhone UAT publishes clear-speech short and multi-topic audio moments and confirms summary ready applies sparse topic tags; video/image/text moments do not receive AI tags; summary regeneration leaves existing tags unchanged; summary failure leaves AI tags absent without extra timeline state.

### R025 — Tags must participate in iPhone local search/filter and be manageable in iPhone Settings.
- Class: functional
- Status: active
- Description: Timeline search must match primary tags, topic tags, and aliases with `tag` as a match source. Filter must separate primary tags and topic tags, use AND semantics, and show popular/recent topics plus search. Settings must support tag usage counts, topic rename/merge/archive/restore, Topic batch archive/merge, Archived batch restore/delete, alias preservation, custom primary lifecycle, and primary color customization including batch primary color edits.
- Why it matters: Tags are only valuable if they can be used to find moments and cleaned up when AI or manual vocabulary drifts.
- Source: M006 Smart Tags discussion 2026-05-03
- Primary owning slice: M006/S03
- Supporting slices: M006/S04,M006/S06
- Validation: Focused tests and UAT prove search by canonical name and alias, tag match source display, primary/topic filter sections, AND filtering, archived tags hidden from ordinary search/filter, Settings single-item plus batch merge/archive/restore/delete behavior with usage counts, and batch primary color edits that change only selected primary tag colors.

### R026 — Tags must sync as first-class recoverable metadata with deterministic conflict behavior.
- Class: functional
- Status: active
- Description: Tag vocabulary, aliases, archive/delete state, primary colors, post tag assignments, assignment source/confidence, `aiTagProcessedAt`, and `tagsUserEditedAt` must persist on iOS and Mac server and sync across devices. Topic assignments merge independently; conflicting primary assignments use last-write-wins. Archived non-default tags can be permanently deleted to free an accidental normalized name.
- Why it matters: Tags are long-lived organization work. Losing or corrupting them on reinstall, sync recovery, or multi-device edits would undermine their purpose.
- Source: M006 Smart Tags discussion 2026-05-03
- Primary owning slice: M006/S01
- Supporting slices: M006/S05,M006/S06
- Validation: Sync/recovery checks prove tag vocabulary and assignments pull after reinstall-equivalent refresh, topic assignments from different devices can coexist, primary conflicts resolve by updatedAt, user-edited moments block future AI auto-application, and cursor advancement remains safe.

### R027 — Smart Tags implementation must preserve privacy, docs/contracts, diagnostics, and real-device proof.
- Class: operational
- Status: active
- Description: Smart Tags must update `.gsd`, shared OpenAPI/sync protocol, and affected human-facing docs; logs/diagnostics must avoid transcript, summary, post, and comment bodies; Settings diagnostics may show safe tag/AI status counts and error codes; completion requires real iPhone UAT.
- Why it matters: The feature crosses AI, private content, schema, sync, and UI. It needs the same verification discipline as comments and AI summaries.
- Source: M006 Smart Tags discussion 2026-05-03
- Primary owning slice: M006/S06
- Supporting slices: M006/S01,M006/S02,M006/S03,M006/S04,M006/S05
- Validation: Completion evidence includes server/iOS/admin builds as applicable, migration/sync/search/filter tests, no-private-body log inspection, serialized local transcription queue review, Settings diagnostics shape checks, OpenAPI/sync-protocol updates, and real iPhone UAT for new audio AI tags plus manual tag search/filter/edit flows.

### R033 — v0.1 archive work is scoped to the current self-use iPhone + Mac server loop, not public distribution or iOS standalone.
- Class: constraint
- Status: active
- Description: v0.1 archive/recovery work targets the current architecture where iPhone is the capture/browsing client and Mac server is the authoritative archive. iOS standalone mode, App Store/TestFlight distribution, public marketing, and open-source launch polish are out of scope for M009.
- Why it matters: Market research showed strong adjacent competition and high distribution cost. The immediate value is making the owner's private daily-use archive stable and recoverable.
- Source: v0.1 archive grill-me discussion 2026-05-05
- Primary owning slice: M009
- Supporting slices: M009/S01,M009/S02,M009/S03,M009/S04,M009/S05,M009/S06
- Validation: M009 artifacts and implementation avoid App Store/TestFlight/iOS standalone scope and focus on Mac-server archive, restore, and sync-health reliability.

### R034 — Backup/restore must be Admin-managed, restic-backed, deduplicated, staged, and recoverable without user-managed passwords.
- Class: functional
- Status: active
- Description: Mac Admin must manage backup repository initialization, immediate backup, daily scheduled backup, snapshot list/check, restore to new directory, verification, and strong-confirm promote. The underlying repository uses restic for deduplicated snapshots. The project auto-generates and stores a fixed key file next to the repository so the user does not need to remember a backup password.
- Why it matters: Raw CLI is too primitive for long-term self-use, but repeating full media backups wastes space. Restic gives mature snapshot/check/restore behavior while the project UI keeps routine operation understandable.
- Source: v0.1 archive grill-me discussion 2026-05-05
- Primary owning slice: M009/S02
- Supporting slices: M009/S01,M009/S03,M009/S06
- Validation: Admin can initialize a repo, run backup now, configure daily fixed-time backup, list/check snapshots, restore a snapshot into a new directory, verify it, and promote it only after strong confirmation and pre-promote backup.

### R035 — Restore/promote must protect current data through maintenance mode, pre-promote snapshot, verification, and restart-safe switching.
- Class: operational
- Status: active
- Description: Restore never directly overwrites the current data directory. It restores into a candidate directory, verifies database/media/config consistency, then promote enters maintenance mode, makes a pre-promote snapshot, and writes restart instructions for switching `PRIVATE_MOMENTS_DATA_DIR` / `DATABASE_URL` to the restored directory. Runtime SQLite replacement is intentionally avoided while Prisma has an open connection.
- Why it matters: A restore feature that can accidentally destroy the only working archive is worse than no restore feature. The recovery path must be safe under wrong snapshot selection, partial restore, and server failure.
- Source: v0.1 archive grill-me discussion 2026-05-05
- Primary owning slice: M009/S02
- Supporting slices: M009/S01,M009/S03,M009/S06
- Validation: Restore and promote smoke tests use a staged directory, verify before switch, block ordinary writes during promote preparation, create a pre-promote backup, and write `pending-promote.json` with rollback-aware restart instructions.

### R036 — Sync Health must explain stale or failing sync in Mac Admin and iOS Settings without adding noise to Timeline.
- Class: functional
- Status: active
- Description: Mac Admin and iOS Settings must expose comparable Sync Health categories covering server reachability, authentication, iPhone cursor vs Mac latest change version, pending/failed outbox operations, failed media uploads, missing media recovery, AI summary pipeline state, and last successful sync.
- Why it matters: The project has repeatedly had real-device issues where the root cause was not visible from the Timeline, such as remote-only server changes, media upload failures, or AI summary pipeline state. The owner needs to know where the system is stuck.
- Source: v0.1 archive grill-me discussion 2026-05-05
- Primary owning slice: M009/S04
- Supporting slices: M009/S01,M009/S06
- Validation: Admin and iOS Settings show the same high-level health model; stale cursor, pending outbox, failed upload, missing media, server unreachable, auth failure, and AI non-ready states are distinguishable without showing private content bodies.

### R037 — Sync Health may offer only safe, idempotent repair actions in v0.1.
- Class: constraint
- Status: active
- Description: Sync Health may expose safe repair actions such as Sync Now, retry uploads, pull server changes, and re-download missing media. It must not expose destructive defaults such as reset cursor, clear database, or rebuild local storage.
- Why it matters: Diagnostics should help the owner recover everyday failures without turning Settings into a dangerous maintenance console.
- Source: v0.1 archive grill-me discussion 2026-05-05
- Primary owning slice: M009/S04
- Supporting slices: M009/S06
- Validation: UI review confirms all repair actions are idempotent/low-risk; destructive actions are absent from default Sync Health.

### R038 — Export/import is migration-first: JSON manifest is authoritative, Markdown is preview, and import targets only a clean archive.
- Class: functional
- Status: active
- Description: Export packages must prioritize restore/import fidelity over human reading. They include authoritative JSON manifest/metadata plus media and optional Markdown preview. Import from export is in scope for M009 Phase B, but only into a new/empty data directory. Import preserves archive IDs/timestamps/generated metadata and reinitializes auth/device/outbox/sync runtime state.
- Why it matters: The owner cares more about future recovery and migration than reading exported files directly. A migration-first format avoids relying on lossy Markdown while still allowing manual inspection.
- Source: v0.1 archive grill-me discussion 2026-05-05
- Primary owning slice: M009/S05
- Supporting slices: M009/S01,M009/S03,M009/S06
- Validation: Export all/date range produces a package with manifest, metadata, media, and preview; import into an empty directory restores active, soft-deleted, archived, comment, tag, and generated summary state without bringing back auth/session/device tokens or re-running AI.

### R039 — Maintenance jobs must be durable, serial, privacy-safe, and able to place the server in maintenance mode for recovery operations.
- Class: operational
- Status: active
- Description: Backup, restore, check, promote, export, import, and sync health work must run through a durable `maintenance_jobs` model with persisted status, progress, stage, safe metadata, artifact path, error details, timestamps, serial execution, and maintenance mode support.
- Why it matters: Backup/restore/export/import are long-running and data-sensitive. Browser refresh, server restart, concurrent jobs, or private content leakage in logs must not make recovery unsafe or opaque.
- Source: v0.1 archive grill-me discussion 2026-05-05
- Primary owning slice: M009/S01
- Supporting slices: M009/S02,M009/S03,M009/S04,M009/S05,M009/S06
- Validation: Server migration/build pass; job list/detail APIs expose safe job state; a no-op/test job persists status transitions; stale running jobs are recoverable after restart; maintenance mode blocks representative write routes while health/job reads stay available; no private post/comment/transcript/summary/media body is stored in job metadata.

### R028 — New audio AI summaries may insert only a generated title into moment text, without turning Moments into a Markdown editor.
- Class: functional
- Status: active
- Description: For new audio moments, the first ready server-side AI summary may insert a valid `documentTitle` as `## <title>` at the top of `post.text` when the current text has no leading `# ` or `## ` title. New summary generation should produce a short title for recognizable non-empty audio/transcript notes, falling back from `oneLiner` if the provider returns no usable title. The insert is controlled by Settings > Feature Modules > `AI Title Auto-Insert`, defaults on, does not run for historical audio, video, image, text-only moments, invalid/overlong titles, or summary regeneration overwrite, and syncs through `insert_ai_title` without setting user `Edited` metadata.
- Why it matters: Voice notes often need a visible title in the timeline, but AI should only provide a small scannable affordance rather than rewriting the user's note or exposing full summaries as timeline prose.
- Source: AI title auto-insert follow-up 2026-05-03
- Primary owning slice: maintenance
- Supporting slices: R014,R015,R016,R018,R024
- Validation: iOS build/tests verify `# ` and `## ` display-only rendering in Timeline/Detail, plain Composer/Edit storage, heading-marker-stripped search, `AI Title Auto-Insert` toggle default on, and `insert_ai_title` sync preserving `localEditedAt`; server build verifies v3 title generation/fallback and that the sync operation accepts only server-owned ready audio summary titles and emits `post_updated` with `updateSource: ai_title`.

### R029 — iOS App Language must be a local immediate preference for English and Simplified Chinese UI.
- Class: functional
- Status: active
- Description: Settings must offer App Language as `System`, `English`, and `简体中文`. New installs default to System; existing private installs default to English when previous app state exists and no language preference has been set. The preference applies immediately, is stored in local `UserDefaults`, is not synced, and covers iOS user-visible Timeline, Calendar, Composer, Detail/Edit, Settings, Tags, Summary, Search/Filter, alerts, comments, and time/date labels.
- Why it matters: The app should be usable by English-preferring and Chinese-preferring users without creating separate product flows or syncing device-context UI preferences through the Mac server.
- Source: M007 iOS localization discussion 2026-05-03
- Primary owning slice: M007
- Supporting slices: R003,R018,R023,R025,R028
- Validation: iOS build verifies the localization layer compiles; dictionary coverage check proves every `L10n.t(...)` key has a Simplified Chinese value; real-device UAT should switch Settings > App Language and inspect the main timeline, composer, filters, tags, summary sheet, detail/edit, and alerts.

### R030 — Default primary tags must display localized names while preserving one synced identity and bilingual search.
- Class: functional
- Status: active
- Description: Default primary tags keep their synced tag IDs and stored canonical names, but display as `Diary`, `Thoughts`, `Study`, `Mood`, `Random`, and `Review` in English mode and as `日记`, `想法`, `学习整理`, `情绪`, `碎碎念`, and `复盘` in Chinese mode. Custom primary tags, topic tags, and aliases are not translated. Local search/filter should match default primary tags by both Chinese and English display names.
- Why it matters: Language switching should change labels, not split tag usage counts, AI assignments, sync behavior, or historical retrieval.
- Source: M007 iOS localization discussion 2026-05-03
- Primary owning slice: M007
- Supporting slices: R022,R023,R025,R026
- Validation: iOS build verifies localized tag display/search helpers compile; UAT should confirm one default tag keeps the same usage count while changing App Language and that both `study` and `学习` can find/filter the default study primary tag.

### R031 — AI summary/title language must be configurable independently from App Language.
- Class: functional
- Status: active
- Description: Settings must offer AI Language as `Auto`, `Chinese`, and `English`, defaulting to Auto. iOS passes this preference to the Mac summary pipeline for upload-triggered and manual regenerated summaries. Auto follows the dominant input language; Chinese and English force generated summary/title output where reasonable. App UI language must not force generated content language.
- Why it matters: AI summaries and titles are derived content, not interface chrome. Chinese voice notes with English technical terms should still summarize naturally in Chinese unless the user explicitly forces English.
- Source: M007 iOS localization discussion 2026-05-03
- Primary owning slice: M007
- Supporting slices: R014,R015,R016,R024,R028
- Validation: Server typecheck/build verifies the new `aiLanguage` request path and prompt handling; UAT should create or regenerate audio summaries with Auto/Chinese/English and confirm generated output language changes without changing App Language.

### R032 — Calendar Review must provide local month-grid time review without becoming a second editor or sync surface.
- Class: functional
- Status: active
- Description: iOS must expose a bottom `Calendar` / `日历` tab beside Timeline. Calendar defaults to a local-derived month grid, supports continuous month navigation by arrows and horizontal swipe, uses quiet heatmap density from local moment counts, shows at most two media hints per day, supports Calendar-owned media/favorite filters, fades future dates, highlights today subtly, and has no Compose entry. Tapping a populated date opens Day Review first, and Day Review should remember its per-day scroll position.
- Why it matters: As the timeline grows, the user needs stronger回看 ability than scrolling or toolbar menus, but the main reading surface should remain Timeline and Calendar must not become a management dashboard.
- Source: M008 Calendar Review discussion 2026-05-03
- Primary owning slice: M008
- Supporting slices: R003,R018,R029
- Validation: CalendarReviewModelsTests cover continuous 42-cell months, empty months, locale first weekday, today/future states, density buckets, max-two media hints, and media/favorite filters. iOS UAT should verify arrows, horizontal swipe, Today, day tap to Day Review, Day Review item detail push/back, top-right Timeline day filter handoff, per-day scroll memory, light/dark, and English/Chinese labels.

## Validated

### R004 — The timeline must keep feed browsing as the primary experience while offering lightweight month-first, optional-day jump navigation from a low-frequency toolbar menu entry.
- Class: functional
- Status: validated
- Description: The timeline must keep feed browsing as the primary experience while offering lightweight month-first, optional-day jump navigation from a low-frequency toolbar menu entry.
- Why it matters: As content grows, the user needs to return to a period of life without turning Moments into a database or management tool.
- Source: M001 discussion
- Primary owning slice: M001/S01
- Validation: S01 completed: root-level and iOS XcodeGen specs generate successfully; generic iOS build passed; TimelineDateJumpModelsTests passed 5/5 on iPhone 17 simulator. This M001 toolbar menu path was later superseded by R032 Calendar Review.

### R005 — Date navigation must only show existing months and dates with moments, use life-feeling labels such as month names and weekday context, and avoid daily counts or database-style primary date strings.
- Class: constraint
- Status: validated
- Description: Date navigation must only show existing months and dates with moments, use life-feeling labels such as month names and weekday context, and avoid daily counts or database-style primary date strings.
- Why it matters: The feature should support returning to lived time, not statistical archive management.
- Source: M001 discussion
- Primary owning slice: M001/S01
- Validation: S01 completed: TimelineDateJumpBuilder tests passed 5/5 and prove the old toolbar jump groups are derived only from caller-provided visible items, omit empty dates, select first visible day targets, and enforce count/statistics-free labels. Calendar Review later intentionally allows continuous empty months while still avoiding visible daily counts.

### R006 — Composer and edit text input may support plain-text list continuation for `- `, `• `, and numbered list prefixes, including numbered auto-increment and empty-item exit.
- Class: functional
- Status: validated
- Description: Composer and edit text input may support plain-text list continuation for `- `, `• `, and numbered list prefixes, including numbered auto-increment and empty-item exit.
- Why it matters: This preserves lightweight expression while removing common friction when writing a few short lines.
- Source: M001 discussion
- Primary owning slice: M001/S02
- Validation: Validated by `cd ios && xcodegen generate && xcodebuild -project PrivateMoments.xcodeproj -scheme PrivateMomentsListContinuationTests -destination 'platform=iOS Simulator,name=iPhone 16' test` after creating an available iPhone 16 simulator: 14 XCTest cases passed, covering dash, bullet, numbered increment, empty-item exit, normal paragraph fallback, non-list fallback, invalid range fallback, max-int fallback, and emoji/Unicode UTF-16 safety. App integration also built with `xcodebuild -project PrivateMoments.xcodeproj -scheme PrivateMoments -destination generic/platform=iOS -configuration Debug CODE_SIGNING_ALLOWED=NO build`. Manual UAT script is recorded in S02-UAT for tactile cursor/save verification.

### R007 — Moments must not introduce Markdown rendering, rich-text formatting, headings, bold, quotes, or link previews as part of the list continuation work.
- Class: constraint
- Status: validated
- Description: Moments must not introduce Markdown rendering, rich-text formatting, headings, bold, quotes, or link previews as part of the list continuation work.
- Why it matters: The app should remain an expression space rather than becoming a Markdown editor or writing tool.
- Source: M001 discussion
- Primary owning slice: M001/S02
- Validation: Validated by implementation boundaries and build evidence for S02: list continuation is implemented as plain string editing via `PlainTextListContinuation` and `PlainTextListEditor`; New Moment/Edit Moment bindings still pass plain `String` values into existing draft/save flows; no Markdown/rich-text rendering, schema, server, sync, storage, telemetry, or logging changes were introduced. `PrivateMomentsListContinuationTests` passed on iPhone 16 simulator and the app target built for generic iOS with code signing disabled.

### R017 — Server-originated AI summary changes must be pullable and diagnosable even when the iPhone has no local pending work.
- Class: functional
- Status: validated
- Description: iOS must pull `ai_summary_updated` / `ai_summary_deleted` server changes after Mac-side processing completes, even if the local outbox, uploads, and media downloads are empty. Diagnostics must make it clear whether a missing summary is a server job failure or a client cursor/pull staleness issue.
- Why it matters: Mac can generate ready summaries after the original upload has already synced. If iOS only syncs when local work exists, the timeline can keep showing no `Summary ready` or old failed summary state even though server data is correct.
- Source: real-device AI summary diagnostics 2026-05-01
- Primary owning slice: M005/S04
- Supporting slices: M005/S02,M005/S03
- Validation: Validated on 2026-05-01 after implementing remote-only pull on app foreground, Storage & Diagnostics refresh, and manual Sync Now. Server admin status returned `sync.latestServerChangeVersion=196` and `aiSummaries ready=10 failed=0`; a paired iPhone container copied after install/launch showed `lastSyncCursor=196`, `local_ai_summaries ready=10 failed=0`, and outbox pending/failed `0`. 2026-05-06 follow-up changed Storage & Diagnostics refresh to read-only status loading; app foreground, `Sync Now`, and `Pull Server Changes` remain remote-only pull paths, while diagnostics still compares iPhone cursor with Mac change version. A later 2026-05-06 follow-up made Settings root show the sync spinner only for user-tapped `Sync Now` and added short timeouts to idle sync checks before fallback.

## Traceability

| ID | Class | Status | Primary owner | Supporting | Proof |
|---|---|---|---|---|---|
| R001 | operational | active | none | none | A completed non-trivial change includes fresh verification output and either updated docs/fact sources or an explicit note that none were affected. |
| R002 | operational | active | none | none | High-risk changes have a milestone or slice context/plan before code changes and include success criteria plus verification evidence. |
| R003 | operational | active | none | none | Completion summaries name the verification class used and include the command or inspection evidence. |
| R004 | functional | validated | M001/S01 | none | S01 completed with TimelineDateJumpModelsTests/build evidence; this old toolbar-menu date navigation path was later superseded by R032 Calendar Review. |
| R005 | constraint | validated | M001/S01 | none | S01 completed: TimelineDateJumpBuilder tests passed 5/5 and prove groups are derived only from caller-provided visible items, omit empty dates, select first visible day targets, and enforce count/statistics-free labels. TimelineView passes filteredItems into the builder. |
| R006 | functional | validated | M001/S02 | none | Validated by `cd ios && xcodegen generate && xcodebuild -project PrivateMoments.xcodeproj -scheme PrivateMomentsListContinuationTests -destination 'platform=iOS Simulator,name=iPhone 16' test` after creating an available iPhone 16 simulator: 14 XCTest cases passed, covering dash, bullet, numbered increment, empty-item exit, normal paragraph fallback, non-list fallback, invalid range fallback, max-int fallback, and emoji/Unicode UTF-16 safety. App integration also built with `xcodebuild -project PrivateMoments.xcodeproj -scheme PrivateMoments -destination generic/platform=iOS -configuration Debug CODE_SIGNING_ALLOWED=NO build`. Manual UAT script is recorded in S02-UAT for tactile cursor/save verification. |
| R007 | constraint | validated | M001/S02 | none | Validated by implementation boundaries and build evidence for S02: list continuation is implemented as plain string editing via `PlainTextListContinuation` and `PlainTextListEditor`; New Moment/Edit Moment bindings still pass plain `String` values into existing draft/save flows; no Markdown/rich-text rendering, schema, server, sync, storage, telemetry, or logging changes were introduced. `PrivateMomentsListContinuationTests` passed on iPhone 16 simulator and the app target built for generic iOS with code signing disabled. |
| R008 | functional | active | M003/S03 | M003/S01,M003/S02,M003/S04 | Real iPhone UAT creates a comment from the timeline, keeps the input target clear, shows the new comment immediately, expands/collapses comments in place, and deletes a comment by long-pressing it and confirming `Delete comment?`. |
| R009 | functional | active | M003/S02 | M003/S01,M003/S03,M003/S04 | Server/iOS sync checks prove `create_comment` and `delete_comment` idempotency, missing/deleted parent rejection, local unsynced create/delete short-circuit, parent delete cascade, and strict no-cursor-advance behavior when a comment change cannot be applied. |
| R010 | constraint | active | M003/S03 | M003/S01,M003/S02,M003/S04 | UI/tests verify multiline literal text display, Markdown-like text stays plain, over-500-character input disables `Send`, long press opens delete confirmation rather than edit/copy/reply, and no comment media/reply/edit operation exists. |
| R011 | functional | active | M003/S03 | M003/S01,M003/S04 | Search applies current filters first, returns a moment when either moment text or comment text matches, prioritizes up to two matching comments in preview, lightly emphasizes matching comment rows, and keeps comment counts as the full undeleted count. |
| R012 | operational | active | M003/S04 | M003/S01,M003/S02,M003/S03 | Completion evidence includes server migration/build, iOS schema/build, sync smoke checks, SQLite aggregate inspection or equivalent recovery proof, Advanced Sync/outbox operation counts without comment bodies, and real iPhone UAT when feasible. |
| R013 | functional | active | M004 | none | iOS build no longer links Speech framework or contains local transcription services; creating audio/video moments uploads media without `transcriptionText`; timeline shows no transcript fallback/status when no ready AI summary exists. |
| R014 | functional | active | M005/S02 | M005/S01,M005/S03,M005/S04 | Real iPhone UAT confirms uploaded audio/video triggers Mac-local transcription plus external summary generation and syncs ready summary records back to iOS; only the narrow R028 audio title insert may mutate `post.text`. |
| R015 | functional | active | M005/S03 | M005/S01,M005/S04 | Timeline rows expose only `Summary ready`; bottom sheet renders ready v3 document summaries with copy/regenerate/delete controls and no transcript fallback. |
| R016 | operational | active | M005/S04 | M005/S01,M005/S02,M005/S03 | Verification proves server-only API keys, no private body logging, failure isolation, summary delete/regenerate behavior, and sync recovery for generated AI metadata. |
| R017 | functional | validated | M005/S04 | M005/S02,M005/S03 | 2026-05-01 paired iPhone container advanced to `lastSyncCursor=196` with `local_ai_summaries ready=10 failed=0` after server-only summary changes; 2026-05-06 follow-ups keep diagnostics refresh read-only, use explicit `Sync Now` / `Pull Server Changes` for manual pull, and prevent background idle sync from appearing as an endless Settings spinner. |
| R018 | functional | active | maintenance | M003/S03,M005/S03 | iPhone Timeline search covers text, comments, AI summary metadata, and historical transcript metadata with lightweight fuzzy matching plus composable local filters and active chips. |
| R019 | operational | active | maintenance | none | `npm run setup:local` plus release/open-source/security docs provide the current setup and publication gate; public release still requires license, Git history secret scan, and release-grade backup/restore/export/import validation. |
| R020 | functional | active | maintenance | R003,R013,R014 | `Save to Moments` stages supported Share Sheet content into an App Group inbox and opens the main app composer for final editing and publish; real-device UAT remains required when the paired phone is available. |
| R021 | operational | active | maintenance | R003,R014,R020 | Media upload uses temp-file atomic finalization and staged logs; verification checks server build, health, no stale write fds, no leftover temp files, and real-device retry behavior when feasible. |
| R022 | functional | active | M006/S01 | M006/S02,M006/S04,M006/S06 | Default primary tags, topic canonicalization, aliases, uniqueness, archive behavior, and custom-primary constraints are verified by schema/seed checks and Settings/Edit UAT. |
| R023 | functional | active | M006/S02 | M006/S01,M006/S06 | Composer optional primary tag, single-moment tag editing, Detail read-only tags, optional Timeline/Day Review/Detail tag visibility, and metadata-row priority are verified on iOS. |
| R024 | functional | active | M006/S05 | M005/S02,M005/S03,M006/S01,M006/S06 | New short audio prefers one first-ready summary AI topic tag unless high-confidence separate themes justify more; non-audio moment types do not receive AI tags, summary regenerate does not change tags, and summary failure leaves no AI tags. |
| R025 | functional | active | M006/S03 | M006/S04,M006/S06 | iPhone local search/filter matches tag names and aliases, distinguishes tag match source, separates primary/topic filters, uses AND semantics, and Settings can clean up vocabulary including batch Topic/Archived operations plus batch primary color edits. |
| R026 | functional | active | M006/S01 | M006/S05,M006/S06 | Tag vocabulary and assignments sync/recover, archived custom tags can be permanently deleted, topic assignments merge, primary conflicts use last-write-wins, and user-edited moments block later AI auto-application. |
| R027 | operational | active | M006/S06 | M006/S01,M006/S02,M006/S03,M006/S04,M006/S05 | Smart Tags closure includes builds/tests, real iPhone UAT, no private-body logs, Settings diagnostics, OpenAPI/sync protocol updates, and docs/fact-source updates. |
| R028 | functional | active | maintenance | R014,R015,R016,R018,R024 | New audio AI summary title can sync into `post.text` as `## <title>` once, render as a restrained heading in Timeline/Detail, remain plain in Composer/Edit, avoid `Edited`, and be disabled for future inserts in Feature Modules. |
| R029 | functional | active | M007 | R003,R018,R023,R025,R028 | iOS App Language is a local immediate preference for System/English/简体中文 and covers the main iOS visible surfaces with Chinese dictionary coverage. |
| R030 | functional | active | M007 | R022,R023,R025,R026 | Default primary tags display localized names without changing synced identity, and local search/filter matches both Chinese and English default names. |
| R031 | functional | active | M007 | R014,R015,R016,R024,R028 | AI Language is local and independent from App Language; iOS passes `auto`/`zh`/`en` to upload-triggered and regenerated summary generation. |
| R032 | functional | active | M008 | R003,R018,R029 | Calendar Review provides a local bottom-tab month grid, Day Review first navigation, Timeline handoff, and per-day scroll memory; CalendarReviewModelsTests and iOS build/test evidence passed, while real-device UAT remains pending. |
| R033 | constraint | active | M009 | M009/S01,M009/S02,M009/S03,M009/S04,M009/S05,M009/S06 | M009 stays scoped to the current iPhone + Mac owner-use loop and excludes public distribution/App Store/iOS standalone work. |
| R034 | functional | active | M009/S02 | M009/S01,M009/S03,M009/S06 | Admin can configure a restic repository, create a project-managed key file, run/list/check backups, schedule daily backups, and restore staged snapshots without user-managed passwords. |
| R035 | operational | active | M009/S02 | M009/S01,M009/S03,M009/S06 | Restore writes to a new directory and promote preparation verifies the restore, enters maintenance mode, creates a pre-promote backup, and writes restart instructions instead of hot-swapping an open SQLite database. |
| R036 | functional | active | M009/S04 | M009/S01,M009/S06 | Mac Admin and iOS Settings show Sync Health categories for reachability/auth/cursor/outbox/upload/missing-media/AI/last-success without putting diagnostics in Timeline. |
| R037 | constraint | active | M009/S04 | M009/S06 | Sync Health exposes safe repair actions only: sync, pull server changes, retry/re-download media; destructive reset/rebuild actions stay out of default v0.1 UI. |
| R038 | functional | active | M009/S05 | M009/S01,M009/S03,M009/S06 | Phase B export/import creates migration-first packages where JSON manifest is authoritative, Markdown is preview, import targets only a new staged archive, and runtime auth/device state is excluded. |
| R039 | operational | active | M009/S01 | M009/S02,M009/S03,M009/S04,M009/S05,M009/S06 | Durable serial `maintenance_jobs` store safe job state, recover stale running jobs after restart, and support maintenance mode for recovery operations without private content body leakage. |
| R040 | functional | active | M010/S01 | R003 | Review artifacts use generic kind/range fields so Weekly Review is the first period kind without hard-coding week-only storage. |
| R041 | functional | active | M010/S04 | R003 | Manual and scheduled Weekly Review generation default to rolling seven-day ranges, with scheduled generation default off and quiet. |
| R042 | functional | active | M010/S02 | R014,R015,R024 | Review input uses post text, comments, ready media summary metadata, tags, favorite, media kind, and rhythm stats; image vision/OCR is out of v1. |
| R043 | constraint | active | M010/S03 | R015,R045 | Review prompt/schema use whole-period reading and reserve moment IDs only for low-weight `Worth Revisiting` anchors. |
| R044 | functional | active | M010/S06 | R001,R003 | Review settings and feedback are explicit, visible, default-off where invasive, and never mutate original moments. |
| R045 | functional | active | M010/S05 | R032 | Weekly Review belongs in Calendar Reviews, and moment anchors open inside the Review context rather than jumping Timeline. |
| R046 | constraint | active | M010/S04,M010/S06 | R044 | Publish-as-moment is explicit and never automatic by default. |
| R047 | operational | active | M010/S08 | R016,R024,R040,R041 | `ai_usage_events` and admin/iOS diagnostics measure AI token usage without storing transcript, prompt, review input, provider response, or generated bodies. |
| R048 | operational | active | none | R001,R002,R003 | Feature work uses dedicated worktrees and protects live Mac/iPhone data before real-device installs or high-risk runtime checks. |
| R049 | operational | active | maintenance | R001,R003 | `docs/UAT-GATES.md` plus `verify:uat-gates` / `verify:release-gates` keep true-device and human UAT gaps visible until evidence closes them. |
| R050 | constraint | active | maintenance | R036,R037,R047 | New operational settings, diagnostics, monitoring, and safe repair controls prefer iOS Settings; Mac Admin remains for Mac-local recovery and low-frequency operations. |

## Coverage Summary

- Active requirements: 45
- Mapped to slices: 41 (R008, R009, R010, R011, R012, R013, R014, R015, R016, R018, R019, R020, R021, R022, R023, R024, R025, R026, R027, R028, R029, R030, R031, R032, R033, R034, R035, R036, R037, R038, R039, R040, R041, R042, R043, R044, R045, R046, R047, R049, R050)
- Validated: 5 (R004, R005, R006, R007, R017)
- Unmapped active requirements: 4 global operational requirements (R001, R002, R003, R048)
