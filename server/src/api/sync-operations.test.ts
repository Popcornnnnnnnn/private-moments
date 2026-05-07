import assert from "node:assert/strict";
import test from "node:test";

import {
  SUPPORTED_SYNC_OPERATIONS,
  isSupportedSyncOperation,
  shouldReplayPreviouslyUnsupportedOperation,
} from "./sync-operations.js";

test("supported sync operation matrix includes all current client operation pairs", () => {
  const pairs = new Set(
    SUPPORTED_SYNC_OPERATIONS.map((operation) => `${operation.type}:${operation.entityType}`),
  );

  assert.deepEqual(
    Array.from(pairs).sort(),
    [
      "archive_tag:tag",
      "create_comment:comment",
      "create_post:post",
      "delete_comment:comment",
      "delete_post:post",
      "delete_tag:tag",
      "delete_tag_alias:tag_alias",
      "insert_ai_title:post",
      "merge_tag:tag",
      "restore_tag:tag",
      "set_post_tags:post",
      "update_media_transcription:media",
      "update_post:post",
      "update_post_favorite:post",
      "upsert_tag:tag",
      "upsert_tag_alias:tag_alias",
    ],
  );
});

test("isSupportedSyncOperation rejects valid operation names with the wrong entity type", () => {
  assert.equal(isSupportedSyncOperation({ type: "create_post", entityType: "comment" }), false);
  assert.equal(isSupportedSyncOperation({ type: "create_comment", entityType: "post" }), false);
  assert.equal(isSupportedSyncOperation({ type: "set_post_tags", entityType: "tag" }), false);
});

test("previous unsupported-operation rejection replays only after the operation becomes supported", () => {
  assert.equal(
    shouldReplayPreviouslyUnsupportedOperation(
      { rejectionReason: "Unsupported operation type: create_comment" },
      { type: "create_comment", entityType: "comment" },
    ),
    true,
  );
  assert.equal(
    shouldReplayPreviouslyUnsupportedOperation(
      { rejectionReason: "Unsupported operation type: create_comment" },
      { type: "create_comment", entityType: "post" },
    ),
    false,
  );
  assert.equal(
    shouldReplayPreviouslyUnsupportedOperation(
      { rejectionReason: "Comment parent post not found" },
      { type: "create_comment", entityType: "comment" },
    ),
    false,
  );
});
