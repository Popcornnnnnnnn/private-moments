---
estimated_steps: 1
estimated_files: 6
skills_used: []
---

# T03: Add iOS local comment sync plumbing

Add iOS local comment persistence and sync payload support without visible UI: SQLite schema migration, comment records, outbox operations, API models, TimelineStore apply/send logic.

## Inputs

- `T01 implementation map`
- `T02 operation shapes`

## Expected Output

- `iOS local comment schema/records`
- `iOS sync payload support`
- `Compilation evidence`

## Verification

cd ios && xcodegen generate && xcodebuild -project PrivateMoments.xcodeproj -scheme PrivateMoments -destination generic/platform=iOS -configuration Debug CODE_SIGNING_ALLOWED=NO build

## Observability Impact

Ensure existing store error messages preserve comment operation context without leaking content unnecessarily.
