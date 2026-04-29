# S03: Comment flow validation and documentation — UAT

**Milestone:** M002
**Written:** 2026-04-29T20:07:21.047Z

# S03 UAT: Private Comments validation

## Preconditions

- Mac development server is prepared with schema version 4 and reachable from the iPhone over the intended private network/Tailscale boundary.
- `server/.env` is configured locally; do not paste passwords, tokens, server secrets, or private comment bodies into logs or handoff notes.
- `Moments` is installed on the real iPhone (`wwz 的 iphone` by default, or `PRIVATE_MOMENTS_DEVICE_NAME` override) and points at the active Mac server in Settings.
- At least one existing non-deleted moment is visible in the iOS timeline.
- Record only aggregate counts/statuses from SQLite, not the text of private comments.

## Test Case 1 — Add two private comments in Moment detail

1. Launch `Moments` on the iPhone and open an existing moment from the main timeline.
   - Expected: Moment detail opens and the parent moment remains visible.
2. Locate the `Private Comments` section.
   - Expected: The comment UI is only in detail view, not in the timeline row.
3. Add one short private comment using `Add`.
   - Expected: The comment appears under `Private Comments`; any pending/sync indicator uses existing sync-status UI.
4. Add a second comment containing multiline and Markdown-like literal text, for example a line break plus `**bold**` or `- item`.
   - Expected: The text is stored/displayed as literal plain text; there is no Markdown rendering, rich-text control, reply affordance, like, mention, or public author identity.

## Test Case 2 — Delete exactly one selected comment

1. Choose one of the two comments and trigger delete.
   - Expected: A centered confirmation alert appears.
2. Confirm deletion.
   - Expected: Only the selected comment is removed/marked deleted; the parent moment remains visible; the other comment remains visible.
3. Return to the main timeline.
   - Expected: The timeline still shows the parent moment without comment badge, count, dot, preview, or comment-specific search surface.

## Test Case 3 — Sync and local durability checks

1. Let sync run until pending state clears, or note the visible pending/error state if the server is unreachable.
   - Expected: Successful sync clears comment-related pending outbox state; failure remains diagnosable via existing SyncBadge/outbox/status surfaces.
2. Copy the app Library container using the runbook `xcrun devicectl device copy from ... --source Library ...` pattern.
   - Expected: A readable copied app Library is available for local SQLite inspection.
3. Query aggregate local state only:
   - `SELECT COUNT(*) AS local_comments_total FROM local_comments;`
   - `SELECT COUNT(*) AS local_comments_visible FROM local_comments WHERE deletedAt IS NULL;`
   - `SELECT syncStatus, COUNT(*) AS count FROM local_comments GROUP BY syncStatus ORDER BY syncStatus;`
   - `SELECT type, status, COUNT(*) AS count FROM outbox_operations WHERE type IN ('create_comment', 'delete_comment') GROUP BY type, status ORDER BY type, status;`
   - Expected: Counts reflect the two creates and one delete from this UAT; no long-lived pending/failed row remains after successful sync.

## Test Case 4 — Server durability checks

1. Query the active schema-version-4 server SQLite database, confirming it is the database used by the running server.
2. Run aggregate checks only:
   - `SELECT COUNT(*) AS server_comments_total FROM comments;`
   - `SELECT COUNT(*) AS server_comments_visible FROM comments WHERE deletedAt IS NULL;`
   - `SELECT type, COUNT(*) AS count FROM sync_operations WHERE type IN ('create_comment', 'delete_comment') GROUP BY type ORDER BY type;`
   - Expected: Server aggregates reflect comment create/delete operations; deletion changes derive authoritative parent post context from the existing comment row even if the client included `postId` only for local parent sync-status refresh.

## Test Case 5 — Static no-timeline-clutter guard

Run:

```bash
! rg -n "comment|Comment" ios/PrivateMoments/Views/TimelineRow.swift ios/PrivateMoments/Views/TimelineView.swift
```

Expected: exit code 0 with no output, proving no comment-specific UI surface was added to the main timeline files.

## Current S03 execution result

Automated/server checks passed in auto-mode: `npm run server:build`, iOS simulator tests on iPhone 16 with 16/16 passing, generic iOS Debug build with `CODE_SIGNING_ALLOWED=NO`, stale-doc/static anchor checks, and static timeline non-clutter check. Real-device install/launch also passed in T01. Manual iPhone create/delete UAT and populated local/server SQLite aggregate proof were not completed by auto-mode and remain the explicit follow-up for R008.
