# M012: Check-ins

**Gathered:** 2026-05-08
**Status:** Checkpoint implemented and simulator-validated; check-in media remains a follow-up
**Worktree:** `/Users/popcornnnnnn/.codex/worktrees/c75e/private-moments`
**Branch:** `codex/checkins-module`
**Depends on:** iOS bottom tabs, Timeline mixed feed rendering, Calendar month stats and Day Review, local SQLite schema, server Prisma schema, sync operations, media storage, tags, search/filter, Weekly Review, Settings diagnostics, and worktree/data-safety requirement R048.

## Project Description

M012 adds `Check-ins` as a third primary iOS surface beside `Timeline` and `Calendar`. The startup/default tab remains `Timeline`, and the bottom tab order is `Timeline / Calendar / Check-ins`.

Check-ins are private life-activity records such as meals, exercise, waking up early, or healthy eating. They are not a KPI habit tracker, task system, reminder system, or social feature. They are a faster structured way to record recurring life activities while still letting the user decide whether any specific entry appears in the Timeline.

## Root Decision

Check-ins are independent local-first data, not disguised Moments:

- A `Check-in Item` defines an activity such as `Meal` or `Exercise`.
- A `Check-in Entry` records one completion of an item at an `occurredAt` time.
- Entries can be shown in Timeline, but Timeline directly renders published check-in entries rather than creating linked ordinary moments.
- Calendar, Day Review, Check-ins History, Month Stats, and Weekly Review use check-in entries regardless of whether they are shown in Timeline.
- `Show in Timeline` is entry-level visibility only. It does not define whether the entry exists.

## User-Visible Outcome

The user can:

- Open a dedicated `Check-ins` tab from the bottom navigation.
- See `Today` by default.
- Tap the main area of a check-in item once to record immediately without a sheet, prompt, or required content.
- Use a separate lightweight content button to create an entry with note/media.
- Create once-per-day or multiple-per-day items.
- Configure active weekdays for each item.
- View `Not scheduled today` items in a folded section and still record them when needed.
- See once-per-day items sink after completion, while multiple-per-day items stay in their manual order.
- Undo a just-created one-tap entry from a short toast/snackbar.
- Open an entry detail page to edit note, media, occurred time, item, and `Show in Timeline`, or cancel the check-in.
- Switch Check-ins from `Today` to `History`.
- Use `Manage Items` for item creation, editing, manual sorting, archiving, and deletion.
- See Check-ins included in Calendar heatmap, Month Stats, Day Review, and Weekly Review structure signals.

## Product Boundaries

### In Scope

- New bottom tab `Check-ins` after `Calendar`.
- `Today` and `History` modes inside Check-ins.
- `Manage Items` for item configuration.
- Local-first item and entry data model.
- Sync operations for item create/update/archive/delete/reorder and entry create/update/cancel.
- Once-per-day and multiple-per-day record modes.
- Weekday scheduling.
- Per-item default `Show in Timeline`.
- Per-entry override and later edit of `Show in Timeline`.
- Entry note plus one media kind using the existing media cardinality rule: up to 9 images, or 1 video, or 1 audio.
- Empty-content semantic entries.
- Independent `Check-in Entry Detail`.
- Timeline and Day Review mixed rendering with compact rows for empty entries and richer rows for entries with note/media.
- Calendar heatmap counting moments plus check-in entries equally.
- Month Stats combined activity breakdown with `Moments`, `Check-ins`, and per-item completion counts.
- Check-ins History descending feed with item filtering.
- Timeline and Day Review `Check-ins` content-type filter.
- Check-ins search over item name, entry note, manual item tag, and media type.
- Optional item-level Smart Tag association, defaulting to none.
- iOS Settings diagnostics for check-in sync/media issues.
- Weekly Review structure signal from item names, dates, and counts only.
- Simulator mock-data validation.

### Out Of Scope

- Reminders, notifications, missed-entry generation, streak pressure, completion-rate dashboards, or KPI habit tracking.
- Failure/missed records as persisted entries.
- Count/quantity goal mode.
- Comments, favorite, or pin on check-in entries.
- AI summary, transcription, AI tag generation, OCR, or media understanding for check-in media.
- Mac Admin item/entry management.
- Separate Check-ins export UI.
- Suggested templates or preset items.
- Multi-device conflict resolution UI.
- Check-in-specific Calendar date-cell icons.
- Full item template/onboarding library.
- Real-device install from this feature worktree unless explicitly requested with a Sync Health/recovery checkpoint.

## Navigation And UI Shape

- Bottom tabs are ordered `Timeline / Calendar / Check-ins`.
- App launch still defaults to `Timeline`.
- Check-ins defaults to `Today`.
- `History` is a separate mode/switch inside Check-ins.
- `Manage Items` is the configuration surface, not the History surface.
- Empty Check-ins state shows one very short sentence plus a create button. No suggested templates are shown in v1.
- Daily use must remain one-tap: tapping the main item area immediately records.
- Adding note/media is a separate explicit action, such as a trailing content button.
- After one-tap creation, show short `Undo`. Undo removes the entry and all local surfaces immediately.
- Once-per-day completed items sink to the bottom of the scheduled Today list.
- Multiple-per-day items stay in their manual order after recording.
- Off-schedule items are folded under `Not scheduled today`.
- If an off-schedule item receives an entry today, it is temporarily shown at the bottom of the main Today list.

## Item Model

Each check-in item includes:

- Stable id.
- Name.
- Icon.
- Color.
- Record mode: `oncePerDay` or `multiplePerDay`.
- Active weekdays.
- Default `showInTimeline`.
- Manual sort order.
- Optional Smart Tag id, default nil.
- Archived/deleted state.

Creation requires only name, icon/color, record mode, weekdays, and default Timeline visibility. Tag association is visible at creation but defaulted to none. Reminders, content-type limits, and AI controls are not part of the first creation flow.

Items can be renamed, recolored, and re-iconed. Historical entries always display the current item name, icon, color, and tag. Items can be archived or deleted:

- Archive hides the item from Today but keeps historical entries.
- Delete soft-deletes the item and all entries, including Timeline/Calendar/Day Review visibility. This requires strong confirmation.

Manual item sorting controls Today order. Changing record mode is allowed; historical entries remain as facts, but future creation immediately follows the new mode. If an item changes from multiple-per-day to once-per-day and today already has multiple entries, those entries remain, but no further same-day entries are allowed.

## Entry Model

Each check-in entry includes:

- Stable id.
- Item id.
- `occurredAt`.
- Optional note.
- Optional media using the existing one-media-kind rule.
- `showInTimeline`.
- Created/updated/deleted timestamps.
- Sync/upload state.

One-tap entries may have no note and no media. `occurredAt` defaults to now but can be edited. Moving an entry across dates updates Calendar/Day Review placement and once-per-day uniqueness. Editing an entry to another item is allowed, with target item plus target local date uniqueness validation.

For once-per-day items, uniqueness is per item and local calendar date. If an edit moves an entry to a date where the target once-per-day item already has an entry, save is blocked or must be explicitly resolved; the app must not silently merge, overwrite, or create duplicates.

Canceling an entry is a soft delete. UI language may say `Cancel check-in`, while the sync model keeps tombstones.

`Show in Timeline` belongs to the entry. The item default is only the initial value for new entries. Changing an entry's item does not recompute `Show in Timeline`.

## Timeline And Day Review

Timeline becomes a mixed feed of ordinary Moments plus check-in entries where `showInTimeline=true`.

Timeline must not create ordinary `Post` rows for check-ins. It directly renders published check-in entries. Turning `Show in Timeline` off removes that entry from Timeline normal list, Timeline search, and Timeline filters, while preserving it in Check-ins, Calendar, and Day Review.

Timeline and Day Review use the same mixed display model:

- Entries with note/media render close to ordinary Moment rows.
- Empty semantic entries render as compact check-in markers.
- Tapping any check-in row opens `Check-in Entry Detail`.
- Check-in rows do not show comments, favorite, pin, AI summary, or transcript controls.

Timeline search includes ordinary Moments plus published check-ins only. Check-ins History has its own item/history search. Day Review includes all check-ins for that day regardless of Timeline visibility.

Timeline and Day Review add `Check-ins` as a content-type filter. Content-type chips use OR semantics. `Photos` includes photo Moments and photo Check-ins; `Check-ins` includes all check-in entries.

## Calendar And Review

Calendar heatmap counts combined activity:

- Each ordinary Moment counts as 1 activity unit.
- Each non-deleted check-in entry counts as 1 activity unit.
- Timeline visibility does not affect Calendar heatmap.

Month date cells do not show separate check-in icons. Check-ins are visible through heatmap, Day Review, and Month Stats.

Month Stats shows:

- Combined activity total.
- `Moments` count.
- `Check-ins` count.
- Completion counts by check-in item.

Month Stats should not show completion rate, streak, missed-day, or pressure-oriented habit metrics in v1.

Day Review mixed timeline shows ordinary Moments plus all check-in entries for that day, including entries hidden from Timeline.

Weekly Review may use check-in structure signals: item names, dates, and counts. It must not read check-in notes/media, generate check-in summaries, or run check-in AI tags. `Show in Timeline` does not affect Weekly Review input eligibility.

## Tags, AI, Media, And Diagnostics

Check-in items may optionally associate one Smart Tag. Default is no tag. Tags are not a daily-use entry point and should stay visually secondary. If a tag is associated with an item, all entries inherit it, including history and published Timeline rows. Timeline tag display/filtering for published check-ins follows the current item tag.

Check-in row identity uses item color/icon first. Smart Tag color does not override item color/icon.

Target behavior: check-in media should be stored, synced, viewed, and played, but must not enter AI summary, transcription, OCR, or AI tag pipelines.

Current implementation checkpoint: check-in note/empty entries are implemented first. Media attachment remains a follow-up because the existing media/upload/recovery pipeline is post-owned through `postId`; implementing check-in media without breaking the "check-ins are not ordinary Moments" boundary requires a separate check-in media parent model and upload/recovery semantics.

Media upload failure does not make the entry feel failed. Ordinary Check-ins, Timeline, and Day Review should not show strong upload failure warnings. Entry detail may show a light `Media not archived` style state. Full diagnosis/retry belongs in iOS Settings > Storage & Diagnostics / Sync diagnostics.

Mac Admin should not manage Check-ins in v1. New diagnostics should default to iOS-only unless they are Mac-local operations such as backup/restore, logs, process state, filesystem recovery, or maintenance jobs.

## Sync And Conflict Policy

Check-ins are complete local-first data:

- iPhone can create/edit/archive/delete items offline.
- iPhone can create/edit/cancel entries offline.
- Current checkpoint syncs item/entry metadata first; check-in media requires a follow-up media model before file sync.
- Operations enter the existing outbox and sync later.

Do not add multi-device conflict UI in v1. Apply operations in existing sync order / last-write-wins style.

Deleting an item is allowed even when entries have pending sync or media upload. Tombstones should cause pending work to stop, be skipped, or become harmless during later sync.

## Runtime And Worktree Safety

This feature is being implemented in a non-main worktree and must not overwrite the owner's daily iPhone app data.

Verification should use:

- Focused tests where practical.
- Generic iOS simulator/device-independent build.
- iOS Simulator with mock data for visible UI behavior.
- Isolated server/prisma checks if server sync schema is touched.

Do not run `npm run ios:device` from this feature worktree by default.

## Completion Bar

Implementation is complete only when:

- M012 design context and key decisions are committed.
- Server and iOS schemas include Check-in item/entry support.
- Local-first item/entry creation, update, cancel, archive/delete, sorting, and Timeline visibility are implemented.
- Timeline and Day Review render mixed check-in rows correctly.
- Calendar heatmap and Month Stats include Check-ins with the decided semantics.
- Check-ins tab supports Today, History, Manage Items, one-tap creation, content creation path, Undo, and entry detail.
- Check-ins do not run AI summary/transcription/tag pipelines.
- Settings diagnostics include check-in sync state at least at a lightweight level; media diagnostics remain follow-up with check-in media.
- Simulator mock-data validation proves Today, History, Timeline mixed rows, Calendar heatmap/Day Review inclusion, and entry detail editing.
- Fresh build/test evidence is recorded in the final handoff.
