# M006: Smart Tags — Validation

**Date:** 2026-05-03
**Status:** Automated verification passed; real iPhone build/install/launch passed; manual UAT is pending.

## Verification Evidence

### Contract, Server, And Admin

- `npm run server:typecheck` passed.
- `npm run server:build` passed.
- `npm run admin:build` passed.
- `git diff --check` passed.
- `npm run server:prisma:deploy` reported 10 migrations and no pending migrations.
- `server/scripts/install-launchd.sh` rebuilt Admin/Server, applied migrations, and installed/restarted `com.private-moments.server`.
- `curl -fsS http://127.0.0.1:3210/api/v1/health` returned `ok: true` and `schemaVersion: 9`.
- SQLite schema inspection confirmed `tags`, `tag_aliases`, and `post_tags` tables exist.
- SQLite seed check confirmed the 6 default primary tags exist, are unarchived, default, and AI-usable:
  - `日记`
  - `想法`
  - `学习整理`
  - `情绪`
  - `碎碎念`
  - `复盘`
- Server change seed check confirmed `tag_updated|6`.
- Authenticated `GET /api/v1/admin/status` returned safe tag diagnostics:
  - `schemaVersion: 9`
  - `sync.latestServerChangeVersion: 294`
  - `tags.total: 6`
  - `tags.primary: 6`
  - `tags.topics: 0`
  - `tags.archived: 0`
  - `tags.aiAssignments: 0`
  - `tags.manualAssignments: 0`

### iOS Build And Tests

- `cd ios && xcodegen generate` passed.
- `xcodebuild test -project PrivateMoments.xcodeproj -scheme PrivateMoments -destination 'platform=iOS Simulator,id=C09FFED1-FC8F-41E2-B4ED-0B2D3875003F' CODE_SIGNING_ALLOWED=NO` passed.
- The simulator test suite executed 17 tests with 0 failures:
  - `ComposerDraftStoreTests`: 2
  - `ShareImportInboxTests`: 1
  - `TimelineCommentsDisplayTests`: 4
  - `TimelineDateJumpModelsTests`: 5
  - `TimelineSearchTests`: 5, including tag and alias matching
- The test run emitted simulator App Group entitlement warnings, but tests completed successfully.
- `xcodebuild -project PrivateMoments.xcodeproj -scheme PrivateMoments -destination generic/platform=iOS -configuration Debug CODE_SIGNING_ALLOWED=NO build` passed.
- `npm run ios:device` built, signed, installed, and launched the app on `wwz 的 iphone`.
- Install output confirmed:
  - `BUILD SUCCEEDED`
  - `App installed`
  - `Launched application with com.popcornnnnnn.privatemoments bundle identifier`
  - `Moments is installed and launched on wwz 的 iphone`

### Real iPhone Availability

- `xcrun devicectl list devices` showed `wwz 的 iphone` as `connected`.
- `xcrun xctrace list devices` showed `wwz 的 iphone (26.4.2)` under `Devices`.
- After install/launch, `curl -fsS http://127.0.0.1:3210/api/v1/health` still returned `ok: true` and `schemaVersion: 9`.

### Follow-up: Tag Color Palette And AI Tag Empty Suggestions

- Replaced primary tag color editing in Settings > Tags with a low-saturation preset palette instead of a raw hex text field.
- Updated the palette again to keep 6 soft default colors and add clearer medium/high-saturation preset colors.
- Reintroduced a custom `#RRGGBB` HEX input below the palette for exact colors. The field normalizes lowercase/partial input to uppercase `#` form and disables Add/Save while the custom value is incomplete or invalid.
- Investigated two newly published audio moments that had ready summaries but no visible tags. Server logs showed `ai.summary_ready` for both, and SQLite showed `ai_tag_processed_at` was set with zero active tags, so the failure was in the AI tag suggestion/application path rather than iOS display.
- The original provider output for both audio files returned empty tag suggestions: `primary: null`, `topics: []`.
- The server prompt now makes tag suggestion mandatory for recognizable speech, falls back to a focused tag-only provider call when summary output has no tags, and logs safe `ai.tags_processed` metadata with applied counts, confidence values, and skipped reason.
- Backfilled the two affected audio posts after the fix:
  - `458DB99B-EA59-4C30-A889-B667DEA441FD`: primary `想法` confidence `0.78`; topics `标签系统测试` `0.86`, `AI转录` `0.68`.
  - `2081168B-6907-47E8-B3DE-85CA3F7738A1`: primary `想法` confidence `0.78`; topics `标签颜色系统` `0.94`, `内置调色盘` `0.93`, `颜色输入体验` `0.86`.
- SQLite verification after backfill confirmed 7 active AI tag assignments across those two posts and latest server change version `322`.
- After reinstall/launch on `wwz 的 iphone`, server logs showed sync advancing the device to `nextSyncCursor: 322`; copied iPhone Library container confirmed `lastSyncCursor = 322` and the same 7 local AI tag assignments in `local_post_tags`.
- Follow-up verification passed:
  - `npm run server:typecheck`
  - `npm run server:build`
  - `npm run admin:build`
  - `cd ios && xcodegen generate`
  - `xcodebuild test ...` executed 17 tests with 0 failures.
  - `xcodebuild ... generic/platform=iOS ... CODE_SIGNING_ALLOWED=NO build` returned `BUILD SUCCEEDED`.
  - Synthetic provider smoke test for a tag color/palette note returned primary `想法` confidence `0.78` and topics `标签系统` `0.92`, `颜色设置` `0.95`, `预设调色盘` `0.90`.

### Follow-up: Edit Moment Audio Preview

- Fixed an older Edit Moment UI bug where existing audio media was rendered through the image thumbnail grid below `Use Camera`, making it look like a broken image preview.
- Edit Moment now renders media by kind:
  - images use the sortable editable thumbnail grid;
  - audio uses an audio preview/playback row;
  - video uses the video preview card;
  - Add Photos and Use Camera are disabled while existing audio/video media is present, preserving one-media-kind behavior.
- HEX color input follow-up verification passed on 2026-05-03:
  - `cd ios && xcodegen generate`
  - `xcodebuild test -project PrivateMoments.xcodeproj -scheme PrivateMoments -destination 'platform=iOS Simulator,id=C09FFED1-FC8F-41E2-B4ED-0B2D3875003F' CODE_SIGNING_ALLOWED=NO` executed 17 tests with 0 failures.
  - `xcodebuild -project PrivateMoments.xcodeproj -scheme PrivateMoments -destination generic/platform=iOS -configuration Debug CODE_SIGNING_ALLOWED=NO build` returned `BUILD SUCCEEDED`.

## UAT Checklist For Next Connected iPhone Session

1. Open Settings > Organization > Tags and confirm the 6 default primary tags appear with low-saturation colors and cannot be renamed/archived.
2. Create a text/image/video moment with a manual primary tag; confirm timeline primary chip display, Detail tag display, Edit Moment tag editing, and `Show Tags in Timeline` hide/show behavior.
3. Add a topic tag and alias in Settings; confirm timeline search matches both canonical topic and alias with `tag` as the match source.
4. Test topic merge/archive/restore in Settings and confirm usage counts/search behavior remain coherent.
5. Publish a new clear-speech audio moment without selecting a primary tag; wait for first ready AI summary and confirm AI-applied primary/topic tags sync back.
6. Publish or edit a moment with a user-chosen primary tag; confirm AI does not replace the selected primary tag.
7. Regenerate an existing summary and confirm tags are not regenerated or overwritten.
8. Publish image/video/text moments without manual tags and confirm they do not receive AI automatic tags.
9. Check Settings > Storage & Diagnostics for Mac Server tag diagnostics and cursor status after sync.

## Known Limitations

- No historical audio tag backfill.
- No AI tags for video, image, or text-only moments in this version.
- No manual `Regenerate tags` action.
- Server/Admin search does not filter by tags in this version.
- Full M006 closure still requires the manual UAT checklist above.
