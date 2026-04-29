# S02: Plain-Text List Continuation — UAT

**Milestone:** M001
**Written:** 2026-04-29T18:11:26.575Z

# S02 UAT: Plain-Text List Continuation

## Preconditions

1. Build and install a current Debug version of the iOS app on an iOS simulator or the paired real device.
2. Use a local app database where creating and editing test moments is safe.
3. Keep the Mac server/sync state optional; this UAT verifies local editor behavior and plain-text save/rendering, not network sync.
4. Ensure the app launches to the main timeline and the New Moment composer can be opened.

## Test Case 1 — Dash list continuation in New Moment

1. Open New Moment.
2. Tap the text field/editor.
3. Type `- first item`.
4. Press Return.
5. Expected: the editor inserts a new line beginning with `- ` and the cursor is placed after the space.
6. Type `second item`.
7. Save/publish the moment.
8. Expected: the saved moment appears as literal plain text with visible `- first item` and `- second item`; no bullet styling, Markdown conversion, or rich formatting is applied.

## Test Case 2 — Bullet list continuation in New Moment

1. Open New Moment.
2. Type `• first item`.
3. Press Return.
4. Expected: the next line begins with `• ` and the cursor is after the space.
5. Type `second item` and save/publish.
6. Expected: timeline/detail text remains literal plain text including the `• ` characters.

## Test Case 3 — Numbered list increment in New Moment

1. Open New Moment.
2. Type `1. first item`.
3. Press Return.
4. Expected: the next line begins with `2. ` and the cursor is after the space.
5. Type `second item`.
6. Press Return.
7. Expected: the next line begins with `3. ` and the cursor is after the space.
8. Save/publish.
9. Expected: the displayed moment shows literal numbered lines; no ordered-list rendering is applied.

## Test Case 4 — Empty generated dash item exits list

1. Open New Moment.
2. Type `- item`.
3. Press Return.
4. Expected: a generated `- ` marker appears on the next line.
5. Without typing text after the marker, press Return again.
6. Expected: the dangling `- ` marker is removed and the cursor exits to a normal blank paragraph line.
7. Type `after list`.
8. Expected: `after list` appears as normal text without a list prefix.

## Test Case 5 — Empty generated bullet and numbered items exit list

1. Repeat Test Case 4 with `• item`.
2. Expected: pressing Return on the generated empty `• ` marker removes it and exits the list.
3. Repeat Test Case 4 with `1. item`.
4. Expected: pressing Return on the generated empty `2. ` marker removes it and exits the list.

## Test Case 6 — Normal paragraphs remain native

1. Open New Moment.
2. Type `ordinary paragraph`.
3. Press Return.
4. Expected: a normal newline is inserted with no prefix.
5. Type another ordinary line and save.
6. Expected: the saved/displayed text preserves the normal newline and no list marker is introduced.

## Test Case 7 — Edit Moment uses the same behavior

1. Open an existing moment's detail view.
2. Enter edit mode.
3. In the edit text field, test each input sequence:
   - `- edited item`, Return → expect `- ` continuation.
   - `• edited item`, Return → expect `• ` continuation.
   - `1. edited item`, Return → expect `2. ` continuation.
4. For each prefix, press Return on the empty generated marker.
5. Expected: the marker is removed and the cursor exits the list.
6. Save the edit.
7. Expected: the updated detail/timeline text remains literal plain text and existing update flow succeeds.

## Test Case 8 — Unicode and emoji safety

1. Open New Moment or Edit Moment.
2. Type `🙂 café` on one line, then Return.
3. Type `- emoji item 🚲`.
4. Press Return.
5. Expected: the editor continues with `- ` and the cursor position is correct; no crash, split emoji, or cursor jump occurs.
6. Save if desired.
7. Expected: Unicode and emoji display literally as plain text.

## Test Case 9 — Non-goals / formatting boundary

1. Create or edit a moment containing:
   - `# heading?`
   - `**bold?**`
   - `> quote?`
   - `https://example.invalid`
2. Save the moment.
3. Expected: timeline/detail display shows the exact literal characters. There are no headings, bold styling, quote blocks, Markdown list rendering, or link-preview cards introduced by this slice.

## Pass Criteria

- New Moment and Edit Moment both continue `- `, `• `, and numbered list prefixes on Return.
- Numbered lists increment by one.
- Pressing Return on an empty generated marker removes the marker and exits the list.
- Normal paragraph Return behavior remains unchanged.
- Saved and rendered content remains ordinary plain text.
- No private typed text appears in logs, telemetry, or new diagnostics surfaces.
