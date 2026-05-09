import assert from "node:assert/strict";
import test from "node:test";

import { applyCheckInOperation } from "./sync-checkins.js";
import { OperationRejectedError, type SyncOperationInput } from "./sync-types.js";

test("upsert_checkin_item defaults missing timeVisualization to none", async () => {
  const { tx, state } = fakeCheckInTx();

  await applyCheckInOperation(tx, checkInItemOperation({ timeVisualization: undefined }));

  assert.equal(state.itemCreate?.timeVisualization, "none");
  assert.equal(JSON.parse(state.changePayloadJson ?? "{}").timeVisualization, "none");
});

test("upsert_checkin_item accepts synced timeVisualization modes", async () => {
  for (const mode of ["none", "timeLine", "timeHeatmap"]) {
    const { tx, state } = fakeCheckInTx();

    await applyCheckInOperation(tx, checkInItemOperation({ timeVisualization: mode }));

    assert.equal(state.itemCreate?.timeVisualization, mode);
    assert.equal(JSON.parse(state.changePayloadJson ?? "{}").timeVisualization, mode);
  }
});

test("upsert_checkin_item rejects invalid timeVisualization", async () => {
  const { tx } = fakeCheckInTx();

  await assert.rejects(
    applyCheckInOperation(tx, checkInItemOperation({ timeVisualization: "chart" })),
    OperationRejectedError,
  );
});

test("upsert_checkin_item rejects timeLine for multiplePerDay items", async () => {
  const { tx } = fakeCheckInTx();

  await assert.rejects(
    applyCheckInOperation(tx, checkInItemOperation({
      recordMode: "multiplePerDay",
      timeVisualization: "timeLine",
    })),
    OperationRejectedError,
  );
});

function checkInItemOperation(
  overrides: {
    recordMode?: string;
    timeVisualization?: string;
  } = {},
): SyncOperationInput {
  const payload: Record<string, unknown> = {
    name: "Get up",
    symbolName: "sun.max",
    colorHex: "#F4C95D",
    recordMode: overrides.recordMode ?? "oncePerDay",
    activeWeekdays: [1, 2, 3, 4, 5, 6, 7],
    sortOrder: 0,
    defaultShowInTimeline: false,
    tagId: null,
    createdAt: "2026-05-09T00:00:00.000Z",
    updatedAt: "2026-05-09T00:00:00.000Z",
    archivedAt: null,
    deletedAt: null,
  };
  if (overrides.timeVisualization !== undefined) {
    payload.timeVisualization = overrides.timeVisualization;
  }

  return {
    opId: "op-checkin-item",
    type: "upsert_checkin_item",
    entityType: "checkin_item",
    entityId: "item-get-up",
    clientCreatedAt: new Date("2026-05-09T00:00:00.000Z"),
    payload,
  };
}

function fakeCheckInTx(): {
  tx: never;
  state: {
    itemCreate?: Record<string, unknown>;
    changePayloadJson?: string;
  };
} {
  const state: {
    itemCreate?: Record<string, unknown>;
    changePayloadJson?: string;
  } = {};

  const tx = {
    tag: {
      findUnique: async () => null,
    },
    checkInItem: {
      upsert: async (args: { create: Record<string, unknown> }) => {
        state.itemCreate = args.create;
        return {
          ...args.create,
          activeWeekdaysJson: args.create.activeWeekdaysJson,
          createdAt: args.create.createdAt,
          updatedAt: args.create.updatedAt,
          archivedAt: args.create.archivedAt,
          deletedAt: args.create.deletedAt,
          serverVersion: 0,
        };
      },
      update: async () => ({}),
    },
    serverChange: {
      create: async (args: { data: { payloadJson: string } }) => {
        state.changePayloadJson = args.data.payloadJson;
        return { version: 1 };
      },
    },
  };

  return { tx: tx as never, state };
}
