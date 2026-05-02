# Contributing

Private Moments is currently a local-first personal timeline project. Contributions should preserve the product's quiet, private, iPhone-first shape.

## Development

```bash
npm run setup:local
npm run verify:server
```

iOS build check:

```bash
cd ios
xcodegen generate
xcodebuild -project PrivateMoments.xcodeproj -scheme PrivateMoments -destination generic/platform=iOS -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

## Pull Request Expectations

- Do not commit `server/.env`, runtime data, SQLite databases, media files, build output, `.gsd/`, or device container dumps.
- Keep secrets and transcript or summary bodies out of logs, screenshots, docs, and test fixtures.
- Update docs when changing setup, sync behavior, storage behavior, AI provider behavior, or iOS user-facing flows.
- For schema, sync, media, auth, or backup changes, include focused verification evidence.

## Product Guardrails

- The main timeline should stay quiet and scannable.
- Low-frequency controls belong in Settings, toolbar menus, detail views, or Admin UI.
- External AI credentials must stay on the Mac server.
- iOS should not receive provider API keys or raw provider configuration.
