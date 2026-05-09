# M013: Continuity Polish And Maintenance Loop

**Gathered:** 2026-05-09
**Status:** Implementation checkpoint in progress on `main`
**Worktree:** `/Users/popcornnnnnn/MacLocal/Projects/07-github/private-moments`
**Branch:** `main`
**Depends on:** M008 Calendar Review, M009 Archive/Sync Health, M010 Weekly Review, M012 Check-ins, iOS Settings diagnostics, real-device deployment script, and regression-test infrastructure.

## Project Description

M013 is a small continuity and reliability pass after Timeline, Calendar, and Check-ins have become the three large user-facing surfaces. It does not add a new primary module. It makes the existing surfaces easier to read and safer to deploy:

- Check-ins heatmap buckets become selectable and reveal the underlying records.
- Day Review gets a lightweight chronological check-ins rhythm strip.
- Weekly Review prompt validation becomes more conservative and rejects broken anchors.
- Real iPhone install gets a preflight check for live server/schema/queues/device visibility.
- iOS Settings adds a focused read-only Backup Status page.
- Large SwiftUI files are kept from growing by extracting new check-in and backup UI into dedicated components.

## Product Boundary

This checkpoint deliberately avoids reminders, goals, streaks, AI interpretation of check-ins, privacy-lock work, new schema migrations, and new sync operations. It also keeps backup/restore execution in Mac Admin; the phone only shows daily read-only status.

## User-Visible Outcome

- In a `Time Heatmap` item insight, the user can tap a 24h bucket or drag across weekday/hour rows to see the exact time bucket, count, and recent records in that bucket.
- Tapping a record from the selected heatmap bucket opens the existing check-in entry detail page.
- Calendar Day Review shows the day's check-ins as a compact chronological rhythm strip near the top, before the full mixed timeline.
- Weekly Review v2 avoids unsupported generic claims and filters `Worth Revisiting` anchors to input moments that actually exist.
- `npm run ios:device` now runs a local preflight after choosing the server URL and before building/installing.
- Settings > Storage & Diagnostics > Diagnostics exposes `Backup Status` as a focused read-only page for repository, latest job, latest snapshot, and recovery file paths.

## Verification Intent

- Focused Swift unit tests cover heatmap bucket selection and Day Review check-in rhythm ordering.
- Server tests cover Weekly Review v2 prompt/version behavior and invalid anchor filtering.
- Routine full verification should include `server:typecheck`, `server:test`, `admin:build`, `verify:ios:generic`, `verify:all`, `ios:preflight` when a live server is reachable, and real iPhone install from `main`.
- Human UAT remains needed for the feel of the heatmap drag/tap interaction, the Day Review rhythm strip, and Backup Status readability on the real phone.
