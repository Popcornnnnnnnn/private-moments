# Private Moments

Private Moments is a private, self-hosted personal timeline. The iOS app is the primary capture surface, and a Mac runs the local server, storage, sync API, and admin UI.

Current status: MVP local build. The Mac server, admin UI, sync API, and native iOS app build locally. The current app supports local-first text, image, audio, video, and text + media moments; Share Sheet import through `Save to Moments`; main-timeline private comments; smart primary/topic tags with color presets, HEX input, and batch primary color editing; editable occurred time; composer/edit drafts; lightweight H1/H2 body editing; offline outbox sync with delayed retry; image compression; video compression with posters; audio recording/playback; server-side AI summaries for uploaded audio/video using Mac-local `mlx-whisper` transcription plus an external summary API, structured document rendering, conservative AI tag suggestions for new audio, and optional AI title insertion for new audio; remote media recovery; Settings storage and AI-summary diagnostics; English human-friendly timeline dates; floating month hints while scrolling; timeline search/filter/month jump; favorites; detail/edit views; soft delete sync; and the Mac admin dashboard with Posts management.

- [PRD](docs/PRD.md)
- [Technical Design](docs/TECH-DESIGN.md)
- [Integration Guide](docs/INTEGRATION-GUIDE.md)
- [Operator Runbook](docs/OPERATOR-RUNBOOK.md)
- [Workflow](docs/WORKFLOW.md)
- [Handoff](docs/HANDOFF.md)
- [Design Principles](docs/DESIGN-PRINCIPLES.md)
- [Release Checklist](docs/RELEASE-CHECKLIST.md)
- [Open Source Readiness](docs/OPEN-SOURCE-READINESS.md)

## Development

Recommended local setup:

```bash
npm run setup:local
npm run server:dev
```

Optional setup flags:

```bash
npm run setup:local -- --with-ai
npm run setup:local -- --with-ios
```

`--with-ai` prepares the Mac-local `mlx-whisper` transcription environment. `--with-ios` regenerates the Xcode project with `xcodegen`.

Manual fallback:

```bash
npm install
cp server/.env.example server/.env
npm run server:prisma:generate
npm run server:prisma:deploy
npm run admin:build
npm run server:build
npm run server:dev
```

Before first start, set `PRIVATE_MOMENTS_INITIAL_PASSWORD` in `server/.env`. The setup script keeps an existing `server/.env` unchanged and only creates one from `server/.env.example` when missing. Agents should collect this value with secure secret handling instead of asking users to paste credentials into chat or documentation.

This password is only used to create the first local user when the database has no users.

The server defaults to:

```text
http://127.0.0.1:3210
```

After `npm run admin:build`, the Mac admin UI is served at:

```text
http://127.0.0.1:3210/admin/
```

## iOS App

Run the Mac server if needed, build the iOS app, install it into the iPhone 13 Pro simulator, and launch it:

```bash
npm run ios:simulator
```

Install and launch on the paired iPhone:

```bash
npm run ios:device
```

In the app, open Settings, enter the Mac server URL and the initial password, then log in. In the simulator, use `http://127.0.0.1:3210`. On a real iPhone, prefer the Mac's Tailscale Serve HTTPS address, such as `https://your-mac.tailnet-name.ts.net`, or override it with `PRIVATE_MOMENTS_DEVICE_SERVER_URL`.

The iOS app stores local posts, comments, tags, generated AI summary metadata, pending operations, compressed images, audio/video media, posters, legacy transcript metadata, Share Extension imports, and drafts under the app's Application Support or App Group directories. New audio/video posts do not run iOS speech transcription. Posting does not wait for network success; sync retries when the server is reachable, and failed pending work uses delayed automatic retry. Settings includes Storage & Diagnostics for local iPhone usage, sync health, AI summary diagnostics, re-downloadable audio/video cache cleanup, tag management, feature module toggles, and Mac server storage when the server is online.

After iOS code changes, rebuild and reinstall to the real device with `npm run ios:device`.

## launchd

Install the Mac login service:

```bash
server/scripts/install-launchd.sh
```

Uninstall it:

```bash
server/scripts/uninstall-launchd.sh
```

The default production data directory is:

```text
~/Library/Application Support/PrivateMoments
```

For local development, set `PRIVATE_MOMENTS_DATA_DIR` to avoid writing to the production directory.

The server soft-deletes posts first, then permanently removes expired deleted posts and media files after 30 days. Cleanup runs once on server startup and then every 6 hours while the service is running.

## Smoke Test

```bash
curl http://127.0.0.1:3210/api/v1/health

curl -X POST http://127.0.0.1:3210/api/v1/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"password":"your-password","deviceName":"Dev iPhone","platform":"ios"}'
```

For route details, admin filters, sync payloads, and media batch download examples, see [Integration Guide](docs/INTEGRATION-GUIDE.md).

## Release And Open Source

This repository is still intended for private/local-first use. Before making it public, complete the checks in [Release Checklist](docs/RELEASE-CHECKLIST.md), [Open Source Readiness](docs/OPEN-SOURCE-READINESS.md), and [Security And Privacy](SECURITY.md).
