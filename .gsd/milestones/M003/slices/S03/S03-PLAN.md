# S03: Timeline Comment Interaction

**Goal:** Build Comments as a main-timeline interaction.
**Demo:** On iPhone, the user comments from the feed, sees latest-two previews, expands all comments in place, deletes by long-press confirmation, and searches comments.

## Must-Haves

- `TimelineRow` gains a low-key action row containing only the comment button/count.
- Every moment shows the comment icon; comment count appears only when greater than zero and uses the real undeleted count.
- Comments render below the action row in a light secondary-background section when present.
- Default preview shows the latest two comments, displayed oldest-to-newest.
- If count is greater than two, `View all N comments` expands the full list in place; expanded state is current-page-session only.
- Expanded state shows `Show less` and collapses back to latest two.
- Comment text is full multiline plain text in both preview and expanded mode.
- Comment rows show text first and lightweight English relative time such as `Just now`, `5m ago`, `Yesterday`, or `Apr 30`.
- Timeline-visible relative times refresh about once per minute.
- Long-pressing a comment opens `Delete comment?`; confirming hides/deletes locally immediately and queues/syncs as needed.
- Comment text has no copy/text-selection support in the first version because long press is delete.
- Tapping the comment button opens a bottom input bar, focuses the keyboard, shows a target summary, and scrolls the target moment near the keyboard-visible area.
- Input supports multiline, Return inserts newline, `Send` sends, empty send is disabled, and over 500 characters disables send with a light hint.
- Send clears the text, closes the input, expands the moment's comment area, and immediately inserts the new local comment.
- Closing or switching targets with a non-empty draft asks `Discard draft?`.
- Scrolling does not change the active comment target or discard the draft.
- Moment text/media taps still open Moment detail; comment controls do not trigger detail navigation.
- Search applies existing filters first, then matches moment text or comment text.
- Search results prioritize up to two matching comments in the preview when comment text matches, and lightly emphasize matching comment rows.

## Requirement Impact

- Owns R008, R010, and R011.
- Supports R012 through real-device UAT coverage.

## Threat Surface

- Gesture risk: whole-row tap-to-detail must not steal comment button, expand, input, or long-press delete gestures.
- Keyboard risk: bottom input bar and auto-scroll must stay understandable on a real iPhone.
- Density risk: full multiline latest-two preview can make rows tall; 500-character limit is the first-version guardrail.

## Verification

- iOS build for generic platform.
- Focused UI/model tests where practical for preview selection, search comment matching, expand/collapse state, length validation, and relative time formatting.
- Real iPhone UAT for comment button, input bar target summary, send-success scroll-to-moment-bottom feedback, latest-two preview, expand/collapse, long-press delete, and comment search.

## Files Likely Touched

- `ios/PrivateMoments/Views/TimelineView.swift`
- `ios/PrivateMoments/Views/TimelineRow.swift`
- `ios/PrivateMoments/Views/TimelineCommentsSection.swift`
- `ios/PrivateMoments/Views/TimelineCommentInputBar.swift`
- `ios/PrivateMoments/Views/MomentDateFormatter.swift`
- `ios/PrivateMoments/Persistence/TimelineStore+Mutations.swift`
- `ios/PrivateMomentsTests/*`
