# M007: iOS Localization And Language Preferences

**Gathered:** 2026-05-03
**Status:** Implemented; automated verification passed; installed and launched on real device
**Depends on:** Current iOS Settings/Appearance local preference pattern, `MomentDateFormatter`, Smart Tags default primary tag model, and AI summary/title pipeline.

## Project Description

Add a first-version language system for the iOS app so Moments can support both English and Simplified Chinese UI without creating two separate product flows.

The core boundary is:

- App Language controls UI chrome and date/time presentation.
- User content is not translated.
- Default system primary tags may have localized display names while keeping one stable synced tag identity.
- AI summary/title language is independent from App Language and should default to source-content language detection.
- The Mac Admin UI, server logs, API names, and project documentation are out of scope for the first localization milestone.

## User-Visible Outcome

When this milestone is complete, the user can:

- Open Settings and choose App Language: `System`, `English`, or `简体中文`.
- Change App Language and see the iOS app update immediately without restarting.
- Use a Chinese UI with natural Chinese date labels such as `刚刚`, `2分钟前`, `今天 14:40`, `昨天 14:40`, and `4月29日 周三`.
- Keep using English UI if preferred, including on existing private installs.
- See default primary tags in the current UI language while keeping historical tag assignments intact.
- Search default primary tags by either Chinese or English names.
- Choose AI Language separately as `Auto`, `Chinese`, or `English`.
- Leave AI Language on `Auto` so AI summary/title follows the dominant input language instead of the UI language.

## App Language Rules

The App Language preference has three options:

- `System`
- `English`
- `简体中文`

Rules:

- New installs default to `System`.
- Existing private installs should migrate to `English` to preserve the current owner's established UI.
- The value is stored locally in `UserDefaults`.
- The value is not synced to the Mac server.
- Changing the value applies immediately across visible iOS surfaces.
- App Language affects UI labels, buttons, settings text, alerts, search/filter labels, empty/error/status text, and date/time formatting.
- App Language does not translate user-authored moment text, comments, custom tags, topic tags, aliases, AI summary bodies, or AI-generated titles.

## Localization Scope

First-version localization covers the iOS app's user-visible surfaces:

- Timeline
- Composer
- Detail
- Edit Moment
- Settings
- Tags management
- Summary sheet
- Search and Filter
- Alerts and confirmation dialogs
- Date jump and month/day navigation
- Comment UI
- Share/import entry surfaces that appear inside the app

Out of scope:

- Mac Admin UI
- Server logs
- API route names and payload field names
- Code symbols and filenames
- Project documentation language policy
- Translating historical user content
- Translating custom tags or topic tags

## Date And Time Rules

English mode keeps the existing life-feeling English labels such as:

- `Just now`
- `2 min ago`
- `Today 2:40 PM`
- `Yesterday 2:40 PM`
- `Apr 29, 2:40 PM`
- `April 2026`
- `Apr 29 · Wed`

Simplified Chinese mode uses natural Chinese expressions rather than direct English-shaped translations:

- `刚刚`
- `2分钟前`
- `今天 14:40`
- `昨天 14:40`
- `4月29日 周三`
- `2026年4月`

The date system should stay life-feeling and count-free. Do not introduce database-like archive labels or daily count language as part of localization.

## Default Primary Tag Localization

Default primary tags are one synced tag identity with localized display names.

Chinese display names remain:

- `日记`
- `想法`
- `学习整理`
- `情绪`
- `碎碎念`
- `复盘`

English display names are:

- `Diary`
- `Thoughts`
- `Study`
- `Mood`
- `Random`
- `Review`

Rules:

- The localized name is display-only.
- Usage count, tag assignment, AI assignment, sync identity, archive/delete rules, and search semantics stay attached to one tag ID.
- Custom primary tags keep the user's chosen name and are not auto-translated.
- Topic tags and aliases keep the user's or AI's canonical text and are not auto-translated.
- Search/filter should match default primary tags through both Chinese and English display names regardless of current App Language.
- This cross-language matching applies only to default primary tags, not arbitrary custom tags.

## AI Language Rules

AI Language is a separate local setting from App Language.

Options:

- `Auto`
- `Chinese`
- `English`

Rules:

- Default is `Auto`.
- `Auto` summarizes/titles in the dominant language of the input.
- Chinese-dominant voice notes with English technical terms should still produce Chinese summary/title.
- English-dominant voice notes should produce English summary/title.
- `Chinese` forces Chinese output where the model can reasonably summarize the input.
- `English` forces English output where the model can reasonably summarize the input.
- App Language does not force AI output language.
- The AI Language value can be sent from iOS to the Mac server as request/config metadata for future generation, but it is not a synced cross-device preference in the first version.

## Data And Migration Notes

Implementation should avoid a heavy server schema migration unless localized default tag names need persistent server metadata.

Preferred first-version approach:

- Store App Language and AI Language locally in iOS `UserDefaults`.
- Keep API field names and sync payloads unchanged where possible.
- Add localized display-name mapping for default primary tag identities on iOS.
- Add search aliases for default primary tags in the local search model.
- Pass AI Language preference to summary generation only where it affects new/regenerated AI output.
- Preserve existing installs by initializing App Language to `English` during migration/first read if no language preference exists and local app data indicates an existing private install.
- Public/open-source new installs should use `System`.

If server-side support is required later, it should be scoped narrowly to generated AI output behavior rather than a general user preference sync system.

## Design Constraints

- Main timeline must stay quiet.
- Do not add a language banner, onboarding wall, or translation prompt.
- Settings is the correct home for language controls.
- Language controls should follow the existing Appearance preference style but should avoid nested-card visual clutter.
- UI copy should stay concise in both languages.
- Chinese copy should be natural product UI, not literal translations.
- Existing English UI should remain polished and not become the neglected fallback.

## Verification Expectations

Milestone implementation should verify:

- iOS build passes.
- App Language changes apply immediately.
- Existing private install keeps English unless changed.
- New-install path defaults to `System`.
- Timeline, Composer, Detail/Edit, Settings, Tags, Summary, Search/Filter, alerts, and date jump surfaces have no obvious mixed-language gaps in Chinese mode.
- English mode remains unchanged or intentionally equivalent.
- Chinese date labels match the agreed life-feeling format.
- Default primary tags show localized names but keep one tag identity and usage count.
- Searching `学习` and `study` can both hit the default `学习整理` / `Study` primary tag.
- Custom tags are not translated.
- AI Language `Auto` keeps Chinese-dominant input in Chinese even when English technical terms appear.
- AI Language `English` and `Chinese` affect new/regenerated summaries without changing App UI language.

## Deferred Questions

- Whether Mac Admin should eventually support localization.
- Whether project docs should ever have parallel English/Chinese versions beyond README.
- Whether AI-generated topic tags should ever be localized or bilingual.
- Whether multi-device preference sync is useful if the app grows beyond a single iPhone.
- Whether Calendar/month/year review views should be built after or before the localization foundation.

## Implementation Notes

- iOS uses `AppLocalization.swift` as the first-version localization layer, with `AppLanguageMode`, `AILanguageMode`, a SwiftUI `appLanguage` environment value, and `L10n.t(...)` for user-visible strings.
- `AppSettings` stores App Language and AI Language in local `UserDefaults`. Existing private installs default to English when no language preference exists and previous app state is detected; new installs default to System.
- `MomentDateFormatter` and timeline date jump labels now render either English or Simplified Chinese life-feeling labels from the resolved App Language.
- Default primary tags stay one synced tag identity, but display as `Diary`, `Thoughts`, `Study`, `Mood`, `Random`, and `Review` in English mode and as the original Chinese names in Chinese mode. Local search/filter can match both language names for these default primary tags.
- iOS sends AI Language as `auto`, `zh`, or `en` when uploading media and when manually regenerating a media summary. The Mac summary prompt uses that preference to choose generated summary/title language while keeping App Language independent.

## Verification Evidence

- `git diff --check -- ios/PrivateMoments server/src/api server/src/ai .gsd docs` passed.
- Localization dictionary coverage check passed: all 270 `L10n.t(...)` keys have Simplified Chinese entries.
- `npm run server:typecheck` passed.
- `npm run server:build` passed.
- `curl -fsS http://127.0.0.1:3210/api/v1/health` returned `ok: true` with `schemaVersion: 9`.
- `cd ios && xcodegen generate && xcodebuild -project PrivateMoments.xcodeproj -scheme PrivateMoments -destination generic/platform=iOS -configuration Debug CODE_SIGNING_ALLOWED=NO build` passed.
- `cd ios && xcodebuild -project PrivateMoments.xcodeproj -scheme PrivateMoments -destination 'platform=iOS Simulator,name=iPhone 17' test CODE_SIGNING_ALLOWED=NO` passed: 21 tests, 0 failures.
- `npm run ios:device` initially built and signed successfully but hit an offline-device CoreDevice error. After reconnecting `wwz 的 iphone`, the app installed successfully; the script launch step failed to determine the pid once, then manual `xcrun devicectl device process launch --device "wwz 的 iphone" --terminate-existing com.popcornnnnnn.privatemoments --timeout 30` launched the app successfully.
