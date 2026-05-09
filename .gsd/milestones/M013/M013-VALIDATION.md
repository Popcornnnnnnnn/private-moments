# M013 Validation: Continuity Polish And Maintenance Loop

**Validated:** 2026-05-09
**Branch:** `main`
**Scope:** Check-ins heatmap interaction, Day Review check-ins rhythm strip, Weekly Review v2 quality calibration, real-device install preflight, Backup Status visibility, and small SwiftUI component extraction.

## Expected Verification

- `npm run server:typecheck`
- `npm run server:test`
- `npm run admin:build`
- Focused iOS XCTest for `CheckInTimeInsightsTests` and `CalendarReviewModelsTests`
- `npm run verify:ios:generic`
- `npm run ios:preflight` when the live Mac server is reachable
- `npm run verify:all`
- `npm run ios:device` from `main` with preflight enabled

## Evidence

- `node --check scripts/preflight-ios-device.mjs` passed.
- `npm run server:typecheck` passed.
- `npm run server:test` passed: 55/55 Node tests.
- `npm run admin:build` passed.
- `npm run verify:ios:generic` passed.
- Focused XCTest passed with exit code 0 using:

```bash
cd ios && xcodebuild -quiet -project PrivateMoments.xcodeproj -scheme PrivateMoments -destination 'platform=iOS Simulator,id=006069EA-BA9A-4689-9C52-36A74F279704' -derivedDataPath /tmp/PrivateMoments-M013Tests -only-testing:PrivateMomentsTests/CheckInTimeInsightsTests -only-testing:PrivateMomentsTests/CalendarReviewModelsTests test
```

- `npm run ios:preflight` passed against local `http://127.0.0.1:3210`: server reachable, schema `16` matches expected `16`, no running maintenance job, no unapplied server sync operations, server media rows uploaded/deleted, latest backup job present, paired iPhone listed. It reported one non-blocking warning for 3 historical rejected operations.
- `npm run verify:all` passed. It reported `UAT gates: 12 total, 1 open` for `UAT-M013-CONTINUITY-POLISH`, as expected.
- `npm run ios:device` passed from `main` with the new preflight enabled. The preflight selected `http://100.114.41.22:3210`, then build/sign/install/launch succeeded on `wwz 的 iphone`; installed bundle id `com.popcornnnnnn.privatemoments`, installation URL `file:///private/var/containers/Bundle/Application/46BFE89F-B30C-4551-B488-33A55B792F29/PrivateMoments.app/`.

## Known UAT Gap

`UAT-M013-CONTINUITY-POLISH` remains open until the user confirms the real-phone feel of heatmap exploration, Day Review rhythm, Backup Status readability, and Weekly Review quality on recent data.
