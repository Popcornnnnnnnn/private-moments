import assert from "node:assert/strict";
import test from "node:test";

import {
  getIntegerArray,
  getMediaOrder,
  getStringArray,
  parseJsonArray,
  parseJsonObject,
  parseSyncRequestBodyValue,
  parseSyncOperation,
} from "./sync-payload.js";

test("parseSyncOperation accepts a valid operation and normalizes dates", () => {
  const parsed = parseSyncOperation({
    opId: "op-1",
    type: "create_post",
    entityType: "post",
    entityId: "post-1",
    clientCreatedAt: "2026-05-08T12:34:56.000Z",
    payload: { text: "hello" },
  });

  assert.equal(parsed?.opId, "op-1");
  assert.equal(parsed?.clientCreatedAt.toISOString(), "2026-05-08T12:34:56.000Z");
  assert.deepEqual(parsed?.payload, { text: "hello" });
});

test("parseSyncOperation rejects invalid payload shape or dates", () => {
  assert.equal(
    parseSyncOperation({
      opId: "op-1",
      type: "create_post",
      entityType: "post",
      entityId: "post-1",
      clientCreatedAt: "not-a-date",
      payload: {},
    }),
    null,
  );
  assert.equal(
    parseSyncOperation({
      opId: "op-1",
      type: "create_post",
      entityType: "post",
      entityId: "post-1",
      clientCreatedAt: "2026-05-08T12:34:56.000Z",
      payload: [],
    }),
    null,
  );
});

test("parseSyncRequestBodyValue enforces request shape and local change limit", () => {
  const valid = parseSyncRequestBodyValue(
    {
      deviceId: "device-1",
      lastSyncCursor: 4,
      localChanges: [
        {
          opId: "op-1",
          type: "delete_post",
          entityType: "post",
          entityId: "post-1",
          clientCreatedAt: "2026-05-08T12:34:56.000Z",
          payload: { deletedAt: "2026-05-08T12:35:00.000Z" },
        },
      ],
    },
    1,
  );

  assert.equal(valid.ok, true);
  assert.equal(valid.ok ? valid.value.localChanges.length : 0, 1);

  const overLimit = parseSyncRequestBodyValue(
    {
      deviceId: "device-1",
      lastSyncCursor: 4,
      localChanges: [{}, {}],
    },
    1,
  );
  assert.deepEqual(overLimit, {
    ok: false,
    message: "localChanges cannot exceed 1 operations",
  });
});

test("array payload helpers deduplicate while preserving first-seen order", () => {
  assert.deepEqual(getStringArray({ ids: [" a ", "b", "a", "", "c"] }, "ids", 5), [
    "a",
    "b",
    "c",
  ]);
  assert.deepEqual(getIntegerArray({ days: [1, 2, 2, 7] }, "days", 7), [1, 2, 7]);
});

test("getMediaOrder rejects malformed media ordering input", () => {
  assert.deepEqual(
    getMediaOrder(
      {
        media: [
          { id: "m1", sortOrder: 0 },
          { id: "m2", sortOrder: 1 },
        ],
      },
      "media",
    ),
    [
      { id: "m1", sortOrder: 0 },
      { id: "m2", sortOrder: 1 },
    ],
  );
  assert.equal(getMediaOrder({ media: [{ id: "m1", sortOrder: -1 }] }, "media"), null);
});

test("JSON helpers keep sync payload parsing defensive", () => {
  assert.deepEqual(parseJsonObject("{\"a\":1}"), { a: 1 });
  assert.deepEqual(parseJsonObject("[1]"), {});
  assert.deepEqual(parseJsonArray("[1,2]"), [1, 2]);
  assert.deepEqual(parseJsonArray("{\"a\":1}"), []);
});
