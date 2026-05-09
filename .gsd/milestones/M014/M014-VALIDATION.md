# M014 Validation: Check-ins Daily Reset Boundary

**Date:** 2026-05-09
**Status:** Verified checkpoint
**Worktree:** `/Users/popcornnnnnn/MacLocal/Projects/07-github/private-moments`
**Branch:** `main`

## Scope Verified

- Server schema version 17 adds synced `checkin_items.day_start_hour`.
- Legacy/missing `dayStartHour` payloads default to `0`.
- Invalid `dayStartHour` payloads are rejected unless the value is an integer from `0` through `23`.
- iOS once-per-day Check-ins use item-day boundaries for Today row lookup, duplicate prevention, active weekday evaluation, and Time Line grouping.
- Bed-style custom boundary works with a noon reset: `00:30` and `23:30` on the same calendar date are separate item days.
- Time Line tooltips continue to display the true occurrence date/time, not only the item-day bucket.

## Automated Verification

- `npm run server:prisma:generate` passed.
- `npm run server:typecheck` passed.
- `npm run server:test` passed: 58/58.
- `npm run admin:build` passed.
- `npm run server:build` passed.
- `npm run verify:ios:generic` passed.
- Focused iOS XCTest passed:
  - `PrivateMomentsTests/CheckInTimeInsightsTests`
  - `PrivateMomentsTests/CheckInDayBoundaryTests`
- `npm run verify:all` passed:
  - `server:typecheck`
  - `server:test` 58/58
  - `server:build`
  - `admin:build`
  - `verify:ios:generic`
  - `verify:uat-gates`
  - `git diff --check`

## Live Deployment Verification

- Live DB was backed up before migration:
  - `server/data/backups/manual/app-before-checkin-day-start-20260509-235949.sqlite`
- `npm run server:prisma:deploy` applied migration `20260509143000_checkin_day_start_hour`.
- LaunchAgent server was restarted.
- Local health check returned schema version `17`.
- `npm run ios:preflight` passed before real-device install.
- `npm run ios:device` built, signed, installed, and launched `com.popcornnnnnn.privatemoments` on `wwz 的 iphone`.

## Residual Notes

- `verify:all` still reports the existing open UAT gate `UAT-M013-CONTINUITY-POLISH`; this is unrelated to the M014 schema and Check-ins day-boundary change.
- Real-device preflight still reports 3 historical rejected operations as a warning; no active pending outbox or active media upload blocker was reported.
