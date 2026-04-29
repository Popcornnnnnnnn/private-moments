# S01: Comment data model and sync contract — UAT

**Milestone:** M002
**Written:** 2026-04-29T19:41:40.467Z

# S01 UAT — Comment Data Model and Sync Contract

This slice has no visible UI by design.

## Scripted/Build Evidence

- Server comment sync smoke test from T02 created a post, created a comment, replayed the create operation idempotently, and deleted the comment.
- iOS generic build passed after local comment persistence and payload plumbing were added.
- iOS XCTest payload tests passed for `create_comment` and `delete_comment` payload shapes.

## Manual UI Expectation

No new UI should appear in the main timeline or detail view from S01 alone. Visible comment creation/deletion belongs to S02.

## Remaining UAT For Later Slices

After S02, use a real iPhone to create a comment from moment detail, verify it displays only in detail, delete it, and confirm the main timeline row remains uncluttered.
