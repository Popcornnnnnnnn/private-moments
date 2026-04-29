# M001: Timeline Navigation and Lightweight Input

**Vision:** Preserve Moments as a quiet private expression feed while adding two bounded polish capabilities: lightweight month/day date jump for growing timelines, and plain-text list continuation for short expressive entries without Markdown or rich-text editing.

## Success Criteria

- Timeline remains visually quiet; date jump is available only through the toolbar calendar menu.
- User can jump to an existing month or a date with moments, and the feed scrolls to the first matching moment.
- Date jump labels feel like time in life, not archive statistics: no daily moment counts and no empty-date selection.
- Composer and Edit Moment support plain-text list continuation if it can be done without a large input architecture rewrite.
- Saved and rendered content remains plain text; Markdown/rich-text rendering stays out of scope.

## Slices

- [x] **S01: S01** `risk:medium` `depends:[]`
  > After this: From the timeline toolbar calendar menu, the user can choose an existing month or a date with moments and the feed jumps to that point.

- [x] **S02: S02** `risk:high` `depends:[]`
  > After this: When feasible, typing a bullet or numbered list in New Moment or Edit Moment continues the list on Return and exits on an empty list item.

## Boundary Map

### S01 → S02
Produces:
- Timeline date jump target model/invariant: month targets and optional day targets are derived only from currently visible timeline items.
- Date label policy: month/day labels use life-feeling text and never show moment counts.
- Toolbar calendar menu remains the only date navigation entry.

Consumes:
- Existing `TimelineView` grouped month data and `ScrollViewReader` jump behavior.

### S02 → Milestone Integration
Produces:
- Plain-text list continuation behavior for `- `, `• `, and numbered prefixes if feasible with small implementation.
- Shared Composer/Edit input path or explicit deferral evidence if implementation requires large rewrite.
- Invariant that saved content remains plain text and no Markdown rendering is added.

Consumes from S01:
- Product boundary: polish features must stay quiet and must not turn Moments into management or writing software.
