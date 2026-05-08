# M011: Pinned Moments — Validation

## 2026-05-08 Design Checkpoint

Scope: design and planning only. No app/server implementation was changed in this checkpoint.

Evidence:

- Created dedicated worktree `/Users/popcornnnnnn/.codex/worktrees/private-moments-pinned`.
- Created branch `codex/pinned-moments-design` from the `main` commit that was current at creation time: `6eda03e`.
- Kept the original `main` worktree at `/Users/popcornnnnnn/MacLocal/Projects/07-github/private-moments` out of scope so it can continue normal development independently.
- Recorded M011 product, sync, schema, UI, and verification boundaries in `.gsd/milestones/M011/`.

Checks intentionally not run:

- No `npm run ios:device`, because installing from a feature worktree would update the same `Moments` bundle/container used by the daily app.
- No live server restart, because the feature worktree must not touch the owner's active `3210` live archive.
- No build verification during the initial design checkpoint, because that checkpoint changed only documentation and planning files.

Next implementation verification must use an isolated server port/data directory before any real-device install. Simulator validation is primarily for UI and interaction behavior; sync/data correctness must still be proven by focused tests and isolated server smoke.

## 2026-05-08 Simulator Launch Validation

Scope: non-main worktree simulator validation, no real-device install.

Evidence:

- Created and booted a dedicated simulator: `Private Moments Pinned iPhone 17`, UDID `1FD6368F-8CB5-4736-9682-AE8DF38A0CC9`.
- Regenerated `ios/PrivateMoments.xcodeproj` with XcodeGen in this worktree.
- Built simulator target with:

```bash
cd ios
xcodebuild -project PrivateMoments.xcodeproj \
  -scheme PrivateMoments \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=1FD6368F-8CB5-4736-9682-AE8DF38A0CC9' \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Result: `** BUILD SUCCEEDED **`.

- Installed `/Users/popcornnnnnn/.codex/worktrees/private-moments-pinned/ios/build/Build/Products/Debug-iphonesimulator/PrivateMoments.app` into the dedicated simulator.
- Before launch, set simulator-local `serverURLString` to `http://127.0.0.1:3211` so this simulator install does not default to the live `3210` server.
- Launched bundle `com.popcornnnnnn.privatemoments` successfully in simulator, process id `61884`.
- Screenshot confirmed the app opened to the unauthenticated Timeline state with `Log in to sync`.
- Re-read simulator-local `serverURLString` after launch and confirmed it remained `http://127.0.0.1:3211`.

Limitations:

- The isolated server on `3211` was not started in this checkpoint because this new worktree does not have Node dependencies installed yet; `prisma migrate deploy` failed with `prisma: command not found`.
- XcodeBuildMCP accessibility hierarchy capture failed, but screenshot capture succeeded and verified visible launch state.
- This validation did not exercise sync, login, media, Share Extension, or real-device behavior.
- No `npm run ios:device` was run.

## 2026-05-08 Grill-Me Decision Checkpoint

Scope: product and verification decisions for implementation. No app/server implementation was changed in this checkpoint.

Resolved decisions:

- Pin state is synced post metadata.
- Pinned appears only on the main Timeline when no search/filter state is active.
- Pinned defaults to a collapsed `Pinned · N` summary header.
- With one to three pinned moments, tapping the header expands/collapses title rows and remembers that state locally.
- With more than three pinned moments, tapping the header opens a bottom sheet with the full pinned title list.
- The pinned sheet uses internal navigation; selecting a row pushes full `MomentDetailView` inside the sheet.
- Pinned title rows show title plus a light occurred-date accessory, not body/media/comment/tag previews.
- Pin/unpin lives in Moment Detail `More`, Timeline row context menu, and pinned sheet row context menu.
- Pin and favorite are independent.
- Pending/failed/partial/synced local moments can be pinned or unpinned.
- Deleted moments disappear from pinned surfaces without an extra unpin operation.
- Calendar, Day Review, and Weekly Review do not gain pinned entry points.
- Conflicts use last server-accepted operation wins.
- Implementation verification uses simulator UI/interaction validation plus isolated server/test validation, with no real-device install by default.

## 2026-05-08 Implementation Validation Checkpoint

Scope: implemented M011 in the dedicated feature worktree. No real-device install was run, and the live `3210` server/archive was not touched.

Automated verification:

- `npm run server:typecheck` passed.
- `npm run server:test` passed: 30 server tests, 0 failures.
- `npm run server:build` passed.
- `npm run admin:build` passed.
- `git diff --check` passed.
- `npm run verify:uat-gates` passed as a report command and showed 11 gates total, 1 open: `UAT-M011-PINNED-MOMENTS`.
- Generic iOS Debug build passed:

```bash
cd ios
xcodegen generate
xcodebuild -project PrivateMoments.xcodeproj \
  -scheme PrivateMoments \
  -destination generic/platform=iOS \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  build
```

- iOS simulator tests passed on `Private Moments Pinned iPhone 17` (`1FD6368F-8CB5-4736-9682-AE8DF38A0CC9`): 41 tests, 0 failures.

Isolated server/data smoke:

- Applied all 14 Prisma migrations into isolated SQLite:

```bash
DATABASE_URL=file:../../.tmp/pinned-smoke-data/app.sqlite \
  npx prisma migrate deploy --schema server/prisma/schema.prisma
```

- Started compiled server on isolated `PORT=3211` with isolated `PRIVATE_MOMENTS_DATA_DIR=/Users/popcornnnnnn/.codex/worktrees/private-moments-pinned/.tmp/pinned-smoke-data`.
- `GET http://127.0.0.1:3211/api/v1/health` returned `schemaVersion: 13` and the isolated data directory.
- Authenticated sync smoke accepted `create_post` and `update_post_pin` with 0 rejected operations.
- `update_post_pin` emitted `post_pin_updated`; `GET /api/v1/posts/post-pin-smoke-1` returned `isPinned: true` and `pinnedAt: 2026-05-08T03:37:00.000Z`.

Simulator UI/interaction validation:

- Rebuilt and installed only the simulator app into dedicated simulator `1FD6368F-8CB5-4736-9682-AE8DF38A0CC9`; no `npm run ios:device` was run.
- Seeded simulator-local SQLite with pinned and unpinned local posts to validate UI state without touching live data.
- Confirmed with accessibility hierarchy that with 4 pinned moments, unfiltered Timeline shows `Pinned 4` plus ordinary chronological rows, including pinned rows that remain in place with pin state UI.
- Tapping `Pinned 4` opened the `Pinned` sheet with four title rows: `Pinned Alpha`, `Pinned Beta`, `Plain pinned title line`, and `Pinned Delta`.
- Selecting `Pinned Alpha` in the sheet pushed full `MomentDetailView` inside the sheet navigation stack.
- After changing simulator-local data to 2 pinned moments, Timeline showed collapsed `Pinned 2`; tapping it expanded exactly the two title rows and kept them as title/date rows rather than full Timeline rows.
- 2026-05-08 follow-up: rebuilt and reinstalled the worktree build into the dedicated simulator after changing the row-retention behavior. The simulator initially had a stale standalone Share Extension install conflict; uninstalling the dedicated simulator's test app/extension fixed installation without touching any real iPhone.
- Seeded simulator-local SQLite with 5 pinned posts and 1 unpinned post. Accessibility hierarchy confirmed the unfiltered Timeline shows `Pinned 5`, then ordinary chronological rows including pinned rows such as `Pinned Alpha`, `Plain pinned title line`, `Pinned Delta`, and `Pinned Echo`; those pinned rows expose the `pin.fill` image with accessibility label `Pinned`.

Main deploy and real-device UAT:

- Main deploy follow-up on 2026-05-08: merged `codex/pinned-moments-design` into `main` as `49e3c5f`, applied `20260508130000_pinned_posts` to the live Mac SQLite database, restarted `com.private-moments.server`, and confirmed `GET /api/v1/health` returns `schemaVersion: 13`.
- Before true-device install, created recovery checkpoint `.tmp/deploy-checkpoints/20260508-121602` with a Mac SQLite backup plus copied iPhone app data container. Pre-install iPhone checks showed 127 visible local posts, 0 pending/failed outbox operations, 0 missing visible media, and 3 pre-existing pending media uploads.
- Installed and launched the merged main build on `wwz 的 iphone` with bundled fallback `https://moments.popcornnn.xyz`. Post-install iPhone database copy confirmed `local_posts.isPinned` and `local_posts.pinnedAt` exist, 127 visible posts remain, outbox remains 0, and the same 3 media uploads remain pending for the normal upload queue.
- 2026-05-08: the owner confirmed the Pinned Moments real-use UAT is complete; `docs/UAT-GATES.md` closed `UAT-M011-PINNED-MOMENTS`.

Known limitations:

- Context-menu pin/unpin visual presentation was implemented and compiled, but simulator validation focused on header, sheet, title-row expansion, and sheet detail navigation because those are the primary UI/interaction paths for this checkpoint.
