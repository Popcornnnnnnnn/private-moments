import assert from "node:assert/strict";
import test from "node:test";

import type { MultipartFields } from "@fastify/multipart";

import {
  extensionForCheckInMediaMimeType,
  parseCheckInMediaUploadFields,
  relativeCheckInMediaPath,
} from "./checkin-media-helpers.js";

function fields(values: Record<string, string>): MultipartFields {
  return Object.fromEntries(
    Object.entries(values).map(([key, value]) => [key, { type: "field", fieldname: key, value }]),
  ) as unknown as MultipartFields;
}

test("parseCheckInMediaUploadFields accepts only compressed image uploads", () => {
  const parsed = parseCheckInMediaUploadFields(
    fields({
      mediaId: "media-1",
      entryId: "entry-1",
      variant: "compressed",
      kind: "image",
      mimeType: "image/jpeg",
      sortOrder: "2",
    }),
  );

  assert.equal(parsed.ok, true);
  assert.equal(parsed.ok ? parsed.fields.variant : null, "compressed");
  assert.equal(parsed.ok ? parsed.fields.kind : null, "image");
  assert.equal(parsed.ok ? parsed.fields.sortOrder : null, 2);
});

test("parseCheckInMediaUploadFields rejects non-image and non-compressed uploads", () => {
  assert.deepEqual(
    parseCheckInMediaUploadFields(fields({ mediaId: "m", entryId: "e", variant: "thumbnail" })),
    {
      ok: false,
      message: "check-in media currently supports compressed image uploads only",
    },
  );
  assert.deepEqual(
    parseCheckInMediaUploadFields(
      fields({ mediaId: "m", entryId: "e", variant: "compressed", kind: "audio" }),
    ),
    { ok: false, message: "check-in media currently supports image uploads only" },
  );
});

test("check-in media path helpers keep photos out of ordinary post media paths", () => {
  assert.equal(
    relativeCheckInMediaPath("checkin-media-1", ".jpg"),
    "media/checkins/compressed/checkin-media-1.jpg",
  );
  assert.equal(extensionForCheckInMediaMimeType("image/png", "photo.bin"), ".png");
  assert.equal(extensionForCheckInMediaMimeType("application/octet-stream", "photo.custom"), ".custom");
  assert.equal(extensionForCheckInMediaMimeType("application/octet-stream", "photo"), ".jpg");
});
