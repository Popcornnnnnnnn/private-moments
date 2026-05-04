# M006: Smart Tags

**Gathered:** 2026-05-03
**Status:** Discussed; ready for milestone planning
**Depends on:** M005 AI Media Summaries for the audio summary pipeline and remote-only metadata sync behavior.

## Project Description

Add a first-class tag system for moments. Tags help the user find and lightly organize moments later without turning the timeline into a database. The system applies to all moment types for manual tagging, while AI automatic tagging is first-version scoped only to new audio moments and reuses the existing audio summary pipeline.

The central product model is:

- Primary tags describe the expression type of a moment.
- Topic tags describe concrete content, concepts, or themes inside that expression.
- User intent wins over AI output.
- AI tags are trusted when generated; they do not require asynchronous confirmation.
- The timeline stays quiet and can hide tag display without disabling tag data.

## User-Visible Outcome

When this milestone is complete, the user can:

- Optionally choose a primary tag while publishing a moment.
- Publish without choosing a tag and let the system handle new audio moments later.
- See a low-noise primary tag in the timeline when tag display is enabled.
- Hide tag chips and Detail tag editing through a feature visibility setting while keeping tags active for Settings management, search, filtering, AI tagging, and sync.
- Filter by primary tags and topic tags from the existing Filter surface.
- Search by primary tag, topic tag, or alias and see tag match as a match source.
- Open Moment Detail and see the full primary/topic tag list only when tag display is enabled.
- Open the single-moment tag editor and edit both primary and topic tags when tag display is enabled.
- Manage tag vocabulary from Settings, including topic rename, merge, alias preservation, archive/restore, and usage counts.

## Core Taxonomy

Primary tags are the stable expression-type layer. The default primary tags are:

- `日记`
- `想法`
- `学习整理`
- `情绪`
- `碎碎念`
- `复盘`

Primary tags answer what kind of expression the moment is. Topic tags answer what the moment is about.

Examples:

- A voice note about studying neural networks:
  - Primary: `学习整理`
  - Topics: `神经网络`, `大语言模型`, `强化学习`
- A post-interview reflection:
  - Primary: `复盘`
  - Topics: `面试`, `压力`
- A casual emotional note:
  - Primary: `情绪` or `碎碎念`
  - Topics: optional and sparse

## Primary Tag Rules

- Default primary tags are fixed product semantics.
- Default primary tags cannot be renamed or hidden in the first version.
- Custom primary tags may be added through a deep Settings path.
- Custom primary tags are manual-only by default: `aiUsableAsPrimary=false`.
- Custom primary tags may be renamed or hidden/archived.
- Primary tags have low-saturation colors.
- Primary tag colors may be customized, but defaults should stay low saturation.
- Primary tag colors are used consistently in Timeline, Filter, Edit, Detail, and Settings.
- Primary tag names are globally unique across all tag types.

## Topic Tag Rules

- Topic tags are dynamic and can grow over time.
- Topic tags use a canonical display name plus aliases.
- Canonical topic names should default to Chinese when possible.
- Aliases should preserve common English names, abbreviations, and alternate phrasings.
- Alias and tag matching is case-insensitive.
- Topic tags are flat; no hierarchy in the first version.
- Topic tags do not have colors.
- Topic tags can be renamed, merged into a canonical tag, hidden/archived, and restored.
- Merging topic tags preserves the old name as an alias and keeps search working.
- Archived topic tags are not shown in normal Timeline, Detail, Filter, or ordinary search.
- Archived topic tags remain visible in Settings and in the single-moment tag editor when tag display is enabled, marked as archived, so they can be removed or restored.
- Archived tag names cannot be recreated as new tags; restore the archived tag instead.

## AI Tag Scope

The tag system itself applies to all moment kinds:

- text-only
- image
- video
- audio

AI automatic tagging in the first version applies only to new audio moments.

Out of scope for AI automatic tagging in this milestone:

- video moments
- image moments
- text-only moments
- historical audio backfill
- automatic tagging when opening old summaries
- manual `Regenerate tags`

## AI Tag Lifecycle

AI tags reuse the existing audio summary pipeline:

1. iOS publishes an audio moment.
2. The audio file uploads to the Mac server.
3. The Mac server runs local transcription.
4. The external summary API generates the ready audio summary.
5. The same pipeline returns structured tag results.
6. Tags are stored as normal tag assignments and sync back to iOS.

There is no separate `Tagging...` state in Timeline. If summary is not ready, AI tags are not ready. If summary fails, AI tags fail silently and the moment remains untagged unless manually tagged.

AI tag generation happens once on the first ready summary for new audio moments. Regenerating the summary does not regenerate tags. If the user wants to fix tags in the first version, they edit them manually through the single-moment tag editor when tag display is enabled.

## AI Tag Application Rules

- If the user chose no primary tag at publish time, AI may choose one default primary tag and apply it directly.
- If AI confidence for primary tag is low, leave the primary tag empty.
- If the user chose a primary tag at publish time, AI must not change that primary tag.
- Choosing a primary tag at publish time locks only the primary tag; it does not count as full `tagsUserEdited`.
- If the user chose a primary tag at publish time, AI may still add topic tags.
- If the user later edits tags in the single-moment tag editor, mark the moment as user-edited and do not auto-apply future AI tags for that moment.
- AI can apply at most three topic tags.
- AI should apply fewer topic tags when confidence is low; it should not fill the quota with vague tags.
- Topic tags can be specific concepts if they are likely reusable, such as `高斯概率分布`, `强化学习`, or `大语言模型`.
- One-off details, temporary names, and overly narrow facts should not become topic tags.
- AI must prefer existing topic tags and aliases before creating new topic tags.
- AI may create new topic tags only when no existing canonical tag or alias fits.
- AI output should include confidence metadata for primary and topic assignments.
- Confidence thresholds are product/model constants, not user-facing settings.

## Timeline UI

The timeline remains quiet.

Timeline tag display:

- Shows only the primary tag.
- Does not show topic tags.
- Is controlled by `Show tags in Timeline`.
- Hiding timeline tags also hides Day Review/Detail tag display and the Detail tag editing entry, but does not disable tags, AI tags, search, filtering, sync, or Settings management.

Metadata row layout:

- The primary tag appears on the same row as the time.
- The primary tag is near the right side of the metadata row.
- The right-side ordering is: primary tag, favorite star, abnormal sync status.
- Abnormal sync status is rightmost.
- `synced` success state is removed from the timeline entirely.
- Only states that require attention should show in timeline, such as `pending`, `uploading`, `partial`, or `failed`.
- If horizontal space is tight, hide or truncate the primary tag first.
- Time, favorite star, and abnormal sync status must remain stable and readable.

## Composer UI

The composer uses a light optional `Tag` control.

- The control is visible but not presented as required.
- If no primary tag is selected, publishing proceeds normally.
- The picker selects only one primary tag.
- Topic tags are not edited in the composer.
- Most common audio use should remain "publish now, AI handles tags later."

## Detail And Edit UI

Moment Detail:

- Shows complete primary/topic tags only when `Show tags in Timeline` is enabled.
- Hides the Tags section and single-moment tag editing entry when `Show tags in Timeline` is disabled.
- Does not show `AI suggested` or similar source labels in normal read mode.

Single-moment tag editor:

- Allows editing primary and topic tags.
- Allows topic search, addition, and removal.
- Shows lightweight source/provenance labels such as `AI` or `Manual`.
- Does not expose model, prompt, summary ID, or full provenance details.
- Shows archived tags attached to that moment, marked as archived, with remove or restore actions.
- Saving manual tag edits marks the moment as user-edited for AI tag overwrite prevention.

## Search And Filter

Tags integrate into the existing timeline search/filter model.

Filter:

- Tags are part of the existing Filter menu, not a new tab.
- Primary tags and topic tags are separate sections.
- Primary tag filters show the primary tag list.
- Topic tag filters show popular/recent topics plus search across all active topics.
- Multiple selected filters use AND semantics.
- Topic tags use AND semantics in the first version.

Search:

- Normal timeline search matches primary tags, topic tags, and aliases.
- Search results indicate tag match as a match source.
- Archived tags do not participate in ordinary search unless restored.
- First version only needs iPhone local search/filter support. Server `/api/v1/search` and Admin Posts search do not need tag filtering.

## Settings And Management

Add a light feature visibility setting:

- `Settings > Features > Tags > Show tags in Timeline`

This is display-only. It must not disable the tag system.

Add a tag management surface:

- `Settings > Tags`

Settings tag management supports:

- primary tag listing
- topic tag listing
- usage counts
- custom primary tag creation through a deep path
- custom primary rename/hide
- primary color customization with low-saturation defaults
- topic rename
- topic merge into canonical tag
- alias preservation
- topic archive/restore
- archived tag section

Mac Admin:

- May show lightweight tag counts or diagnostics.
- Does not manage tags in the first version.
- Should remain an operations surface, not a content management surface.

## Data And Sync Model

Tags are synced, durable metadata.

Required model concepts:

- Tag vocabulary is separate from post tag assignments.
- Tags have a stable ID.
- Tags have a type: `primary` or `topic`.
- A tag belongs to exactly one type.
- Tag names are globally unique across all active and archived tags.
- Aliases belong to tags and are used for matching/search.
- Post tag assignments reference tag IDs, not tag strings.
- AI-generated assignments are stored as normal tag assignments with source metadata.

Suggested server tables:

- `tags`
- `tag_aliases`
- `post_tags`

Suggested iOS tables:

- `local_tags`
- `local_tag_aliases`
- `local_post_tags`

Suggested tag fields:

- `id`
- `type` (`primary`, `topic`)
- `name`
- `normalizedName`
- `colorHex` for primary tags
- `isDefault`
- `isArchived`
- `aiUsableAsPrimary`
- `createdAt`
- `updatedAt`
- `archivedAt`

Suggested alias fields:

- `id`
- `tagId`
- `alias`
- `normalizedAlias`
- `createdAt`
- `deletedAt`

Suggested assignment fields:

- `id`
- `postId`
- `tagId`
- `role` (`primary`, `topic`)
- `source` (`manual`, `ai`)
- `confidence`
- `aiSummaryId`
- `createdAt`
- `updatedAt`
- `deletedAt`

Suggested post-level tag state:

- `aiTagProcessedAt`
- `tagsUserEditedAt`

Conflict semantics:

- Topic assignments merge independently.
- Topic deletes remove only the corresponding assignment.
- Primary assignment is single-select and uses last-write-wins by assignment `updatedAt`.
- Different devices adding different topic tags can both succeed.
- A moment-level user-edited marker blocks future automatic AI tag application.

Sync protocol should add tag vocabulary and post tag assignment changes. Exact operation names can be planned during slice planning, but the contract must cover tag create/update/archive, alias create/delete, post tag assign/delete, and server-originated AI tag assignment sync.

## AI Prompt And Privacy

The AI tag step may use:

- transcript text
- summary document fields
- tag vocabulary
- aliases

Normal logs must not contain:

- transcript body
- summary body
- post text
- comments
- private audio body

Logs and diagnostics may include:

- post ID
- media ID
- summary ID
- tag IDs
- tag counts
- provider/model
- input lengths
- status
- error code
- low-confidence skip counts

## Diagnostics

Settings > Storage & Diagnostics should include lightweight tag diagnostics because AI tags reuse summary processing.

Useful fields:

- active primary/topic tag counts
- archived tag count
- audio AI tag processed count
- AI tag failed/skipped count
- low-confidence skipped primary/topic counts
- server latest change version vs iPhone cursor if tag changes look stale

Do not expose transcript or summary content in diagnostics.

## Export And Backup

Tags are first-class user organization metadata and must be recoverable.

Any future backup/export/restore flow should include:

- tag vocabulary
- aliases
- archived state
- colors
- post tag assignments
- assignment source/confidence metadata where useful

## In Scope

- Default primary tags.
- Optional composer primary tag selection.
- Manual tag support for all moment types.
- AI automatic tags for new audio moments only.
- Topic tag vocabulary with aliases.
- Topic merge/archive/restore in Settings.
- Timeline primary tag display with feature visibility setting.
- Removing `synced` success status from timeline.
- Keeping abnormal sync statuses visible.
- Detail read-only full tags when tag display is enabled.
- Single-moment full tag editing when tag display is enabled.
- Local iPhone tag search/filter.
- Tag sync and recovery.
- Tag diagnostics.
- OpenAPI and sync protocol documentation updates.
- Real iPhone UAT.

## Out Of Scope / Non-Goals

- AI tags for video, image, or text-only moments.
- Historical audio backfill.
- Automatic tag generation when opening old summaries.
- `Regenerate tags`.
- Tag hierarchy.
- Topic colors.
- Full plugin system.
- Tag management in Mac Admin.
- Server-side search/filter by tags in the first version.
- Tag counts in timeline/filter chips.
- AI confirmation popups.
- Timeline `Tagging...` state.

## Suggested Slice Breakdown

1. Data and sync foundation:
   - server/iOS schema
   - vocabulary and assignment model
   - migration
   - sync operation/server change semantics
   - OpenAPI and sync protocol updates

2. iOS manual tagging UI:
   - composer primary tag picker
   - timeline primary chip and metadata row cleanup
   - `Show tags in Timeline`
   - detail read-only tags
   - edit tag management for one moment

3. Search and filter:
   - primary/topic filter sections
   - topic popular/recent plus search
   - tag and alias search match source
   - AND filtering

4. Settings tag management:
   - tag vocabulary screen
   - usage counts
   - topic rename/merge/archive/restore
   - custom primary create/rename/hide
   - primary color customization

5. Audio AI tag pipeline:
   - extend summary output contract
   - tag vocabulary prompt input
   - AI assignment application rules
   - confidence metadata
   - first-ready-only semantics
   - diagnostics

6. Verification and UAT:
   - migration tests
   - sync recovery tests
   - search/filter tests
   - real iPhone audio publication UAT
   - tag management UAT

## Final Integrated Acceptance

To call this milestone complete, prove:

- A user can publish any moment type without choosing a tag.
- A user can optionally choose exactly one primary tag in the composer.
- A user can edit primary and topic tags later in the single-moment tag editor when tag display is enabled.
- Default primary tags exist: `日记`, `想法`, `学习整理`, `情绪`, `碎碎念`, `复盘`.
- Topic tags can be dynamically added and are canonicalized with aliases.
- Topic merge preserves old names as aliases.
- Archived topic tags disappear from ordinary Timeline, visible Detail tags, Filter, and Search, but remain visible in Settings and the single-moment tag editor when tag display is enabled.
- Timeline and Day Review display only primary tags when `Show tags in Timeline` is on, and Moment Detail shows its Tags section only when the same switch is on.
- Turning off `Show tags in Timeline` hides timeline/Day Review chips and the Detail Tags section/edit entry without disabling tag data, search, filter, Settings management, sync, or AI tags.
- Timeline no longer shows `synced` as a success badge.
- Timeline still shows abnormal sync states such as pending/uploading/partial/failed.
- Metadata row ordering is stable: primary tag, favorite star, abnormal sync status.
- If space is tight, tag display yields before favorite or abnormal sync status.
- Filter separates primary tags and topic tags.
- Multiple selected filters use AND semantics.
- Search matches tag names and aliases and reports tag match source.
- Tags sync to the Mac server and recover on device reinstall.
- Topic tag assignments from different devices can merge.
- Conflicting primary tags use last-write-wins.
- A new clear-speech audio moment with no manual tag gets AI primary/topic tags after summary ready, when confidence is high enough.
- A new clear-speech audio moment with a manual primary tag keeps that primary tag and can receive AI topic tags.
- AI applies at most three topic tags and does not hard-fill uncertain tags.
- Summary regeneration does not regenerate or overwrite tags.
- If a user edits tags in the single-moment tag editor, future AI tag application is blocked for that moment.
- Summary failure leaves AI tags absent without extra timeline state.
- Video, image, and text-only moments do not receive AI automatic tags in the first version.
- Historical audio moments are not automatically backfilled.
- Settings diagnostics can explain tag/sync/AI tag state without leaking transcript or summary bodies.
- Tags are represented in shared sync protocol and OpenAPI documentation.
- Real iPhone UAT covers new audio publish, upload, summary ready, AI tags sync, timeline primary chip, filter, search, edit lockout, and tag management.

## Open Questions Deferred To Planning

- Exact schema and operation names.
- Exact primary tag colors and color picker affordance.
- Exact layout details for topic search inside Filter and the single-moment tag editor.
- Exact confidence thresholds for primary and topic tags.
- Whether future versions should add tag backfill, server search, Admin tag diagnostics, or broader AI auto-tagging.
