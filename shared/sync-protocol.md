# Private Moments Sync Protocol

This document defines the business rules for syncing iOS local changes with the Mac server.

## Goals

- iOS can create content offline.
- The UI renders from local SQLite first.
- Sync is retryable and idempotent.
- Mac is the authoritative archive.
- The data model supports multiple devices for one user.

## Terms

- `deviceId`: Stable ID for an authorized device.
- `deviceToken`: Long-lived secret used by a device to call the API.
- `opId`: Client-generated operation ID, unique per device.
- `syncCursor`: Last server change version processed by the client.
- `serverVersion`: Monotonic integer assigned by the Mac server to each accepted change.
- `outbox`: Local iOS table containing pending operations.
- `serverChanges`: Ordered server-side change log used for incremental pull sync.

## Core Flow

1. iOS writes user changes to local SQLite first.
2. iOS appends an operation to `outbox_operation`.
3. When the Mac server is reachable, iOS sends pending metadata operations to `POST /api/v1/sync`.
4. The server applies accepted operations transactionally.
5. iOS uploads media files for posts that now exist on the server.
6. iOS uploads check-in image media for check-in entries that now exist on the server.
7. iOS calls `POST /api/v1/sync` again to pull media upload changes and any generated metadata, such as AI summary status.
8. The server returns new server changes after the client's `syncCursor`.
9. iOS applies server changes locally and advances `lastSyncCursor`.
10. iOS downloads missing remote media thumbnails through `POST /api/v1/media/batch-download` and missing check-in images through `POST /api/v1/checkin-media/batch-download`.

Server-originated metadata can appear after the original local work is already synced. AI summaries are the current important example: the Mac may emit `ai_summary_updated` minutes after upload, so iOS performs foreground/manual diagnostic pull syncs even when there are no local outbox operations or pending uploads.

## MVP Operations

The MVP server currently supports these operation types:

- `create_post`: create a text post with `occurredAt`.
- `update_post`: replace post text, `occurredAt`, media order, and removed media set.
- `insert_ai_title`: insert one ready audio AI summary title as a top `##` heading without marking the post as a user edit.
- `update_post_favorite`: update only a post's favorite state.
- `delete_post`: soft delete an existing post.
- `create_comment`: create a private single-user plain-text comment attached to a post.
- `delete_comment`: soft delete a private comment.
- `update_media_transcription`: legacy operation for older clients to attach iOS-generated audio/video transcript text to an uploaded media item.
- `media_uploaded`: server-originated change emitted after `/api/v1/media/upload`.
- `media_transcription_updated`: server-originated change emitted after a transcript metadata update.
- `media_deleted`: server-originated change emitted when a media item is removed from a post.
- `ai_summary_updated`: server-originated change emitted after AI summary status/content changes.
- `ai_summary_deleted`: server-originated change emitted after a generated AI summary is soft-deleted.
- `upsert_tag`: create or update one primary/topic tag vocabulary entry.
- `archive_tag`: hide one non-default tag from normal timeline/detail/filter/search surfaces without deleting history.
- `restore_tag`: make an archived tag active again.
- `delete_tag`: permanently remove an archived non-default tag and free its normalized name for reuse.
- `merge_tag`: move one topic tag's active assignments into another topic tag, preserve the source name as an alias, and archive the source tag.
- `upsert_tag_alias`: create or update one searchable alias for a tag.
- `delete_tag_alias`: soft-delete one alias.
- `set_post_tags`: replace one post's primary tag and topic tag set, marking the moment as user-edited.
- `update_post_pin`: set or clear one post's lightweight pinned shortcut state.
- `upsert_checkin_item`: create or update one check-in item definition.
- `delete_checkin_item`: soft-delete one check-in item and its entries.
- `upsert_checkin_entry`: create or update one check-in entry.
- `delete_checkin_entry`: soft-delete one check-in entry.
- `delete_checkin_media`: soft-delete one uploaded check-in media record.
- `tag_updated`: server-originated vocabulary change.
- `tag_deleted`: server-originated permanent tag deletion.
- `tag_alias_updated` / `tag_alias_deleted`: server-originated alias changes.
- `post_tag_updated` / `post_tag_deleted`: server-originated assignment changes.
- `post_tag_state_updated`: server-originated post-level tag state change.
- `checkin_item_updated` / `checkin_item_deleted`: server-originated check-in item changes.
- `checkin_entry_updated` / `checkin_entry_deleted`: server-originated check-in entry changes.
- `checkin_media_uploaded` / `checkin_media_deleted`: server-originated check-in media changes.

Future operation types:

- `upsert_media`
- media status reconciliation

## Idempotency

Each local operation must include an `opId`. The server stores `(deviceId, opId)` in `sync_operation` with a unique constraint.

If the same operation is received again:

- The server must not apply it twice.
- The server should return it as accepted if the previous application succeeded.
- The server should return the previous rejection if it was rejected.

## Conflict Policy

MVP uses last write wins plus operation logs.

If two devices update the same entity, the operation received later by the server wins. The server keeps `sync_operation` rows for debugging and future recovery.

## Deletion

Deletes are soft deletes.

- iOS sets `deletedAt` locally and appends `delete_post`.
- The server sets `deletedAt` on the post and related media.
- The server also soft-deletes comments under a deleted post, but emits only the `post_deleted` server change; clients cascade local comments when applying `post_deleted`.
- Direct comment deletes use `delete_comment` and emit `comment_deleted`.
- Check-in item deletes use `delete_checkin_item`; the server soft-deletes the item and its entries, emits `checkin_item_deleted`, and clients cascade local entries.
- Direct check-in entry deletes use `delete_checkin_entry` and emit `checkin_entry_deleted`.
- Direct check-in media deletes use `delete_checkin_media` after the media has been uploaded; local-only pending check-in media can be dropped without a server operation.
- The server permanently deletes records and files after 30 days.

## Partial Media Sync

Post metadata and media files may sync separately.

- A post can be accepted before every media upload succeeds.
- Failed image, audio, or video uploads remain retryable.
- The iOS UI can show/play the local media while remote upload is pending.
- Sync status may be `pending`, `partial`, `synced`, or `failed`.
- iOS uploads media one file at a time. Images are compressed before upload; video is prepared as 720p H.264 MP4 with a poster thumbnail; audio is AAC/M4A.
- Failed sync or upload work schedules delayed retry with backoff: 5s, 20s, 60s, 120s, then 300s.
- Remote media cache recovery uses thumbnail batch download first for images and video posters. Full audio/video files download on demand when played and are cached locally.
- Audio/video transcription is no longer generated by new iOS clients. `update_media_transcription` remains accepted for older clients and historical metadata recovery.
- Check-in image media uses a separate parent model and separate upload/recovery routes. It does not create ordinary `Post` or `Media` rows and does not run AI summary, transcription, OCR, or AI tag pipelines.

## Smart Tags

Smart Tags are first-class sync metadata. Tag vocabulary is separate from post assignments so the user can maintain a stable organization layer while individual moments stay lightweight.

Vocabulary records:

- `tags`: primary/topic tag entries with stable IDs, canonical names, normalized names, optional primary color, default/archive flags, and `aiUsableAsPrimary`.
- `tag_aliases`: alternate searchable names for tags, soft-deleted with `deletedAt`.
- default primary tags are seeded by server and iOS: `日记`, `想法`, `学习整理`, `情绪`, `碎碎念`, `复盘`.

Post assignment records:

- `post_tags`: references post ID and tag ID.
- `role`: `primary` or `topic`.
- `source`: `manual` or `ai`.
- optional AI provenance: confidence and `aiSummaryId`.
- soft-deleted assignments keep history recoverable.

Manual operations:

`create_post` may include a `primaryTagId`. This creates a manual primary assignment without marking the whole tag set as user-edited; AI may still add topic tags later.

`set_post_tags` uses `entityType: "post"`, `entityId: <post id>`, and payload:

```json
{
  "primaryTagId": "tag-primary-learning",
  "topicTagIds": ["topic-neural-network", "topic-llm"],
  "updatedAt": "2026-05-03T12:00:00Z"
}
```

Server behavior:

- Validates that the primary tag is an active primary tag.
- Validates that topic IDs reference active topic tags.
- Replaces the post's active tag set.
- Marks all retained/new assignments as `manual`.
- Sets `Post.tagsUserEditedAt`, blocking future automatic AI tag application for that moment.
- Emits `post_tag_updated` and `post_tag_deleted` changes for assignment changes, then `post_tag_state_updated`.

Vocabulary operations:

- `upsert_tag` uses `entityType: "tag"` and payload `{type, name, colorHex, isDefault, aiUsableAsPrimary, updatedAt}`.
- `archive_tag` uses payload `{archivedAt}` and hides the tag from normal timeline/detail/filter/search.
- `restore_tag` reactivates an archived tag.
- `delete_tag` uses payload `{deletedAt}` and permanently deletes an archived non-default tag. The server emits `post_tag_deleted` for active assignments, `tag_alias_deleted` for active aliases, then `tag_deleted`.
- `upsert_tag_alias` uses `entityType: "tag_alias"` and payload `{tagId, alias}`.
- `delete_tag_alias` uses payload `{deletedAt}`.
- `merge_tag` uses `entityType: "tag"`, `entityId` as the source topic tag, and payload `{targetTagId, alias, mergedAt}`.

`merge_tag` server behavior:

- Requires source and target to be different topic tags.
- Requires target to be active.
- Moves active source assignments to the target tag.
- If a post already has the target tag, the source assignment is soft-deleted.
- Preserves the source name as an alias on the target when it does not conflict.
- Archives the source tag.
- Emits assignment, alias, and tag server changes in version order.

iOS behavior:

- Stores vocabulary in `local_tags` and `local_tag_aliases`.
- Stores assignments in `local_post_tags`.
- Applies `post_tag_updated` by assignment ID first, because a server-side `merge_tag` may move an existing assignment from the source topic to the target topic while preserving the assignment ID.
- Timeline may show only the primary tag and only when `Show Tags in Timeline` is enabled.
- Timeline does not show the `synced` success badge; only abnormal sync states remain visible.
- Search can match tag names and aliases. Filters separate primary tags and topic tags.
- Settings > Tags manages the local vocabulary and queues sync operations like other local-first edits.

## Remote Media Cache Recovery

`POST /api/v1/media/batch-download` accepts:

```json
{
  "mediaIds": ["media-id-1", "media-id-2"],
  "variant": "thumbnail"
}
```

The response returns base64 JSON payloads keyed by media id. iOS writes image thumbnails to `local_media.localCompressedPath` and video posters to `local_media.localThumbnailPath`.

Server behavior:

- `thumbnail` is the default variant for iOS recovery.
- Thumbnails are generated on demand with max edge `800px`.
- Oversized existing thumbnails are regenerated.
- Missing or deleted media ids are skipped instead of failing the entire batch.

## Editing

Editing is represented as a direct overwrite, not a visible version history.

`update_post` payload:

```json
{
  "text": "latest text",
  "occurredAt": "2026-04-29T12:00:00Z",
  "updatedAt": "2026-04-29T12:05:00Z",
  "media": [
    { "id": "existing-or-new-media-id", "sortOrder": 0 }
  ],
  "removedMediaIds": ["media-id-to-soft-delete"]
}
```

The server updates the post, soft-deletes removed media, updates `sortOrder` for existing media, and emits server changes for the updated post and removed media. Newly added media records are created later by the existing media upload endpoint.

If two devices edit the same post offline, the last operation applied by the server wins.

`insert_ai_title` payload:

```json
{
  "summaryId": "ready-ai-summary-id",
  "mediaId": "audio-media-id",
  "insertedAt": "2026-05-03T12:05:00Z"
}
```

The client does not send the generated title body in this operation. The server reloads `documentTitle` from its own ready `ai_summaries` row, verifies that the summary belongs to the target post and audio media, skips safely if the post already has a leading `# ` or `## ` title, and emits `post_updated` with `updateSource: "ai_title"` when it changes text. Clients should not treat that server change as a user edit marker.

## Favorites

Favorite state is synced as metadata on the post, but it uses a separate lightweight operation so starring a moment does not require entering the edit flow.

`update_post_favorite` payload:

```json
{
  "isFavorite": true,
  "updatedAt": "2026-04-29T12:06:00Z"
}
```

The server updates `Post.isFavorite`, emits `post_favorite_updated`, and assigns a new `serverVersion`. Clients should keep the time line visually quiet: favorites are a small marker and filter target, not a prominent content block.

## Pinned Moments

Pinned moments use lightweight post metadata. Pinning does not change `occurredAt`, does not rewrite post text, does not set user-edit metadata, and does not interact with favorite state.

`update_post_pin` payload:

```json
{
  "isPinned": true,
  "pinnedAt": "2026-05-08T12:00:00Z",
  "updatedAt": "2026-05-08T12:00:00Z"
}
```

Server behavior:

- Validates that the post exists and is not deleted.
- Updates `Post.isPinned` and `Post.pinnedAt`.
- Emits `post_pin_updated` with `id`, `isPinned`, nullable `pinnedAt`, and `updatedAt`.
- Includes pin fields in `post_created` and `post_updated` payloads for baseline recovery.
- Uses last server-accepted operation wins for pin/unpin conflicts.

iOS behavior:

- Applies `post_pin_updated` into `local_posts.isPinned` / `local_posts.pinnedAt`.
- Shows pinned moments only on the unfiltered Timeline. Active search/filter state hides the pinned surface.
- Defaults to a collapsed `Pinned · N` header; one to three pinned moments can expand into title rows, while more than three open a bottom sheet list.
- Keeps pinned items in the ordinary unfiltered Timeline list with a lightweight marker; the top shelf is only an extra shortcut entry point.
- Keeps pinned moments in their original chronological Calendar, Day Review, search/filter, review input, and detail positions.
- Treats pin/unpin like favorite in edit semantics: it does not set user edited metadata and does not change post text or `occurredAt`.

## Check-ins

Check-ins are independent local-first life-activity records. They are not ordinary posts and must not create linked `Post` rows. A check-in entry can optionally be rendered in Timeline through `showInTimeline`, but Calendar, Day Review, Check-ins History, Month Stats, and future review structure signals use non-deleted entries regardless of Timeline visibility.

Item payloads use `entityType: "checkin_item"`, `entityId: <item id>`.

`upsert_checkin_item` payload:

```json
{
  "name": "Meal",
  "symbolName": "fork.knife",
  "colorHex": "#D98E73",
  "recordMode": "multiplePerDay",
  "activeWeekdays": [1, 2, 3, 4, 5, 6, 7],
  "sortOrder": 2,
  "defaultShowInTimeline": false,
  "tagId": null,
  "createdAt": "2026-05-08T09:00:00Z",
  "updatedAt": "2026-05-08T09:00:00Z",
  "archivedAt": null
}
```

`delete_checkin_item` payload:

```json
{
  "deletedAt": "2026-05-08T12:00:00Z"
}
```

Entry payloads use `entityType: "checkin_entry"`, `entityId: <entry id>`.

`upsert_checkin_entry` payload:

```json
{
  "itemId": "checkin-meal",
  "occurredAt": "2026-05-08T12:30:00Z",
  "note": "Lunch",
  "showInTimeline": false,
  "createdAt": "2026-05-08T12:30:00Z",
  "updatedAt": "2026-05-08T12:30:00Z"
}
```

`delete_checkin_entry` payload:

```json
{
  "deletedAt": "2026-05-08T12:45:00Z"
}
```

Check-in image media is uploaded after the entry metadata syncs. It uses `POST /api/v1/checkin-media/upload` with multipart fields:

- `mediaId`
- `entryId`
- `variant=compressed`
- `kind=image`
- optional `mimeType`
- optional `sortOrder`
- `file`

Only still images are enabled in this checkpoint. The iOS UI reserves the richer media entry shape, but check-in audio/video capture is not active yet.

`delete_checkin_media` payload:

```json
{
  "deletedAt": "2026-05-08T12:45:00Z"
}
```

Server behavior:

- Validates item names, record modes, colors, weekdays, optional active tag references, and timestamps.
- Validates entry parent item existence and soft-delete state.
- Relies on iOS to perform local same-day validation before enqueueing once-per-day entries; v1 does not add a conflict UI for rare cross-device duplicate check-ins.
- Stores check-in media under `media/checkins/compressed/` and emits `checkin_media_uploaded` after a successful upload.
- Emits `checkin_item_updated`, `checkin_item_deleted`, `checkin_entry_updated`, `checkin_entry_deleted`, `checkin_media_uploaded`, and `checkin_media_deleted` server changes.
- Does not invoke AI summary, transcription, OCR, or AI tag pipelines for check-ins.

iOS behavior:

- Stores items in `local_checkin_items`, entries in `local_checkin_entries`, and image attachments in `local_checkin_media`.
- Shows Check-ins as a third bottom tab after Calendar, while default launch remains Timeline.
- Creates empty semantic entries with one tap in Today.
- Supports adding/replacing/removing one photo from the richer entry flow and entry detail. Simulator builds cannot use hardware camera, but real devices use the camera picker.
- Uses entry-level `showInTimeline` to decide whether the mixed Timeline feed includes a compact check-in row.
- Includes all non-deleted entries in Calendar activity counts and Day Review, including entries hidden from Timeline.
- History supports per-item filtering; photo check-ins appear in History and Day Review, and `Photos` filters include photo check-ins.
- Exposes item/entry management and lightweight diagnostics on iOS; Mac Admin does not manage Check-ins in v1.

## Comments

Comments are single-user, private, plain-text follow-up entries attached to a post. They are independent entities so comment create/delete operations do not rewrite the post payload.

Comments are intentionally not a public social system:

- no visible author identity
- no replies or nested threads
- no likes, mentions, reactions, or public feedback features
- no media attachments
- no Markdown or rich-text rendering
- no comment editing in the first version

`create_comment` uses `entityType: "comment"`, `entityId: <comment id>`, and payload:

```json
{
  "postId": "post-id",
  "text": "plain text comment",
  "createdAt": "2026-04-30T12:07:00Z"
}
```

Server behavior:

- Rejects empty or whitespace-only text.
- Rejects text over 500 characters.
- Rejects comments for missing or deleted posts.
- Emits `comment_created` with `{ id, postId, text, createdAt, updatedAt, deletedAt: null }`.

`delete_comment` uses `entityType: "comment"`, `entityId: <comment id>`, and payload:

```json
{
  "postId": "post-id",
  "deletedAt": "2026-04-30T12:08:00Z"
}
```

Server behavior:

- Soft-deletes the comment if it exists and is not already deleted.
- Emits `comment_deleted` with `{ id, postId, deletedAt }` for direct comment deletes.
- Accepts a delete for an already-deleted comment as a no-op under the same operation log semantics.

iOS behavior:

- Comments are stored in `local_comments`.
- Comment rows do not show per-comment sync state.
- Pending/failed comment operations are visible through global sync/outbox diagnostics.
- If a newly created local comment is deleted before its `create_comment` operation is sent, iOS can cancel the local create operation instead of syncing create-then-delete.
- If iOS receives a recognized comment server change but the parent post is missing, it must fail applying that change and must not advance `lastSyncCursor`.

## Legacy Audio/Video Transcription

New iOS clients do not generate local speech transcripts. This section remains only for older clients and historical metadata compatibility.

`update_media_transcription` uses `entityType: "media"`, `entityId: <media id>`, and payload:

```json
{
  "postId": "post-id",
  "transcriptionText": "plain transcript text",
  "updatedAt": "2026-04-30T12:10:00Z"
}
```

Server behavior:

- Rejects empty or whitespace-only transcript text.
- Rejects transcript text over 100,000 characters.
- Rejects updates for missing, deleted, or wrong-parent media.
- Emits `media_transcription_updated` with `{ id, postId, transcriptionText, updatedAt }`.

New iOS behavior:

- Does not link Speech framework, request speech recognition permission, or create `update_media_transcription`.
- Does not upload `transcriptionText` in media multipart metadata.
- Does not show transcript snippets, transcript fallback, or transcript failure states in the timeline.

## AI Media Summaries

AI summaries are generated metadata attached to one audio/video media item. They are not comments, transcript edits, or visible transcript fallback. The only post text exception is optional new-audio title insertion through `insert_ai_title`; summary bodies remain generated metadata.

Generation is server-owned:

1. iOS uploads complete audio/video media to `/api/v1/media/upload`.
2. The Mac server starts a background AI summary job for uploaded audio/video media.
3. The job transcribes the stored media file locally on the Mac with `mlx-whisper`, then sends the internal transcript to the configured external summary API.
4. The Mac server records `transcribing`, then `summarizing`, then validates structured output and stores either `ready` or `failed`.
5. The server emits `ai_summary_updated` for status/content changes and `ai_summary_deleted` when the user deletes generated summary metadata.
6. iOS applies these changes to `local_ai_summaries` and advances `lastSyncCursor` only after all changes in the response are applied.
7. iOS may call `POST /api/v1/ai/media-summary` with `{ postId, mediaId, forceRegenerate }` to regenerate an existing summary.

The summary payload includes:

- `id`, `postId`, `mediaId`
- `status`: `transcribing`, `summarizing`, `ready`, `failed`, or `deleted`
- generated content fields: `format`, `language`, `documentTitle`, `oneLiner`, `documentBlocks`, and `summaryText`
- structured tag suggestions under `suggestedTags`, with one optional default primary tag and up to three topic suggestions
- legacy compatibility fields: `overview`, `keyPoints`, and `sections`
- provenance fields: `promptVersion`, `provider`, `model`, nullable input transcript length/hash, optional media duration
- lightweight failure fields: `errorCode`, `errorMessage`
- timestamps and optional `deletedAt`

Privacy and failure rules:

- The iPhone never stores or sends provider credentials.
- The Mac server reads only the selected media file for local transcription and sends only the resulting transcript to the configured summary provider.
- iOS never receives the transcript body from the new AI path.
- Normal logs must record IDs, provider/model, status, error code, and input length only; they must not include transcript text or summary bodies.
- Missing media files, transcription failures, empty transcripts, provider failures, or invalid output should not block media upload, comments, or normal post sync.
- Provider failures are isolated to the `ai_summaries` row and can be retried/regenerated later.
- AI summary generated metadata participates in iPhone local search, but server-side search remains narrower unless explicitly extended.

## Cursor Rules

`syncCursor` refers to the largest `server_change.version` the client has applied.

The server response includes `nextSyncCursor`, which should only be stored locally after iOS successfully applies all returned `serverChanges`.

If the iOS local post table is empty, the client should request cursor `0` even if UserDefaults has an older nonzero cursor. This supports archive recovery after reinstall, failed migration, or the 2026-04-29 cursor recovery bug.

iOS must reject invalid server changes instead of silently skipping them and advancing cursor. Timestamp parsing must handle both fractional and non-fractional ISO8601 strings.
