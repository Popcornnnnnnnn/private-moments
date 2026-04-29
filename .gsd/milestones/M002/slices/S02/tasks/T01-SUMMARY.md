---
id: T01
parent: S02
milestone: M002
key_files:
  - ios/PrivateMoments/Views/MomentCommentsSection.swift
  - ios/PrivateMomentsTests/MomentCommentUITests.swift
key_decisions:
  - Kept MomentCommentDraftPolicy independent of SwiftUI, SQLite, and network so comment draft behavior remains deterministic and unit-testable.
duration: 
verification_result: passed
completed_at: 2026-04-29T19:47:28.050Z
blocker_discovered: false
---

# T01: Added deterministic comment draft policy tests for trimming, submit eligibility, and plain-text-only behavior.

**Added deterministic comment draft policy tests for trimming, submit eligibility, and plain-text-only behavior.**

## What Happened

Created `MomentCommentDraftPolicy` as a small Foundation-only helper that exposes boundary trimming, submit eligibility, and optional submission text without interpreting Markdown or adding reply semantics. Added `MomentCommentUITests` in the existing `PrivateMomentsTests` target using XCTest and `@testable import PrivateMoments`, covering empty drafts, whitespace/newline-only drafts, leading/trailing trim, preservation of internal newlines and bullets, Markdown-like plain strings, and reply-like text remaining ordinary text. Ran the slice verification command; XcodeGen regenerated the project and xcodebuild executed the full PrivateMoments unit-test suite successfully on the iPhone 16 simulator.

## Verification

Ran `cd ios && xcodegen generate && xcodebuild test -project PrivateMoments.xcodeproj -scheme PrivateMoments -destination 'platform=iOS Simulator,name=iPhone 16'`. The command exited 0 with `** TEST SUCCEEDED **`; the suite executed 12 tests with 0 failures, including 6 new `MomentCommentUITests`.

## Verification Evidence

| # | Command | Exit Code | Verdict | Duration |
|---|---------|-----------|---------|----------|
| 1 | `cd ios && xcodegen generate && xcodebuild test -project PrivateMoments.xcodeproj -scheme PrivateMoments -destination 'platform=iOS Simulator,name=iPhone 16'` | 0 | ✅ pass | 36300ms |

## Deviations

None.

## Known Issues

None.

## Files Created/Modified

- `ios/PrivateMoments/Views/MomentCommentsSection.swift`
- `ios/PrivateMomentsTests/MomentCommentUITests.swift`
