---
phase: complete-milestone
phase_name: Milestone Completion Learnings
project: private-moments
generated: 2026-04-29T20:09:38Z
counts:
  decisions: 4
  lessons: 4
  patterns: 4
  surprises: 2
missing_artifacts: []
---

# M002 Learnings: Private comments for moments

### Decisions

- Comments are modeled as first-class synced entities with `entityType: "comment"`, not embedded post payload data, so create/delete lifecycle, soft deletion, and recovery-sensitive sync can be managed independently.
  Source: S01-SUMMARY.md/Key decisions

- The first comment contract supports separate idempotent `create_comment` and `delete_comment` operations, while comment update/edit remains out of scope for this milestone.
  Source: S01-SUMMARY.md/Key decisions

- The only user-facing comment surface is iOS Moment detail; the main timeline must not gain comment badges, counts, previews, search participation, or other clutter.
  Source: M002-ROADMAP.md/Success Criteria

- Private comments remain plain-text, single-level, and non-social: no replies, likes, mentions, Markdown rendering, public identity, rich text, comment media, or thread/edit affordances.
  Source: S03-SUMMARY.md/Requirements Validated

### Lessons

- Real-device install/launch automation is useful evidence, but it cannot validate requirements that explicitly require manual iPhone gestures and populated aggregate data; R008 correctly stayed active.
  Source: S03-SUMMARY.md/Known Limitations

- Comment sync payloads should carry parent `postId` even when `entityId` is the comment id, because local post sync-status refresh and detail reloads still need the parent moment context.
  Source: S01-SUMMARY.md/Patterns established

- Private-data validation should record only aggregate SQLite counts and statuses; comment bodies and secrets should not be logged in UAT evidence or diagnostics.
  Source: S03-SUMMARY.md/Patterns established

- Cursor advancement remains data-sensitive for new entities: server changes must be durably applied locally before advancing sync cursor, or recovery-sensitive data can appear lost.
  Source: S01-SUMMARY.md/Requirements Validated

### Patterns

- For detail-only features, add a static guard against timeline clutter by checking `TimelineRow.swift` and `TimelineView.swift` for forbidden feature references.
  Source: S02-SUMMARY.md/Patterns established

- Keep UI boundary rules that need deterministic proof in Foundation-only policy helpers rather than burying them inside SwiftUI view state.
  Source: S02-SUMMARY.md/Patterns established

- Route comment create/delete mutations through `TimelineStore` and local database reload paths instead of optimistically mutating rendered row collections.
  Source: S02-SUMMARY.md/Patterns established

- Document private-data UAT with repeatable iPhone steps, aggregate local/server DB queries, blocked-check handling, and explicit privacy rules.
  Source: S03-SUMMARY.md/Provides

### Surprises

- The copied device database evidence after install/launch had zero `local_comments` rows and zero comment outbox operations because no manual comment gestures were performed in auto-mode.
  Source: S03-SUMMARY.md/Known Limitations

- Checked local server SQLite archives did not expose a `comments` table, so the active schema-version-4 database path still needs confirmation during manual UAT.
  Source: S03-SUMMARY.md/Follow-ups
