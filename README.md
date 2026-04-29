# Private Moments

Private Moments is a private, self-hosted personal timeline. The iOS app is the primary capture surface, and a Mac runs the local server, storage, sync API, and admin UI.

Current status: MVP local build. The Mac server, admin UI, sync API, and native iOS app build locally. The current app supports local-first text/image publishing, editable occurred time, text/time/image drafts, offline outbox sync with delayed retry, upload-time image compression, image upload/download cache, Settings storage diagnostics, English human-friendly timeline dates, floating month hints while scrolling, timeline search/filter/month jump, favorites, detail view, image gallery with pan/zoom, post editing, soft delete sync, and the Mac admin dashboard with Posts management.

- [PRD](docs/PRD.md)
- [Technical Design](docs/TECH-DESIGN.md)
- [Integration Guide](docs/INTEGRATION-GUIDE.md)
- [Operator Runbook](docs/OPERATOR-RUNBOOK.md)
- [Handoff](docs/HANDOFF.md)
- [Design Principles](docs/DESIGN-PRINCIPLES.md)

## Development

```bash
npm install
cp server/.env.example server/.env
npm run server:prisma:generate
npm run server:prisma:migrate
npm run admin:build
npm run server:dev
```

Before first start, edit `server/.env` and set:

```text
PRIVATE_MOMENTS_INITIAL_PASSWORD=your-password
```

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

The iOS app stores local posts, pending operations, compressed images, and composer drafts under the app's Application Support directory. Posting does not wait for network success; sync retries when the server is reachable, and failed pending work uses delayed automatic retry. Settings includes a read-only Storage page for local iPhone usage, sync health, and Mac server storage when the server is online.

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
