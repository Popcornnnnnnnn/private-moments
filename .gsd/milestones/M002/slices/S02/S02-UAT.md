# S02: Private comments in Moment detail — UAT

**Milestone:** M002
**Written:** 2026-04-29T19:54:52.642Z

# S02 UAT: Private comments in Moment detail

## Preconditions

- Install a build containing S02 on an iPhone or simulator.
- The app has at least one visible, non-deleted moment in the timeline.
- The moment can be opened into Moment detail.
- For sync-state observations, the normal Mac server/Tailscale setup may be used, but full cross-device sync validation is deferred to S03.

## Test Case 1 — Comments are detail-only

1. Open the main timeline.
   - Expected: Timeline rows show the existing moment content/date/media/favorite surfaces only.
   - Expected: No comment count, comment badge, comment preview, or comment search UI is visible.
2. Tap a moment to open Moment detail.
   - Expected: A private comments section appears below the existing moment content/media area.
   - Expected: If the moment has no comments, the section shows a quiet empty state rather than timeline clutter.

## Test Case 2 — Whitespace-only drafts cannot submit

1. In the Moment detail comments draft field, enter only spaces/newlines.
   - Expected: The submit control remains disabled.
2. Attempt to submit if possible.
   - Expected: No comment is created and no outbox operation should be triggered.

## Test Case 3 — Add a plain-text comment

1. Enter a draft with leading/trailing whitespace and internal plain-text structure, for example:

   ```text
     first line
   - literal bullet
   **not markdown**  
   ```

2. Tap the submit/add control.
   - Expected: The operation calls the existing comment create path.
   - Expected: The saved/rendered row trims only the outer whitespace.
   - Expected: Internal newlines, bullets, and Markdown-like characters remain literal plain text; no Markdown/rich-text rendering appears.
   - Expected: The draft clears only after the create operation succeeds.
3. If the create operation fails due to connection/server state, observe the draft field.
   - Expected: The typed draft remains visible so the user can retry.
   - Expected: Any failure is surfaced through the existing store error path, without logging the private comment body.

## Test Case 4 — Comment ordering and row status

1. Add two comments to the same moment in sequence.
   - Expected: Comments render in the order supplied by local storage, oldest first.
2. Observe rows while sync is pending or after sync completes.
   - Expected: Any status shown is lightweight existing sync status, not a social/public metadata surface.

## Test Case 5 — Confirmed delete

1. Tap the delete affordance for one comment.
   - Expected: A centered confirmation alert appears before deletion.
2. Choose cancel.
   - Expected: The comment remains visible and no delete mutation is performed.
3. Tap delete for the same comment again and confirm.
   - Expected: Only the selected comment is deleted through `TimelineStore.deleteComment`.
   - Expected: Other comments remain.
   - Expected: Duplicate taps while deletion is in flight do not trigger duplicate delete work.
4. If deletion fails due to connection/server state, remain in Moment detail.
   - Expected: Existing store error handling surfaces the failure; the detail view is not dismissed unexpectedly.

## Test Case 6 — Constraint review

1. Inspect Moment detail comment UI.
   - Expected: No replies, likes, mentions, avatars/public author identity, rich text controls, Markdown rendering, comment media, edit controls, or threading affordances appear.
2. Return to the main timeline and use search/filter controls.
   - Expected: Comments do not appear as timeline row previews, timeline badges/counts, or separate search participation.

## Notes

- This UAT proves S02 UI behavior. S03 remains responsible for final real-device/cross-boundary UAT and documentation updates for the full private-comment flow.
