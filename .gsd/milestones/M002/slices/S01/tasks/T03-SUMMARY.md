---
id: T03
parent: S01
milestone: M002
key_files:
  - ios/PrivateMoments/Models/TimelinePost.swift
  - ios/PrivateMoments/Persistence/LocalDatabase+Schema.swift
  - ios/PrivateMoments/Persistence/LocalDatabase+Records.swift
  - ios/PrivateMoments/Persistence/LocalDatabase+Sync.swift
  - ios/PrivateMoments/Persistence/LocalDatabase+Timeline.swift
  - ios/PrivateMoments/Persistence/TimelineStore+Payloads.swift
  - ios/PrivateMoments/Persistence/TimelineStore+ServerChanges.swift
  - ios/PrivateMoments/Persistence/TimelineStore+Mutations.swift
  - ios/PrivateMomentsTests/CommentSyncPayloadTests.swift
  - ios/PrivateMomentsTests/TimelineDateJumpModelsTests.swift
key_decisions:
  - Included parent `postId` in iOS delete-comment payloads so local status refresh can map comment outbox rows back to their parent post even though the sync entity id is the comment id.
  - Kept comment server-change parse errors strict but content-safe: messages name `comment_created`/`comment_deleted` and invalid field names without interpolating private comment text.
duration: 
verification_result: passed
completed_at: 2026-04-29T19:38:42.910Z
blocker_discovered: false
---

# T03: Added iOS local private comment persistence and sync plumbing for create/delete comment operations.

**Added iOS local private comment persistence and sync plumbing for create/delete comment operations.**

## What Happened

Implemented the iOS side of the private comment sync contract without adding visible UI. Added `TimelineComment` and carried comments on `TimelineItem`, created the `local_comments` SQLite table with soft-delete and post indexes, and added fetch/insert/apply helpers. Added local store methods and payload builders for `create_comment` and `delete_comment` outbox operations, including parent `postId` context so comment operation acceptance/rejection can refresh the parent moment status. Extended server-change application for `comment_created` and `comment_deleted` with strict required-field/date parsing while keeping error text at operation/change-type granularity rather than logging comment content. Added focused XCTest coverage for comment outbox payload encoding and updated the existing timeline fixture for the new comment collection.

## Verification

Ran the required iOS XcodeGen plus generic iOS build successfully. Also ran the `PrivateMoments` XCTest scheme on the `Private Moments iPhone 13 Pro` simulator; the new comment payload tests and existing timeline date jump tests passed. Slice-level observability requirement was checked by ensuring invalid comment server-change errors include `comment_created`/`comment_deleted` context but not the private comment text.

## Verification Evidence

| # | Command | Exit Code | Verdict | Duration |
|---|---------|-----------|---------|----------|
| 1 | `cd ios && xcodegen generate && xcodebuild -project PrivateMoments.xcodeproj -scheme PrivateMoments -destination generic/platform=iOS -configuration Debug CODE_SIGNING_ALLOWED=NO build` | 0 | ✅ pass — XcodeGen regenerated the project and the generic iOS app build succeeded. | 9300ms |
| 2 | `cd ios && xcodebuild test -project PrivateMoments.xcodeproj -scheme PrivateMoments -destination 'platform=iOS Simulator,name=Private Moments iPhone 13 Pro,OS=26.0.1'` | 0 | ✅ pass — 6 XCTest cases passed, including 2 new comment sync payload tests. | 52000ms |

## Deviations

Added a focused XCTest file beyond the plan’s compile-only verification because this task introduced durable payload builders and outbox shapes that should stay covered.

## Known Issues

No blocker. This task intentionally adds no visible comment UI; UI consumption remains for a later slice/task. Local database helpers are covered through build/tests but not yet exercised against a live server from iOS.

## Files Created/Modified

- `ios/PrivateMoments/Models/TimelinePost.swift`
- `ios/PrivateMoments/Persistence/LocalDatabase+Schema.swift`
- `ios/PrivateMoments/Persistence/LocalDatabase+Records.swift`
- `ios/PrivateMoments/Persistence/LocalDatabase+Sync.swift`
- `ios/PrivateMoments/Persistence/LocalDatabase+Timeline.swift`
- `ios/PrivateMoments/Persistence/TimelineStore+Payloads.swift`
- `ios/PrivateMoments/Persistence/TimelineStore+ServerChanges.swift`
- `ios/PrivateMoments/Persistence/TimelineStore+Mutations.swift`
- `ios/PrivateMomentsTests/CommentSyncPayloadTests.swift`
- `ios/PrivateMomentsTests/TimelineDateJumpModelsTests.swift`
