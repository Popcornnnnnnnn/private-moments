# M008: Calendar Review

**Gathered:** 2026-05-03
**Status:** Implemented; automated verification passed; installed on real device; unlocked-device UAT pending
**Supersedes:** The no-Calendar-tab part of D006.
**Depends on:** Current Timeline tab, Timeline search/filter chip model, `MomentDateFormatter`, App Language localization, local media metadata, favorite metadata, and Timeline scroll/date jump mechanics.

## Project Description

Add a first-class Calendar tab for visual time review.

Calendar should make it easier to understand past posting rhythm and find a day when the user cannot remember the exact date. It is a review and navigation surface, not a second editor, archive database, statistics dashboard, or AI summary center.

Timeline remains the continuous reading surface. Calendar gives an overview of lived-time density, then opens a focused Day Review for the selected date; jumping back to Timeline is a secondary action inside that Day Review.

## User-Visible Outcome

When this milestone is complete, the user can:

- Switch between `Timeline` and `Calendar` from the bottom tab bar.
- Open Calendar and see a month grid for the current month.
- Swipe horizontally or use month arrows to move across continuous months.
- See which days have moments through a quiet low-saturation heatmap.
- See small media hints for days that contain photos, audio, or video.
- Tap a day with light press feedback and open a full Day Review page for that day.
- Use the Day Review `Timeline` toolbar action to jump to Timeline filtered to that day.
- Clear the day filter from a visible Timeline active chip after using the `Timeline` action.
- Tap a Day Review item to open that moment's detail reading view and return to the same Day Review.
- Use Calendar offline from the same local data that powers Timeline.

## Product Positioning

Calendar is a bottom-tab peer to Timeline:

- Tab label: `Calendar` in English, `日历` in Simplified Chinese.
- Bottom tabs in v1: Timeline and Calendar only.
- Settings remains a low-frequency toolbar entry.
- Calendar has no Compose / New Moment entry.
- Calendar is a review/navigation mode, not a publishing path.
- Calendar should feel like looking back through lived time, not checking a productivity dashboard.

## Relationship To Timeline

Timeline remains the main reading and interaction surface.

Rules:

- Ordinary tab switching preserves the current Timeline scroll position.
- Calendar day tap opens a full Day Review page inside the Calendar navigation stack.
- The Day Review `Timeline` toolbar action switches to Timeline and applies a temporary day filter.
- The day filter appears as an active chip such as `Apr 29` or `4月29日`.
- Tapping the chip's clear affordance returns Timeline to its full unfiltered state.
- Calendar owns a lightweight day review mode but not editing, publishing, or archive management.
- Day Review item taps open exact moment detail inside the Calendar navigation stack, so Back returns to Day Review rather than Timeline or the month grid.

The existing Timeline `Jump to date` toolbar menu should be removed in M008. Calendar becomes the single primary date review entry. Do not keep the toolbar calendar icon as a parallel date navigation path.

## Default View

Calendar defaults to month view.

Month view rules:

- First screen shows the current month.
- Top navigation shows current month title and left/right month arrows.
- A lightweight `Today` / `今天` control appears or becomes more visible when not on the current month.
- Month switching supports both horizontal swipe and arrow taps.
- Weekday order follows the system locale / `Calendar.current.firstWeekday`.
- Weekends are not visually distinguished in v1.
- Future dates are visible but faded and not tappable.
- Today has a subtle ring or outline, not a strong task-app highlight.
- Empty months show a normal empty calendar grid, with no explanatory empty-month text.

New-user empty state:

- If there are no moments at all, show the current month grid plus one short localized empty message such as `No moments yet` / `还没有 moments`.
- Do not turn the empty state into a publish prompt or onboarding page.

## Day Cell Visual Model

Day cells should stay compact and predictable.

Density:

- The heatmap is based on moment count, not media duration, content weight, comments, favorites, AI summaries, or inferred importance.
- Suggested count buckets:
  - 0 moments: no heat color.
  - 1 moment: very light color.
  - 2-3 moments: medium-light color.
  - 4+ moments: stronger but still low-saturation color.
- Do not show numeric counts in the date cell.
- Use a fixed hue family that adapts to light/dark mode by brightness/opacity, not tag colors.
- Visual feel should be low-saturation paper-like traces, not a strong GitHub-style KPI heatmap.

Media hints:

- Show at most two tiny media icons per day.
- Icons are memory triggers only; they must not crowd the day cell.
- Prefer familiar SF Symbols for media hints:
  - image/photo for image moments.
  - waveform or mic-like symbol for audio.
  - play/video symbol for video.
- If more than two media types exist, show the most useful two or a compact overflow indicator.
- Text-only days rely on the heatmap and date number; no text icon is required unless implementation proves it useful.

## Day Review

Tapping a selectable day opens a quiet Day Review page.

Day Review rules:

- Date cell press feedback should stay aligned with the app's quiet button language: light `0.985`-scale press, subtle tint, no heavy shadow, and one selection haptic on navigation.
- Day Review shows all moments for that day that match the current Calendar filters.
- The top header shows date, weekday, visible moment count, and a lightweight media composition line.
- Day Review rows use an intra-day timeline structure rather than cards or a grouped List background.
- Each Day Review item can include:
  - time.
  - primary tag when `Show tags in Timeline` is enabled.
  - rendered lightweight Markdown post text, AI title, or compact fallback such as `Photo moment`.
  - compact inline audio playback and summary state/entry for audio moments.
  - video type/duration hint without poster, autoplay, or inline playback.
- Image moments show all image thumbnails as uniform small grid cells; single-image moments are not enlarged in Day Review.
- Video moments do not show video playback or poster preview in Day Review.
- Tapping a Day Review item outside audio controls opens that specific moment's detail reading view inside the Calendar navigation stack, so Back returns to the same Day Review.

## Calendar Filters

Calendar has its own lightweight filters and does not inherit transient Timeline search/filter state.

Rules:

- Default Calendar shows all local visible moments.
- Calendar filters are separate from Timeline filters.
- V1 filters:
  - media type: All, Text, Photos, Audio, Video.
  - Favorite.
- Do not add tag filters in v1.
- Do not add search, comments, needs-sync, month, or match-source filters in v1.
- Filtering affects the heatmap, media hints, date tappability, Day Review contents, and Day Review header counts.
- Calendar filter state does not need to persist across app restarts unless implementation finds a very low-risk local preference pattern.

## Data Model And Sync Boundary

Calendar v1 is a pure derived local UI.

Rules:

- Use only local iOS data already available to Timeline.
- Do not add new SQLite schema.
- Do not add new sync operations.
- Do not request remote Mac calendar statistics.
- Do not create server-side calendar summary/cache tables.
- Calendar should be available offline and match what the local Timeline can currently show.
- If a remote moment is not yet synced to the iPhone, Calendar does not show it.
- Deleted moments should not contribute to Calendar density or Day Review.

## Localization And Accessibility

Localization:

- All Calendar UI chrome follows App Language.
- Month/day labels use `MomentDateFormatter` or the same localized date-label rules.
- User content in Day Review is not translated.
- Calendar first weekday follows system locale.

Accessibility:

- Date cells must expose VoiceOver labels that include date, moment count bucket/count, media types, favorite presence when relevant, today/future state, and available actions.
- Color and icons cannot be the only carriers of information.
- Future dates should be announced as unavailable or disabled.
- Day Review items should be individually focusable and actionable.

## Explicit Non-Goals For V1

Do not include in M008 v1:

- Creating moments from Calendar.
- Tapping an empty date to create a backdated moment.
- A Calendar-specific Compose button.
- Editing, creating, or managing moments from Calendar Day Review.
- Year heatmap implementation.
- Week or month AI summaries.
- On-this-date memory surfacing.
- Periodic summaries.
- Lunar calendar or holiday display.
- Weekend styling.
- Tag filters.
- Remote Mac calendar statistics.
- New schema or sync protocol.
- README/open-source screenshot updates.

## Future Hooks

These are deliberately deferred:

- Year view / yearly heatmap.
- On-this-date memory resurfacing.
- Weekly/monthly AI summaries.
- More advanced tag-aware or semantic calendar filters.
- Calendar screenshots for README/open-source release materials after the feature is implemented and visually verified.

Implementation may keep internal structure open for Year view later, but should not expose a prominent disabled or unfinished Year View control.

## Verification Expectations

M008 implementation should verify:

- iOS build passes.
- Existing Timeline tests still pass.
- Calendar derived model tests cover month construction, continuous empty months, future date disabling, today state, density buckets, media hint selection, favorite/media filters, and locale first weekday.
- Calendar does not require server connectivity and does not introduce schema/sync migrations.
- Tapping a day opens Day Review with a visible local day header and no grouped sheet/list background.
- The Day Review `Timeline` action switches to Timeline with a visible clearable day filter chip.
- Ordinary Timeline/Calendar tab switching preserves Timeline scroll position.
- Old Timeline `Jump to date` toolbar calendar icon is removed.
- Day Review shows all filtered items for that day, uses uniform small image thumbnails, supports inline audio playback, omits video playback/posters, and item detail push returns to Day Review.
- App Language affects Calendar labels and empty state.
- VoiceOver labels for date cells expose date, density, media, favorite, today/future, and action semantics.
- Real iPhone UAT covers month swipe, arrows, Today, day tap, Day Review, Timeline action/chip clear, media/favorite filters, light/dark appearance, audio waveform playback/seek/rate, and English/Chinese labels.

## Implementation Notes

Implemented on 2026-05-03 as a local iOS-only UI change:

- `RootView` now exposes bottom tabs for Timeline and Calendar only; Settings opens from toolbar buttons.
- `CalendarView` renders the local month grid, arrows, horizontal swipe, Today control, media/favorite filters, heatmap density, media hints, future-date disabling, light date-cell press feedback, and Day Review navigation.
- Calendar Day Review shows all filtered items for the selected day. Rows render post text with the same lightweight `#` / `##` Markdown heading model used by Timeline, show the primary tag only when `Show tags in Timeline` is enabled, show all image thumbnails for image moments, and fall back to AI title or media labels only when post text is empty.
- Day Review row taps open `MomentDetailView` for that exact moment inside the Calendar navigation stack, so Back returns to the same Day Review instead of switching to Timeline/date filtering.
- `CalendarReviewBuilder` derives 42-cell months from local `TimelineItem` values without schema, sync, server, or Mac API changes.
- `TimelineView` accepts Calendar day routes, clears transient Timeline filters/search for that route, applies a clearable day chip, and scrolls to the selected day/item.
- The old Timeline toolbar `Jump to date` calendar menu was removed.

Fresh verification:

- `cd ios && xcodegen generate`
- `xcodebuild -project ios/PrivateMoments.xcodeproj -scheme PrivateMoments -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:PrivateMomentsTests/CalendarReviewModelsTests test` passed 3/3.
- `xcodebuild -project ios/PrivateMoments.xcodeproj -scheme PrivateMoments -destination 'platform=iOS Simulator,name=iPhone 16' test` passed 24/24.
- `xcodebuild -project ios/PrivateMoments.xcodeproj -scheme PrivateMoments -destination generic/platform=iOS -configuration Debug CODE_SIGNING_ALLOWED=NO build` passed.
- `git diff --check -- <M008 touched files>` passed.
- `npm run ios:device` built and installed `com.popcornnnnnn.privatemoments` on the connected iPhone. The final auto-launch step was denied because the device was locked, so manual unlocked-device UAT is still pending.
- Follow-up verification for preview polish: `xcodebuild -project ios/PrivateMoments.xcodeproj -scheme PrivateMoments -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:PrivateMomentsTests/CalendarReviewModelsTests test` passed 3/3 after changing preview to all same-day items.
- Follow-up verification for preview polish: `xcodebuild -project ios/PrivateMoments.xcodeproj -scheme PrivateMoments -destination generic/platform=iOS -configuration Debug CODE_SIGNING_ALLOWED=NO build` passed.
- Follow-up verification for preview detail routing/tags/image thumbnail: `xcodebuild -project ios/PrivateMoments.xcodeproj -scheme PrivateMoments -destination generic/platform=iOS -configuration Debug CODE_SIGNING_ALLOWED=NO build` passed.
- Follow-up verification for preview detail routing/tags/image thumbnail: `xcodebuild -project ios/PrivateMoments.xcodeproj -scheme PrivateMoments -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:PrivateMomentsTests/CalendarReviewModelsTests test` passed 3/3.
- Follow-up install attempt for preview detail routing/tags/image thumbnail: `npm run ios:device` built successfully, but install failed because CoreDevice reported `wwz 的 iphone` as `unavailable` / unable to locate the previous device identifier.
- Follow-up verification for all-image preview thumbnails and in-sheet detail navigation: `git diff --check -- <touched Calendar/audio/docs files>` passed, generic iOS Debug build passed, and `CalendarReviewModelsTests` passed 3/3.
- Follow-up install attempt for all-image preview thumbnails and in-sheet detail navigation: `npm run ios:device` built successfully, but install failed because CoreDevice reported `wwz 的 iphone` as `unavailable`.
- 2026-05-04 Day Review navigation follow-up supersedes the original long-press preview model: Calendar day tap now pushes a full Day Review page; top-right `Timeline` remains the secondary route to Timeline day filtering. Day Review uses an intra-day timeline layout with date/weekday/count/media composition header, optional primary tags controlled by `Show tags in Timeline`, lightweight `#` / `##` text rendering, uniform small image thumbnails, inline compact audio playback and summary state, and video type/duration hints only. Detail routing uses a heterogeneous `NavigationPath` so item taps push `MomentDetailView` and Back returns to the same Day Review.
- 2026-05-04 audio playback follow-up replaces the old play-button + slider row with a global deterministic waveform voice bar. Timeline and Day Review use compact density; Detail uses a slightly taller density. The bar supports tap to play/pause, drag to seek, finer bars, top-aligned play/speed controls, and the existing right-side speed menu, while full playback completion still resets progress.
- 2026-05-04 Day Review + waveform verification: `git diff --check -- <tracked audio/docs files>` passed, manual trailing-whitespace check covered new Calendar/audio files, generic iOS Debug build passed, and `CalendarReviewModelsTests` passed 3/3.
- 2026-05-04 Day Review + waveform install: `npm run ios:device` built, signed, and installed `com.popcornnnnnn.privatemoments` on the connected iPhone. The final auto-launch step failed only because the device was locked.
- 2026-05-04 UAT feedback fixes: Day Review primary tags now respect `Show tags in Timeline`; Day Review detail routing now uses `NavigationPath` so the right chevron/content opens `MomentDetailView`; waveform bars are finer and the play/speed controls align to the waveform region instead of the whole text-bearing row.
- 2026-05-04 UAT feedback verification: `git diff --check -- <Calendar/audio/docs/GSD files>` passed; generic iOS Debug build passed; `CalendarReviewModelsTests` passed 3/3; `npm run ios:device` built, installed, and launched `com.popcornnnnnn.privatemoments` on `wwz 的 iphone`.
- 2026-05-04 UAT follow-up: `Show Tags in Timeline` now also hides Moment Detail's Tags section and tag editing entry; active in-app navigation/tab/sheet transitions pause voice playback while background/lock-screen playback remains enabled by the existing audio background mode; Day Review stores the visible moment id per date and restores that scroll position when returning to that day.
