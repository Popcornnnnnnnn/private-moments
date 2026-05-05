# M010: AI Periodic Reviews — Validation

## Automated Checks

- [x] `npm run server:prisma:generate`
- [x] `npm run server:typecheck`
- [x] `npm run server:test`
- [x] `npm run server:build`
- [x] `npm run admin:build`
- [x] `cd ios && xcodegen generate`
- [x] `xcodebuild -project ios/PrivateMoments.xcodeproj -scheme PrivateMoments -destination generic/platform=iOS -configuration Debug CODE_SIGNING_ALLOWED=NO build`
- [x] `git diff --check`
- [x] `ruby -e "require 'yaml'; YAML.load_file('shared/openapi.yaml')"`
- [x] HTTP smoke against an isolated schema-11 server:
  - login
  - get review settings
  - update review settings
  - list weekly reviews
  - generate rolling-seven-day review
  - save feedback

Current smoke evidence from 2026-05-05: isolated server returned `schemaVersion: 11`; review settings defaulted to `autoWeeklyEnabled: false` and `publishWeeklyToMoments: false`; update accepted `autoWeeklyEnabled: true`; generated review returned `status: ready`; feedback returned `ok: true`; review list returned `count: 1`.

Live server evidence from 2026-05-05: `npm run server:prisma:deploy` applied `20260505220000_periodic_reviews`; `curl -fsS http://127.0.0.1:3210/api/v1/health` returned `schemaVersion: 11`; unauthenticated `GET /api/v1/reviews/settings` returned `401 Missing bearer token`, confirming the route is registered behind device auth.

Sustainability fix evidence from 2026-05-05: focused server tests cover Review range/moment input limits and publish-as-moment Markdown staying within H1/H2-compatible output. Review generation now rejects ranges over 35 days and fails oversized provider input with `review_input_too_large`; Review/Archive schedulers catch and log tick failures.

Runtime fix evidence from 2026-05-05: after a real manual Weekly Review failed with `errorCode: invalid_json`, `review-generation` was updated to explicitly ask for JSON-only output and to tolerate common fenced/surrounded JSON provider responses. An isolated fake provider returning a Markdown fenced JSON response generated a ready review with title `Fenced JSON Review` and `errorCode: null`; the live LaunchAgent server was rebuilt and restarted, and `/api/v1/health` still returned `schemaVersion: 11`.

UAT fix evidence from 2026-05-05: after repeated taps on `Regenerate` created many review artifacts, iOS now tracks per-review in-flight mutations and disables regenerate/delete/publish while one is running; the Mac server also coalesces concurrent regenerate requests for the same source review. An isolated smoke generated a base ready review, sent two concurrent regenerate requests, received the same regenerated review id for both responses, then soft-deleted that review and observed the weekly list count drop from 2 to 1. `DELETE /api/v1/reviews/:reviewId` is documented in `shared/openapi.yaml` and `docs/INTEGRATION-GUIDE.md`.

Sparse-output fix evidence from 2026-05-06: live SQLite showed latest manual review `81d601d2-5577-421b-bf4c-1ec48deb0e0f` was `ready` with 92 input moments and 16 comments, but provider content had only a title while `oneLiner`, `keywords`, `themes`, `emotionalReflection.body`, `rhythm`, `notableMoments`, and `gentleSuggestions` were empty. Review generation now strengthens the schema/prompt and rejects sparse provider output for non-empty ranges with `empty_review_content` instead of marking it `ready`. Review deletion is now idempotent for already-soft-deleted review IDs so duplicate delete gestures do not surface `HTTP 404` to the app. Fresh verification passed `npm run server:test` with 8 tests, `npm run server:typecheck`, and `npm run server:build`; the LaunchAgent server was restarted and `/api/v1/health` returned `schemaVersion: 11`.

Provider resilience fix evidence from 2026-05-06: live SQLite showed manual review `3d738804-b7b1-46af-ba4a-bc832f059edf` failed with `provider_http_502` / `AI provider returned HTTP 502`. Review generation now retries retryable provider failures and poor provider outputs up to 3 attempts, then returns a conservative local fallback review for non-configuration failures instead of surfacing a failed empty review. New tests cover substantive local fallback output and a simulated provider returning HTTP 502 three times; `npm run server:test` passed 12 tests, `npm run server:typecheck` passed, and `npm run server:build` passed.

Single-flight generation fix evidence from 2026-05-06: after user clarified that any active generate/regenerate should disable all other review generation entry points, iOS now uses one global `isReviewGenerationInFlight` state for manual generate, regenerate, list navigation, delete, and publish controls. Server now enforces one active `generating` review globally: generate/regenerate returns the existing active generating review instead of creating a duplicate. Stale generating rows older than 15 minutes are marked `failed` with `review_generation_timeout` before another generation can proceed. Server tests now cover duplicate-create prevention and stale-generation timeout behavior; `npm run server:test` passed 14 tests, `npm run server:typecheck` passed, `npm run server:build` passed, and generic iOS build succeeded.

AI token usage ledger evidence from 2026-05-06: schema version 12 adds `ai_usage_events`; provider wrappers for media summary, weekly review, and tag fallback now record privacy-safe token usage metadata with provider usage when available and character-based estimates otherwise. Fresh verification passed `npm run server:prisma:generate`, `npm run server:typecheck`, `npm run server:test` with 12 tests including `src/ai/usage.test.ts`, `npm run server:build`, `npm run admin:build`, and `cd ios && xcodegen generate && xcodebuild -project PrivateMoments.xcodeproj -scheme PrivateMoments -destination generic/platform=iOS -configuration Debug CODE_SIGNING_ALLOWED=NO build`.

Live token usage deployment evidence from 2026-05-06: `npm run server:prisma:deploy` applied `20260506093000_ai_usage_events` to `server/data/app.sqlite`; `curl -fsS http://127.0.0.1:3210/api/v1/health` returned `schemaVersion: 12`; `ai_usage_events` existed with `COUNT(*) = 0`; authenticated `GET /api/v1/admin/status` returned `aiUsage` with zeroed `today`, `currentWeek`, `currentMonth`, and `allTime` windows before the next fresh AI call.

Real-device install evidence from 2026-05-06: `npm run ios:device` built `PrivateMoments.app` for `iphoneos`, signed the app and `Save to Moments` extension, and installed bundle `com.popcornnnnnn.privatemoments` on the connected iPhone. Automatic launch failed afterward because the device was locked (`Unable to launch ... because the device was not, or could not be, unlocked`), so UI navigation to `Settings > Storage & Diagnostics > AI Token Usage` still needs an unlocked-device check.

## Human UAT

- [ ] Calendar shows a low-noise `Reviews` entry.
- [ ] Manual `Generate Last 7 Days` creates a readable Weekly Review from real moments.
- [ ] Review tone feels like calm observation plus moderate encouragement.
- [ ] Review does not cite individual moments in ordinary theme/keyword/reflection sections.
- [ ] `Worth Revisiting` anchors are secondary and open inside the review context.
- [ ] Regenerate creates a new artifact without destroying the older readable review.
- [ ] Feedback controls feel low-friction and understandable.
- [ ] Settings toggles default off and update the Mac server setting.
- [ ] Optional publish-as-moment is explicit and never automatic by default.
- [ ] Settings > Storage & Diagnostics shows `AI Token Usage` after Mac server is reachable on schema version 12.
- [ ] A fresh media summary or Weekly Review increments the expected Today/This week/This month token totals without exposing transcript, prompt, review input, or summary body.
