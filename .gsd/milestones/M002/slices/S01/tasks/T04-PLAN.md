---
estimated_steps: 1
estimated_files: 3
skills_used: []
---

# T04: Verify and close comment sync contract slice

Run slice-level integration checks, reconcile docs/contracts, and record S01 summary with remaining risks for UI slice.

## Inputs

- `T02/T03 verification output`
- `shared/sync-protocol.md`
- `shared/openapi.yaml`

## Expected Output

- `S01 verification evidence`
- `Known limitations for S02`
- `Updated .gsd/doc artifacts if needed`

## Verification

npm run server:build && cd ios && xcodegen generate && xcodebuild -project PrivateMoments.xcodeproj -scheme PrivateMoments -destination generic/platform=iOS -configuration Debug CODE_SIGNING_ALLOWED=NO build

## Observability Impact

Document any new diagnostic surfaces or confirm existing sync diagnostics are sufficient.
