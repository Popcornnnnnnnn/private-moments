# Private Moments Operator Runbook

This runbook covers local operation of the Mac server, admin UI, and iOS test app.

## Requirements

- macOS with Xcode installed.
- Node.js `>=22`.
- `npm`.
- `xcodegen` for regenerating `ios/PrivateMoments.xcodeproj`.
- Tailscale for real iPhone access outside simulator localhost.
- The paired iPhone must be unlocked and trusted for command-line install.

## Environment Variables

| Variable | Default | Purpose |
|---|---|---|
| `HOST` | `127.0.0.1` | Server bind address. Use `0.0.0.0` for LAN/Tailscale IP access. |
| `PORT` | `3210` | Server port. |
| `LOG_LEVEL` | `info` | Fastify log level. |
| `PRIVATE_MOMENTS_INITIAL_PASSWORD` | unset | Creates the first local user when the database has no users. |
| `PRIVATE_MOMENTS_DATA_DIR` | `~/Library/Application Support/PrivateMoments` | Runtime data directory. Development commonly uses `./server/data`. |
| `DATABASE_URL` | `file:<dataDir>/app.sqlite` | Prisma SQLite database URL. In `server/.env.example`, `file:./dev.db` is relative to `server/prisma/schema.prisma`. |
| `PRIVATE_MOMENTS_SERVER_URL` | `http://127.0.0.1:3210` | Simulator script server URL. |
| `PRIVATE_MOMENTS_SIM_NAME` | `Private Moments iPhone 13 Pro` | Simulator display name. |
| `PRIVATE_MOMENTS_DEVICE_TYPE` | `com.apple.CoreSimulator.SimDeviceType.iPhone-13-Pro` | Simulator device type. |
| `PRIVATE_MOMENTS_DEVICE_NAME` | `wwz 的 iphone` | Real iPhone name for `devicectl`. |
| `PRIVATE_MOMENTS_DEVICE_SERVER_URL` | auto-detected | Real-device server URL override. |
| `PRIVATE_MOMENTS_LAUNCHD_LABEL` | `com.private-moments.server` | launchd label. |

## Local Development Start

```bash
npm install
cp server/.env.example server/.env
npm run server:prisma:generate
npm run server:prisma:migrate
npm run admin:build
npm run server:dev
```

Set a real password in `server/.env` before first boot:

```text
PRIVATE_MOMENTS_INITIAL_PASSWORD=your-password
```

For real iPhone testing, make the server reachable from Tailscale:

```text
HOST=0.0.0.0
PRIVATE_MOMENTS_DATA_DIR="./data"
```

## Build And Install iOS

Simulator:

```bash
npm run ios:simulator
```

Real iPhone:

```bash
npm run ios:device
```

The real-device script:

1. Checks candidate server URLs.
2. Regenerates the Xcode project with `xcodegen` if available.
3. Builds a Debug iPhoneOS app.
4. Installs with `xcrun devicectl`.
5. Launches `com.popcornnnnnn.privatemoments`.

If iPhone blocks the app as an untrusted developer, trust it on the phone:

```text
Settings > General > VPN & Device Management > Developer App
```

## Mac Admin

After `npm run admin:build`, the server serves:

```text
http://127.0.0.1:3210/admin/
```

Use the same password as iOS login. Admin registers as a web device and uses the same Bearer token flow.

## launchd Service

Install:

```bash
server/scripts/install-launchd.sh
```

Uninstall:

```bash
server/scripts/uninstall-launchd.sh
```

Production data defaults to:

```text
~/Library/Application Support/PrivateMoments
```

launchd stdout/stderr logs:

```text
~/Library/Logs/private-moments.out.log
~/Library/Logs/private-moments.err.log
```

Application logs:

```text
<dataDir>/logs/app-YYYY-MM-DD.jsonl
```

## Smoke Checks

Server health:

```bash
curl -fsS http://127.0.0.1:3210/api/v1/health
```

Tailscale reachability from the Mac:

```bash
tailscale ip -4
curl -fsS http://<tailscale-ip>:3210/api/v1/health
```

Admin build and server typecheck:

```bash
npm run admin:build
npm run server:typecheck
```

Admin storage diagnostics, after logging in and setting `TOKEN` to a device token:

```bash
curl -fsS http://127.0.0.1:3210/api/v1/admin/status \
  -H "Authorization: Bearer $TOKEN"
```

The response should include `counts` plus `storage.totalBytes`, `storage.databaseBytes`, `storage.mediaBytes`, `storage.logsBytes`, and `storage.availableBytes`.

iOS compile without signing:

```bash
cd ios
xcodegen generate
xcodebuild -project PrivateMoments.xcodeproj \
  -scheme PrivateMoments \
  -destination generic/platform=iOS \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## Real iPhone Data Verification

Copy the app Library container:

```bash
rm -rf .tmp/device-app-library-check
mkdir -p .tmp/device-app-library-check
xcrun devicectl device copy from \
  --device "wwz 的 iphone" \
  --domain-type appDataContainer \
  --domain-identifier com.popcornnnnnn.privatemoments \
  --source Library \
  --destination .tmp/device-app-library-check \
  --timeout 60
```

Inspect sync state:

```bash
plutil -p .tmp/device-app-library-check/Preferences/com.popcornnnnnn.privatemoments.plist
sqlite3 '.tmp/device-app-library-check/Application Support/PrivateMoments/private-moments.sqlite' \
  'SELECT COUNT(*) FROM local_posts WHERE deletedAt IS NULL;'
```

Useful media recovery query:

```sql
SELECT COUNT(*) AS missing_visible_media
FROM local_media m
JOIN local_posts p ON p.id = m.postId
WHERE m.uploadStatus='uploaded'
  AND m.remoteCompressedPath IS NOT NULL
  AND m.localCompressedPath = ''
  AND m.deletedAt IS NULL
  AND p.deletedAt IS NULL;
```

Expected healthy value after cache recovery is `0`.

## Troubleshooting

### Login Fails With App Transport Security

Use HTTPS Tailscale Serve, or use an IP/host covered by the current `NSAppTransportSecurity` exceptions in `ios/PrivateMoments/Info.plist`. The development app currently allows arbitrary loads and local networking, but a clean production build should tighten this.

### Duplicate Devices

Repeated login should reuse `deviceKey`. If old duplicate rows exist, use Mac Admin device cleanup carefully. Do not revoke the active iPhone token unless you plan to log in again.

### Sync Shows Empty Timeline After Login

Check `lastSyncCursor` in app preferences. iOS recovery resets the cursor to `0` when the local database is empty or the one-time recovery flag has not been applied. After sync, `lastSyncCursor` should match the server's latest `server_changes.version`.

### Images Do Not Load

Check server logs for `media.batch_download`. iOS now uses batch thumbnail JSON for remote cache recovery. On the phone database, `missing_visible_media` should be `0`.

### Uploads Stay Pending

iOS uploads media one file at a time and compresses images before upload. If a large upload or Tailscale connection drops, the item remains in the local queue and sync schedules delayed retry with backoff. Check Settings > Storage > Sync Health for pending or failed counts, then inspect server logs for `media.upload` and sync errors.

### Storage Mac Server Section Is Missing

Settings > Storage always shows local iPhone usage. The Mac Server section appears only when the app is logged in and `/api/v1/admin/status` succeeds. Check the server URL, token state, and Tailscale reachability if the Mac section is hidden.

### Build Fails With Signing/Profile Errors

Open Xcode:

```text
Xcode > Settings > Accounts
Target PrivateMoments > Signing & Capabilities
```

Select the personal team, keep automatic signing enabled, unlock the iPhone, then rerun:

```bash
npm run ios:device
```
