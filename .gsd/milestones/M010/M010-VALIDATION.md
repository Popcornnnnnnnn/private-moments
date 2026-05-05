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
