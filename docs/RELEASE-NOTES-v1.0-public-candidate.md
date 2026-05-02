# v1.0-public Candidate Release Notes

Date: 2026-05-02

This is the first sanitized public-release candidate snapshot of Private Moments.

## Included

- Local-first iOS timeline for text, image, audio, video, and text plus one media kind.
- Main-timeline private comments.
- Local Mac server with Fastify, Prisma, SQLite, local media storage, sync API, and Admin UI.
- Audio/video upload and playback support.
- Server-side AI media summaries using Mac-local transcription plus an external OpenAI-compatible summary provider.
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
