# v1.0-public Candidate Release Notes

Date: 2026-05-02

This is the first sanitized public-release candidate snapshot of Private Moments.

## 2026-05-03 Public Snapshot Update

This update syncs the public track with the latest private-development feature set while keeping public identifiers and local secrets sanitized.

### New User-Facing Features

- `Save to Moments` iOS Share Extension for importing photos, videos, audio files, text, and links from the system Share Sheet into the main Composer.
- Smart Tags for moments, including primary tags, topic tags, aliases, timeline visibility toggle, tag-aware search/filtering, color presets plus HEX input, archive/restore/delete, merge, and batch operations.
- AI tag suggestions for new audio moments after the first ready AI summary. Video, image, and plain-text moments are not automatically AI-tagged.
- AI summary v3 output with structured document blocks, more reliable short titles, conservative topic-tag generation, and tag-only fallback when the summary response omits tag suggestions.
- Optional AI title auto-insert for new audio moments without a handwritten heading. The app inserts only the generated title as a top `##` heading; summary bodies remain generated metadata.
- Basic Markdown-like moment text rendering for headings and lightweight body structure.
- Settings feature modules for timeline tag display and AI title insertion, plus System / Light / Dark appearance selection.

### Public-Track Sanitization

- Public iOS identifiers remain `dev.privatemoments.app`, `dev.privatemoments.app.share`, and `group.dev.privatemoments.app`.
- Personal Team ID, personal device defaults, private runtime data, `.gsd/`, local databases, media files, build outputs, and API keys remain excluded.
- Public README and English README now describe the new capture, Smart Tags, and AI-title capabilities.

## Included

- Local-first iOS timeline for text, image, audio, video, and text plus one media kind.
- Main-timeline private comments.
- `Save to Moments` Share Extension.
- Local Mac server with Fastify, Prisma, SQLite, local media storage, sync API, and Admin UI.
- Audio/video upload and playback support.
- Server-side AI media summaries using Mac-local transcription plus an external OpenAI-compatible summary provider.
- Smart Tags and tag-aware local organization.
- Timeline fuzzy search and composable local filters.
- Storage, sync, and AI summary diagnostics.
- One-command local setup: `npm run setup:local`.
- Local backup, restore, and metadata export commands.

## Public-Track Cleanup

- Private development Git history is not reused.
- `.gsd/` execution history is excluded.
- `server/.env`, runtime databases, media files, build output, and dependency directories are excluded.
- Default public iOS bundle id is `dev.privatemoments.app`.
- XcodeGen config does not include a personal Team ID.
- Real-device install requires explicit `PRIVATE_MOMENTS_DEVICE_NAME`.
- MIT license, SECURITY, CONTRIBUTING, and public-release docs are included.

## Known Limits

- Public GitHub publication still needs a final scan after the remote repository is created.
- Backup/restore/export scripts have passed a local smoke test, but should be tested on another clean machine before a tagged release.
- Production ATS/network hardening is documented as future work.
- AI provider behavior depends on the user's configured external API.
