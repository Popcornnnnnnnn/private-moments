# M014: Check-ins Daily Reset Boundary

**Gathered:** 2026-05-09
**Status:** Implementation checkpoint in progress on `main`
**Worktree:** `/Users/popcornnnnnn/MacLocal/Projects/07-github/private-moments`
**Branch:** `main`
**Depends on:** M012 Check-ins, M013 Time Insights, sync schema version 16, iOS Check-ins Today row, and item insights Time Line.

## Problem

The original once-per-day Check-ins logic used natural local calendar days. That works for Get up, but it is wrong for Bed-style sleep records:

- A 00:30 bedtime belongs to the previous night's sleep cycle.
- A 23:30 bedtime on the same calendar date belongs to the next night's sleep cycle.
- Natural midnight reset treats both as the same day, blocking the second record and making Time Line grouping misleading.

## Product Decision

Add item-level `Daily reset` / `dayStartHour` metadata:

- Default is `00:00`, preserving current behavior for existing and new ordinary items.
- Once-per-day items can choose any hour from `00:00` to `23:00`.
- Bed-like items should use `12:00` so the item day runs noon to noon.
- Multiple-per-day items keep `dayStartHour = 0`; their Time Heatmap remains based on actual occurrence hours.

## User-Visible Outcome

- Manage item editor shows `Daily reset` for once-per-day items.
- Today row and one-tap duplicate checks use the item day boundary.
- Active weekdays are evaluated from the item day start.
- Time Line groups by item day but tooltips still show the true occurrence date and time.

## Technical Scope

- Server schema adds `checkin_items.day_start_hour`, schema version 17.
- Sync payload/server changes/export-import include `dayStartHour`.
- iOS local schema adds `local_checkin_items.dayStartHour`.
- Time Line aggregation uses `CheckInDayBoundary` instead of natural `startOfDay`.
- Focused server and iOS tests cover legacy default, invalid values, custom day grouping, and duplicate detection.
