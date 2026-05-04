# M003: Feed Comments — Validation

**Date:** 2026-04-30

## Passed

- `npm run server:build`
  - TypeScript server build passed.
- `npm run server:prisma:migrate`
  - Applied `20260430213000_feed_comments` to `server/data/app.sqlite`.
  - Prisma Client regenerated successfully.
- Current-code health check on temporary server:
  - `PORT=3211 HOST=127.0.0.1 npm run server:start`
  - `curl -fsS http://127.0.0.1:3211/api/v1/health`
  - Response reported `schemaVersion: 4`.
- Sync smoke against temporary port 3211:
  - Login succeeded with schema version 4.
  - `create_post` + `create_comment` accepted and emitted `comment_created`.
  - `delete_comment` accepted and emitted `comment_deleted`.
  - `create_comment` against a deleted parent post was rejected.
  - Parent `delete_post` soft-deleted its child comment and emitted `post_deleted` without an extra `comment_deleted`.
  - SQLite inspection confirmed both direct-deleted and parent-cascaded test comments had non-null `deleted_at`.
- `cd ios && xcodebuild -project PrivateMoments.xcodeproj -scheme PrivateMoments -destination 'platform=iOS Simulator,name=iPhone 17' test`
  - 9 tests passed, including 4 `TimelineCommentsDisplayTests`.
- `cd ios && xcodebuild -project PrivateMoments.xcodeproj -scheme PrivateMoments -destination generic/platform=iOS -configuration Debug CODE_SIGNING_ALLOWED=NO build`
  - Generic iOS Debug build passed.
- `npm run admin:build`
  - Admin TypeScript and Vite build passed.
- `npm run ios:device`
  - Real-device Debug build passed.
  - App installed on paired iPhone.
  - Later retry after unlocking the phone installed and launched successfully:
    - `Moments is installed and launched on wwz 的 iphone.`

## 2026-04-30 Comment Send Feedback Fix

- Changed send-success scrolling from the nested comment-row anchor to the parent moment row with `.bottom` anchor, because SwiftUI `List` does not reliably expose nested row IDs to `ScrollViewReader`.
- The send path now issues two delayed row-bottom scroll requests after local comment creation, comment expansion, and input closure so keyboard/safe-area layout changes have settled.
- `cd ios && xcodebuild -project PrivateMoments.xcodeproj -scheme PrivateMoments -destination generic/platform=iOS -configuration Debug CODE_SIGNING_ALLOWED=NO build`
  - Passed after the row-level send-success scroll change.
- `cd ios && xcodebuild -project PrivateMoments.xcodeproj -scheme PrivateMoments -destination 'platform=iOS Simulator,name=iPhone 17' test`
  - Passed 9 tests, 0 failures.
- `npm run ios:device`
  - Current code built, installed, and launched on `wwz 的 iphone`.
  - `Moments is installed and launched on wwz 的 iphone.`

## Remaining UAT

- On the paired iPhone, manually verify:
  - Tap feed comment button and confirm bottom input focuses on the correct target.
  - Create a comment and confirm it appears immediately under the correct moment.
  - Send a comment and confirm the input closes while the timeline moves to the bottom of that moment and the newest comment is visible.
  - Expand/collapse comments in place.
  - Search by comment text and confirm the matching comment is visible.
  - Long-press a comment, confirm pressed/haptic feedback, confirm `Delete comment?`, and confirm only the comment is deleted.
