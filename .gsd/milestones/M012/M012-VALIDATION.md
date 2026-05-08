# M012 Validation: Check-ins

**Validated:** 2026-05-08
**Feature worktree:** `/Users/popcornnnnnn/.codex/worktrees/c75e/private-moments`
**Feature branch:** `codex/checkins-module`
**Main merge commit:** `1ae0313 Merge check-ins module`
**Scope:** Current checkpoint implements local-first check-in items/entries/image media, sync metadata, independent check-in media upload/recovery, iOS Check-ins UI, Timeline publishing, Calendar/Day Review/Month Stats/Photos filter integration, History item filtering, and lightweight iOS diagnostics. Check-in audio/video media remains out of scope.

## Automated Verification

- `npm run server:typecheck` passed.
- `npm run server:test` passed: 30/30 Node tests.
- `npm run server:build` passed.
- `npm run admin:build` passed.
- Isolated check-in media upload smoke passed against a temporary SQLite/data directory initialized from migrations: login, `/api/v1/sync` created a check-in item and entry, `/api/v1/checkin-media/upload` uploaded one PNG, and `/api/v1/checkin-media/batch-download` returned the uploaded image as base64.
- Local `sqlite3` migration replay passed through `20260508190000_checkin_media`. `prisma migrate deploy` against a temporary SQLite URL returned a blank local schema-engine error in this environment, so the runtime smoke used direct migration replay for the isolated database.
- `xcodebuild test -project PrivateMoments.xcodeproj -scheme PrivateMoments -destination id=1FD6368F-8CB5-4736-9682-AE8DF38A0CC9 -only-testing:PrivateMomentsTests/CalendarReviewModelsTests` passed: 8/8 tests.
- `xcodebuild test -project PrivateMoments.xcodeproj -scheme PrivateMoments -destination id=1FD6368F-8CB5-4736-9682-AE8DF38A0CC9 -only-testing:PrivateMomentsTests/TimelineDateJumpModelsTests` passed: 5/5 tests.
- `xcodebuild -project PrivateMoments.xcodeproj -scheme PrivateMoments -destination generic/platform=iOS -configuration Debug CODE_SIGNING_ALLOWED=NO build` passed.
- After merge to `main`, `npm run server:prisma:generate && npm run verify:server` passed.
- After merge to `main`, `npm run verify:ios:generic` passed.

## Main Deployment Verification

- Merged `codex/checkins-module` into `main` as `1ae0313 Merge check-ins module`.
- Created a live SQLite backup before migration: `server/data/backups/manual/app-before-checkins-20260508-221014.sqlite`.
- Ran `npm run server:prisma:deploy` against the live server database; migrations `20260508160000_checkins` and `20260508190000_checkin_media` applied successfully.
- Restarted the LaunchAgent-managed server with `launchctl kickstart -k gui/$(id -u)/com.private-moments.server`.
- `GET http://127.0.0.1:3210/api/v1/health` returned `schemaVersion: 15` after restart.
- `npm run ios:device` built, signed, installed, and launched `com.popcornnnnnn.privatemoments` on `wwz 的 iphone`.
- Device install reported bundle id `com.popcornnnnnn.privatemoments` and installation URL `file:///private/var/containers/Bundle/Application/2B8340D6-8DF2-4BC4-9D42-915C2063E638/PrivateMoments.app/`.
- Device launch succeeded through `xcrun devicectl device process launch`.

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
- Timeline and Day Review no longer show a redundant gray `Check-in` label, and entries without note/media no longer show `Checked in` fallback text.
- Hidden `Meal` check-in did not render in Timeline.
- `Check-ins` tab opened `Today` by default with `Workout`, `Meal`, and `Wake up`.
- `History` switch showed weekly/month/item counts and all three mock entries, including hidden `Meal`.
- `History` item filter selected `Meal` and reduced the list to the single Meal entry.
- Hidden `Meal` included a mock image media thumbnail in History.
- `Manage` opened item management with `Wake up`, `Workout`, and `Meal`.
- Calendar heatmap showed May 7 with 1 item and May 8 with 2 items before the one-tap interaction.
- Calendar Day Review for May 8 showed `2 items`, `1 photo`, and `2 check-ins`, including hidden `Meal` with its image.
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
checkin_media|1
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
- Check-in image media is separate from ordinary post media and appears in History/Day Review/Photos surfaces even when the entry is hidden from Timeline.

## Known Limitation

Simulator cannot exercise the real camera hardware picker. The camera path compiled and the UI reserves it for real devices; simulator validation used seeded mock image media and direct SQLite/file checks. Check-in audio/video media is intentionally not implemented in this checkpoint.

No real iPhone install was performed from the feature worktree, by design. Real-device deployment happened only after merge to `main`.
