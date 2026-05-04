# M004: Audio and Video Moments

**Gathered:** 2026-04-30
**Status:** Implemented first vertical slice; real-device UAT pending
**Depends on:** M003 Feed Comments should remain text-only; do not expand comments into media attachments while implementing this milestone.

## Project Description

Add audio and video as first-class media types for iOS moments. Audio/video should behave like images at the product level: they can stand alone as a moment, or appear together with moment text. They are not comment attachments and do not introduce public/social behavior.

This milestone touches iOS capture/import UI, media processing, local SQLite schema, server storage, sync payloads, media recovery, playback, cache management, Admin diagnostics, and real-device background audio behavior.

## User-Visible Outcome

When this milestone is complete, the user can:

- Create a text-only, image, video, audio, text+image, text+video, or text+audio moment.
- Choose one video from Photos, preview it in composer, remove it, and publish it if it is 2 minutes or shorter.
- Record one audio note inside composer, continue editing text while recording, pause/resume/stop, listen before publishing, rerecord, delete, or publish it.
- Record audio for up to 60 minutes, including while locked or in the background.
- Recover an interrupted recording as a composer draft and choose whether to use or discard the saved partial recording.
- See video moments in the timeline as muted inline autoplay when the card is the primary visible video, then tap to play fullscreen.
- See audio moments in the timeline as a light playback bar with play/pause, current time, total duration, progress, and speed options.
- Resume long audio from the last local playback position after pause or app restart; completed audio resets to the initial unplayed state.
- Keep audio playback running while locked or in the background.
- Use the existing Filter menu to filter Audio or Video moments.
- Search audio/video moments by iOS-generated transcript text after speech transcription completes.
- Clear re-downloadable audio/video cache from Settings > Storage without deleting archived moment content.

## Implementation Snapshot

As of 2026-04-30, the first implementation pass is in place:

- Server schema version 5 adds `media.mime_type` and `media.duration_seconds`.
- `/api/v1/media/upload` accepts `kind=image|video|audio`, stores typed media metadata, and uses `thumbnail` for video posters.
- iOS local media schema stores `kind`, local/remote thumbnail paths, `mimeType`, and `durationSeconds`.
- Composer supports image moments, Photos video import with 2-minute validation, 720p MP4 export, poster generation, and AAC/M4A audio recording.
- Composer image draft persistence only manages `.image` files, so clearing image drafts no longer deletes prepared MP4/M4A media files before publish.
- Server multipart upload limits now allow the typed media metadata fields introduced by M004, avoiding `reach fields limit` 500s during audio/video/image upload.
- Server thumbnail uploads no longer overwrite the primary media MIME, duration, width, or height metadata for video/audio/image records.
- Timeline/detail support muted inline video autoplay, fullscreen video playback, audio playback bars, playback progress reset on completion, and Audio/Video filters.
- Remote recovery automatically fetches image thumbnails and video posters; full audio/video download occurs on play.
- Settings > Storage can clear uploaded, re-downloadable full audio/video cache only.
- Admin shows media kind, MIME type, duration, size, status, and poster/thumbnail diagnostics without playback.
- Follow-up transcription pass raises server schema version to 6, adds `media.transcription_text`, adds iOS `local_media` transcription fields/status, and syncs transcripts through upload metadata or `update_media_transcription` / `media_transcription_updated`.
- iOS/server/Admin search now matches moment text, comments, and audio/video transcript text.

Known gaps for follow-up:

- Edit UI still needs the full replace-across-media-kind confirmation flow.
- On-demand audio/video download failures currently surface through the existing app error path rather than a media-card-only Retry control.
- Real iPhone background recording/playback and long-recording cap still need manual UAT evidence.
- Real iPhone speech-recognition permission, transcript quality, and transcript sync/search still need manual UAT evidence.

## Completion Class

- Contract complete means: shared OpenAPI and sync protocol describe media kinds, audio/video metadata, poster variants, on-demand download behavior, and failure semantics.
- Integration complete means: iOS, server, SQLite, sync, timeline, detail, edit, Admin diagnostics, and Settings Storage all understand image/audio/video media kinds without breaking existing image moments.
- Operational complete means: schema migration, media upload/download recovery, cache cleanup, background recording/playback, and real iPhone UAT have current evidence.

## Final Integrated Acceptance

To call this milestone complete, prove:

- Existing image-only and text+image moments still create, upload, sync, recover thumbnails, edit, and delete.
- A pure audio moment and a text+audio moment can be recorded, previewed, published, synced, played from timeline, resumed from saved progress, and played in background.
- Completed audio playback resets the timeline playback bar to the initial `0 / duration` state and clears the saved progress for that media.
- Audio recording supports pause/resume/stop, reaches the 60-minute cap by auto-stopping and preserving the file, and preserves partial recordings after interruption or app termination.
- A pure video moment and text+video moment can be selected from Photos, rejected if over 2 minutes, compressed to 720p H.264 MP4, assigned an iOS-generated poster, published, synced, restored with poster, and played fullscreen.
- A video moment autoplays muted when it becomes the primary visible video in the timeline, stops when scrolled away or when another media surface opens, and still opens fullscreen on tap.
- One media kind per moment is enforced in composer and edit, with confirmation before replacing existing media and text/occurred time preserved.
- Upload failure keeps the moment visible with media-level retry while local playback still works.
- On-demand full audio/video download failure shows inline Retry without a global alert.
- Settings > Storage can clear only re-downloadable full audio/video cache and does not delete archived media or local-only pending media.
- Admin shows type, size, status, and poster/thumbnail diagnostics without audio/video playback.
- Audio/video transcription is best-effort and does not block publishing; successful transcripts sync to Mac and are searchable in iOS, `/api/v1/search`, and Admin Posts search.

## Scope

### In Scope

- iOS media model expansion from image-only to typed media: image, video, audio.
- Server media model expansion for media kind, MIME type, duration, byte size, poster/thumbnail references, and variants needed by sync/recovery.
- Sync contract changes for typed media metadata and poster/download recovery.
- One media kind per moment:
  - up to 9 images;
  - 1 video;
  - 1 audio recording.
- Composer video flow:
  - choose from Photos only;
  - no in-app video capture;
  - reject videos longer than 2 minutes;
  - show preview and remove action;
  - no trim/crop UI.
- Video processing:
  - immediately process after selection;
  - composer shows Processing until ready;
  - compress to 720p H.264 MP4 with audio;
  - do not preserve the original video;
  - iOS generates a poster image;
  - poster generation failure blocks publish and asks user to reselect.
- Video timeline/detail playback:
  - timeline poster plus muted inline autoplay when the video is the primary visible card;
  - fullscreen playback;
  - autoplay is muted;
  - only one timeline video autoplays at a time;
  - no background video playback;
  - no video playback speed controls.
- Composer audio flow:
  - in-app recording inside composer media area;
  - record AAC M4A;
  - up to 60 minutes;
  - pause/resume/stop;
  - background and lock-screen recording;
  - user can edit moment text while recording;
  - after stop, user can listen, rerecord, delete, or publish.
- Audio failure and draft recovery:
  - recording writes to disk during recording;
  - interruptions, app kill, or other abnormal stop preserve recorded partial file as a draft;
  - returning to composer prompts to keep or discard the partial recording;
  - permissions, interruptions, and disk-space issues show clear recording-area status.
- Audio playback:
  - timeline playback bar;
  - play/pause, progress, current time, total duration;
  - no waveform in first version;
  - per-audio local playback progress persists across app restarts;
  - completed playback clears local progress and returns to the unplayed state;
  - 1x, 1.5x, and 2x speed;
  - background and lock-screen playback.
- Global playback policy:
  - only one audio or video can play at a time;
  - starting a new media item pauses the current one.
- Detail and edit:
  - detail can display/play audio/video;
  - edit can replace or delete audio/video;
  - edit may replace across media kinds after confirmation;
  - text and occurred time remain when media kind changes.
- Occurred time:
  - audio/video moments use existing occurredAt behavior;
  - default to moment creation time;
  - user can manually edit.
- Search/filter:
  - text search remains metadata-based and matches moment text, comments, and audio/video transcript text;
  - do not search filenames, raw audio content without a generated transcript, video OCR, or visual content;
  - existing Filter menu adds Audio and Video.
- Recovery and caching:
  - video recovery fetches poster automatically;
  - audio recovery fetches metadata only;
  - full audio/video downloads on play;
  - successful full downloads remain cached locally;
  - Settings > Storage can clear re-downloadable full audio/video cache.
- Failure UI:
  - upload failure keeps the moment visible;
  - media card shows Uploading or Upload failed plus Retry;
  - local file playback remains available when possible;
  - on-demand download failure shows inline Retry, not global alert.
- Admin:
  - show media type, size, status, and poster/thumbnail diagnostics;
  - no audio/video playback in Admin first version.

### Out of Scope / Non-Goals

- Audio or video comments.
- Mixing images, video, and audio inside one moment.
- Multiple videos or multiple audio recordings in one moment.
- In-app video recording.
- Video trimming, cropping, or manual poster selection.
- Preserving original video files.
- Unmuted inline video autoplay.
- Background video playback.
- Video speed controls.
- Audio waveform generation or waveform scrubbing.
- Video OCR, AI image search, semantic fuzzy search, or filename search.
- Admin audio/video playback.
- Public sharing, multi-user media comments, or audience-facing behavior.

## Architectural Decisions

- Audio/video are moment media, not comment media.
- Comments remain plain text only after M003.
- Extend existing media architecture rather than introducing separate audio/video tables unless implementation research proves a separate table is safer.
- Add explicit media type metadata and variants so existing image recovery and new audio/video on-demand recovery can share the same media pipeline.
- Store speech transcripts as media metadata rather than introducing a separate transcript entity in the first version.
- Keep timeline quiet: video autoplay is muted and single-active, audio is a compact playback bar, filters stay in the toolbar Filter menu.
- Treat background audio recording/playback as real-device-critical, not simulator-only.
- Prefer local file safety over optimistic publish: audio recordings land on disk while recording, and video publish waits for compression/poster success.

## High-Risk Areas

- iOS background audio modes and permission handling.
- AVFoundation recording interruptions, lock-screen behavior, and app termination recovery.
- Video compression duration, memory use, cancellation, and thermal behavior on real iPhone.
- SQLite/server schema migration from image-only media assumptions to typed media.
- Existing image sync and thumbnail recovery regressions.
- On-demand audio/video download with local cache invalidation and retry.
- Keeping local-only pending media safe when Settings Storage clears re-downloadable caches.
- Fullscreen video playback handoff while enforcing one global media playback source.

## Verification Bar

Run at least:

```bash
npm run server:build
npm run server:prisma:migrate
npm run admin:build
cd ios && xcodebuild -project PrivateMoments.xcodeproj -scheme PrivateMoments -destination generic/platform=iOS -configuration Debug CODE_SIGNING_ALLOWED=NO build
cd ios && xcodebuild -project PrivateMoments.xcodeproj -scheme PrivateMoments -destination 'platform=iOS Simulator,name=iPhone 17' test
npm run ios:device
```

Current focused evidence:

- 2026-04-30 regression check: `ComposerDraftStoreTests` covers that `saveImages([])` preserves prepared video draft files and ignores non-image draft files when loading images.
- 2026-04-30 device check: `npm run ios:device` built, installed, and launched Moments on `wwz 的 iphone` after the draft-file fix.
- 2026-04-30 server check: local `3210` dev server was restarted and `/api/v1/health` returned `schemaVersion: 5`.
- 2026-04-30 sync failure check: server logs showed failed media uploads with `message: "reach fields limit"`; after widening multipart limits, an isolated 3220 temp server accepted a typed media upload carrying M004 metadata and returned HTTP 200. Pulling the iPhone container after the 3210 restart showed the previously failed uploaded image/video/audio media had reached `uploaded` state.
- 2026-04-30 playback polish check: generic iOS Debug build passed, iOS simulator tests passed with 11 tests, `npm run ios:device` built and installed the app on `wwz 的 iphone`, and a follow-up `devicectl` launch succeeded.
- 2026-04-30 transcription implementation check: `server:typecheck`, `server:build`, `server:prisma:migrate`, `admin:build`, iOS simulator tests, and generic iOS Debug build passed; port 3210 server was restarted and `/api/v1/health` returned `schemaVersion: 6`; `npm run ios:device` built and installed on the paired iPhone, but auto-launch was blocked because the phone was locked.
- 2026-04-30 transcription visibility follow-up: generic iOS Debug build passed, `npm run ios:device` built/installed/launched on `wwz 的 iphone`, and a copied device SQLite check showed existing audio/video media had no transcript text (`transcript_len = 0`) because speech recognition reported no detected speech. The timeline now exposes transcript progress/failure status under the media card, queues old `not_requested` media, and retries older `No speech%` failures through the Chinese-first recognizer fallback before settling.
- 2026-05-01 transcription quality follow-up: iOS Speech transcription now requests partial results and persists the longest candidate from partial/final callbacks, so a short final result should not overwrite a more complete partial hypothesis. Existing non-empty transcripts are not automatically regenerated.
- 2026-05-04 background recording follow-up: composer recording now refreshes elapsed time after returning to the foreground, checks that `AVAudioRecorder` actually starts, and uses a `playAndRecord` / `spokenAudio` session with the existing `audio` background mode for app-switch recording. Generic iOS Debug build passed; real-device install could not complete because CoreDevice reported `wwz 的 iphone` as `unavailable`.

Also perform real iPhone UAT for:

- microphone permission denied and granted flows;
- long recording pause/resume/stop;
- lock-screen/background recording;
- lock-screen/background audio playback;
- interruption recovery;
- speech-recognition permission grant/deny, transcript display, transcript search, and transcript sync to Mac;
- video over-2-minute rejection;
- video compression and poster generation;
- upload failure retry;
- on-demand download failure retry;
- cache cleanup safety.

## Open Questions

No product-shaping question remains open from the 2026-04-30 discussion. Implementation may still decide internal helper boundaries, AVFoundation abstractions, and exact schema column names during planning.
