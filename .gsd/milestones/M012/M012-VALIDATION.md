# M012 Validation: Check-ins

**Validated:** 2026-05-08
**Worktree:** `/Users/popcornnnnnn/.codex/worktrees/c75e/private-moments`
**Branch:** `codex/checkins-module`
**Scope:** Current checkpoint implements local-first check-in items/entries, sync metadata, iOS Check-ins UI, Timeline publishing, Calendar/Day Review/Month Stats integration, and lightweight iOS diagnostics. Check-in-owned media attachment is intentionally left as a follow-up because the existing media pipeline is post-owned.

## Automated Verification

- `npm run server:typecheck` passed.
- `npm run server:test` passed: 30/30 Node tests.
- `npm run server:build` passed.
- `npm run admin:build` passed.
- `DATABASE_URL='file:/tmp/private-moments-m012-verify.db' npm run server:prisma:deploy` passed after pre-creating the temporary SQLite file, applying all 15 migrations through `20260508160000_checkins`.
- `xcodebuild test -project PrivateMoments.xcodeproj -scheme PrivateMoments -destination id=1FD6368F-8CB5-4736-9682-AE8DF38A0CC9 -only-testing:PrivateMomentsTests/CalendarReviewModelsTests` passed: 8/8 tests.
- `xcodebuild test -project PrivateMoments.xcodeproj -scheme PrivateMoments -destination id=1FD6368F-8CB5-4736-9682-AE8DF38A0CC9 -only-testing:PrivateMomentsTests/TimelineDateJumpModelsTests` passed: 5/5 tests.
- `xcodebuild -project PrivateMoments.xcodeproj -scheme PrivateMoments -destination generic/platform=iOS -configuration Debug CODE_SIGNING_ALLOWED=NO build` passed.

## Simulator Mock-Data Verification

Simulator: `Private Moments Pinned iPhone 17` (`1FD6368F-8CB5-4736-9682-AE8DF38A0CC9`)

Launch path:

- Uninstalled `com.popcornnnnnn.privatemoments` from the simulator for an isolated runtime.
- Built simulator app with XcodeBuildMCP.
- Manually installed `/Users/popcornnnnnn/Library/Developer/XcodeBuildMCP/workspaces/private-moments-a82def837100/DerivedData/PrivateMoments-9ccd4c5a116f/Build/Products/Debug-iphonesimulator/PrivateMoments.app`.
- Launched `com.popcornnnnnn.privatemoments` with `--private-moments-checkins-mock`.

Observed UI evidence:

- Default launch opened `Timeline`, not `Check-ins`.
- Timeline rendered compact check-in rows for `Wake up` and prior `Workout`.
- Hidden `Meal` check-in did not render in Timeline.
- `Check-ins` tab opened `Today` by default with `Workout`, `Meal`, and `Wake up`.
- `History` switch showed weekly/month/item counts and all three mock entries, including hidden `Meal`.
- `Manage` opened item management with `Wake up`, `Workout`, and `Meal`.
- Calendar heatmap showed May 7 with 1 item and May 8 with 2 items before the one-tap interaction.
- Calendar Day Review for May 8 showed `2 items` and `2 check-ins`, including hidden `Meal`.
- Calendar Month Stats showed `3 check-ins`, `0 moments`, active days, busiest day, and daily rhythm bars.
- One-tap on today's `Workout` recorded immediately without opening a sheet and displayed the `Checked in` undo bar.

Screenshots captured during validation:

- `/tmp/private-moments-checkins-today.png`
- `/tmp/private-moments-checkins-history.png`
- `/tmp/private-moments-calendar-checkins.png`
- `/tmp/private-moments-calendar-month-stats-checkins.png`
- `/tmp/private-moments-checkins-one-tap.png`

SQLite evidence after one-tap:

```text
items|3
entries|4
Workout|Evening run|1
Wake up||1
Meal|Lunch|0
Workout||1
timeline_visible_entries|3
hidden_entries|1
```

This proves:

- Check-in entries are independent local rows.
- Entry-level Timeline visibility is separate from entry existence.
- Hidden entries remain present in local history and Calendar-derived counts.
- One-tap records an empty semantic check-in.

## Known Limitation

Check-in media attachment is not implemented in this checkpoint. The current app media model, upload route, recovery logic, and server-side AI summary pipeline are owned by ordinary `postId` media. A correct follow-up should add check-in-owned media semantics instead of creating fake posts or reusing ordinary post media in a way that would break Timeline visibility independence.

No real iPhone install was performed from this feature worktree, by design.
