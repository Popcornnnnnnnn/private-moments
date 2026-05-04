# M003: Feed Comments — Implementation Summary

**Date:** 2026-04-30
**Status:** Implemented; real-device launch verified; tactile UAT pending manual pass

## Delivered

- Added server `Comment` persistence with schema version 4 and migration `20260430213000_feed_comments`.
- Added `create_comment` and `delete_comment` sync operations with `comment_created` and `comment_deleted` server changes.
- Added parent-post constraints: comment create is rejected for missing/deleted posts, and post delete soft-deletes child comments while emitting only `post_deleted`.
- Added iOS `TimelineComment`, `local_comments`, local create/delete mutations, outbox payloads, server-change application, and parent delete cascade.
- Added main timeline comment UI: quiet comment button, count, latest-two preview, in-place expand/collapse, bottom input bar, send-success scroll-to-moment-bottom feedback for newest-comment visibility, 500-character limit, and long-press delete confirmation with pressed/haptic feedback.
- Added comment-aware timeline search that matches comments after existing filters and prioritizes matching comments in preview.
- Added Advanced Sync outbox operation counts without exposing private comment bodies.
- Updated `shared/openapi.yaml`, `shared/sync-protocol.md`, Chinese docs, and `.gsd` facts.

## Known Limitations

- Real iPhone build/install/launch succeeded for the latest code; tactile comment UAT still needs a manual pass.
- Comments are intentionally single-user only: no author display, replies, likes, media, editing, Markdown rendering, Admin UI management, or per-comment sync badges.
- The active dev server already running on port 3210 still reported schema version 3 during verification; current code was verified on a temporary 3211 server reporting schema version 4. Restart the long-running 3210 server to pick up the new build.
