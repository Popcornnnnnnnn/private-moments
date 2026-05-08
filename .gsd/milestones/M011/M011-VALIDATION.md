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

Next implementation verification must use an isolated server port/data directory before any real-device install.

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
