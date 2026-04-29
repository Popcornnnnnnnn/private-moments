# M001: Timeline Navigation and Lightweight Input — Context

**Gathered:** 2026-04-30
**Status:** Ready for planning

## Project Description

Moments is a private expression space with no audience. It should feel like posting to a personal feed: write a sentence, add a few photos, record the moment, then continue living. It should not become a social product, database archive, or writing editor.

## Why This Milestone

The next product questions are both about positioning pressure:

1. As content grows, how does the user return to past moments without turning the app into an archive manager?
2. Should input support helpful syntax without turning the app into a Markdown editor?

This milestone answers both with small, bounded UI improvements that preserve the core promise: timeline-first, private, light expression.

## User-Visible Outcome

### When this milestone is complete, the user can:

- Open the existing timeline toolbar calendar menu, choose a month, optionally choose a day within that month, and jump to the matching portion of the feed.
- Type short bullet or numbered lists in New Moment and Edit Moment with Return continuing the list naturally.

### Entry point / environment

- Entry point: iOS `Moments` app timeline toolbar menu, New Moment composer, Edit Moment sheet.
- Environment: local iOS app with existing local timeline data.
- Live dependencies involved: local SQLite timeline data; no server contract change expected.

## Completion Class

- Contract complete means: date grouping and list-continuation helpers produce expected IDs, labels, and text transformations for representative inputs.
- Integration complete means: timeline scroll target wiring works from the menu, and composer/edit share the same input behavior.
- Operational complete means: existing sync/storage behavior remains unchanged; no migration required.

## Final Integrated Acceptance

To call this milestone complete, we must prove:

- Timeline remains visually quiet while date jump is available only from the low-frequency toolbar calendar menu.
- Choosing an existing month jumps to that month’s first moment; choosing a date jumps to that day’s first moment.
- Composer and Edit Moment support `- `, `• `, and numbered list continuation when feasible without large input architecture changes.
- Saved text remains plain text and timeline/detail views do not render Markdown.

## Scope

### In Scope

- Enhance the existing toolbar calendar menu into month-first, optional-day navigation.
- Show only months/dates that actually contain moments.
- Use life-feeling date labels such as `April 2026`, `Apr 29 · Wed`, `Today`, or `Yesterday`.
- Continue bullet list prefixes `- ` and `• ` on Return.
- Continue numbered list prefixes with auto-increment, e.g. `1. ` → `2. `.
- Exit list continuation when the generated list item is empty and Return is pressed again.
- Apply input assistance to both New Moment and Edit Moment if a small shared implementation is possible.

### Out of Scope / Non-Goals

- Calendar tab.
- Archive/database management page.
- Daily moment counts such as `5 moments`.
- Empty date selection.
- Markdown rendering.
- Rich text editing, heading, bold, quote, or link preview support.
- Large composer/edit rewrite solely for input polish.

## Architectural Decisions

### Timeline stays feed-first

**Decision:** Date navigation must support returning to a time period without changing the main timeline into a calendar or archive UI.

**Rationale:** The product north star is “像刷 feed 一样回看过去，而不是像查数据库一样翻记录”.

**Alternatives Considered:**
- Full Calendar/Archive tab — rejected because it creates management weight and statistical framing.
- No date jump — rejected because growing content needs better temporal return paths.

### Toolbar menu is the date navigation entry

**Decision:** Keep date jump inside the existing toolbar calendar menu.

**Rationale:** It preserves the quiet main timeline and follows the existing low-frequency control pattern.

**Alternatives Considered:**
- Persistent timeline button — rejected as unnecessary visual weight.
- Search/filter area — rejected because date jump is temporal navigation, not text search.

### Plain-text list continuation only

**Decision:** Support small plain-text list continuation behavior, not Markdown or rich text.

**Rationale:** List continuation helps “顺手表达” but Markdown/rich text nudges the app toward long-form writing and formatting.

**Alternatives Considered:**
- Full basic Markdown — rejected as too editor-like.
- Pure text with no assistance — acceptable but leaves common friction unresolved.

## Error Handling Strategy

- If timeline has no moments, date jump remains disabled as it is today.
- Date jump should only expose existing months/days, avoiding empty targets.
- If a target item disappears due to filter/search changes, the UI should fail quietly and keep the user in the current feed rather than showing an error.
- If list continuation cannot be implemented cleanly with `TextEditor`, attempt a minimal UIKit/TextEditor bridge only if it stays small. If it requires substantial composer/edit restructuring, defer S02 instead of forcing it.

## Risks and Unknowns

- SwiftUI `TextEditor` may not expose enough Return handling for clean list continuation — this can turn a small polish feature into a UIKit bridge or input component rewrite.
- Nested SwiftUI `Menu` behavior for month → day navigation may be awkward or limited depending on platform behavior.
- Existing `TimelineView.swift` is still a large file, so date jump changes should avoid making it more monolithic if possible.

## Existing Codebase / Prior Art

- `ios/PrivateMoments/Views/TimelineView.swift` already has a toolbar calendar `Menu` that lists `groupedItems` by month and scrolls via `TimelineMonthJump`.
- `ios/PrivateMoments/Views/MomentDateFormatter.swift` already owns human-friendly date and month formatting.
- `ios/PrivateMoments/Views/ComposerView.swift` uses SwiftUI `TextEditor` for new post text.
- `ios/PrivateMoments/Views/MomentDetailView.swift` contains `EditMomentView`, which also uses SwiftUI `TextEditor`.
- `docs/DESIGN-PRINCIPLES.md` now states that date navigation must avoid database feel and input must not become Markdown editing.

## Relevant Requirements

- R004 — Timeline must remain feed-first while offering lightweight month/day jump navigation.
- R005 — Date navigation labels and options must avoid archive/statistics feel.
- R006 — Composer/Edit may support plain-text list continuation.
- R007 — Markdown rendering and rich text formatting remain out of scope.

## Technical Constraints

- App-facing UI copy remains primarily English.
- Main timeline must stay quiet; no persistent new calendar UI.
- No server/schema changes are expected.
- If S02 requires a large input rewrite, it should be deferred rather than forced.

## Integration Points

- Timeline menu → existing grouped timeline data → ScrollViewReader target IDs.
- Composer/Edit text binding → draft persistence → store create/update flows.

## Testing Requirements

- iOS build must pass.
- Date jump grouping and labels should be manually verified in the app or with focused helper tests if helpers are extracted.
- List continuation behavior should be verified in both New Moment and Edit Moment when implemented.
- Confirm saved/rendered content remains plain text.

## Acceptance Criteria

### S01: Lightweight Date Jump

- Toolbar calendar menu remains the only date jump entry.
- Month entries are derived from existing visible timeline data.
- Each month can expose only dates that have moments.
- Selecting a month scrolls to that month’s first visible moment.
- Selecting a day scrolls to that day’s first visible moment.
- Labels are life-feeling and do not show moment counts.

### S02: Plain-Text List Continuation

- New Moment and Edit Moment share behavior if feasible.
- `- item` + Return produces `- `.
- `• item` + Return produces `• `.
- `1. item` + Return produces `2. `.
- Return on an empty generated list item exits the list.
- Saved content remains plain text.
- If implementation requires large input architecture changes, S02 is explicitly deferred with evidence.

## Open Questions

- Whether SwiftUI `Menu` nested month/day menus feel acceptable on the target iOS version.
- Whether `TextEditor` can support Return interception with small, maintainable code.