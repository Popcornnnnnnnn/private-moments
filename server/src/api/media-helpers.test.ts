import assert from "node:assert/strict";
import test from "node:test";

import {
  contentTypeForMediaPath,
  mediaUploadErrorCode,
  parseMediaIds,
  parseMediaVariant,
  pathForMediaVariant,
} from "./media-helpers.js";

test("parseMediaIds trims, deduplicates, skips invalid entries, and caps batch size", () => {
  const ids = parseMediaIds([
    " media-1 ",
    "media-2",
    "",
    "media-1",
    null,
    ...Array.from({ length: 25 }, (_, index) => `extra-${index}`),
  ]);

  assert.equal(ids.length, 20);
  assert.deepEqual(ids.slice(0, 3), ["media-1", "media-2", "extra-0"]);
  assert.equal(new Set(ids).size, ids.length);
});

test("parseMediaVariant accepts only known media variants", () => {
  assert.equal(parseMediaVariant("compressed"), "compressed");
  assert.equal(parseMediaVariant("original"), "original");
  assert.equal(parseMediaVariant("thumbnail"), "thumbnail");
  assert.equal(parseMediaVariant("preview"), null);
});

test("pathForMediaVariant selects the requested storage path", () => {
  const media = {
    compressedPath: "media/compressed/a.jpg",
    originalPath: "media/original/a.heic",
    thumbnailPath: "media/thumbnail/a.jpg",
  };

  assert.equal(pathForMediaVariant(media, "compressed"), media.compressedPath);
  assert.equal(pathForMediaVariant(media, "original"), media.originalPath);
  assert.equal(pathForMediaVariant(media, "thumbnail"), media.thumbnailPath);
});

test("contentTypeForMediaPath maps supported media extensions", () => {
  assert.equal(contentTypeForMediaPath("photo.JPG"), "image/jpeg");
  assert.equal(contentTypeForMediaPath("poster.png"), "image/png");
  assert.equal(contentTypeForMediaPath("clip.mp4"), "video/mp4");
  assert.equal(contentTypeForMediaPath("voice.m4a"), "audio/mp4");
  assert.equal(contentTypeForMediaPath("unknown.bin"), "application/octet-stream");
});

test("mediaUploadErrorCode classifies timeout, premature close, and system errors safely", () => {
  const timeout = new Error("aborted");
  timeout.name = "AbortError";
  assert.equal(mediaUploadErrorCode(timeout), "upload_timeout");
  assert.equal(mediaUploadErrorCode(new Error("Premature close")), "client_premature_close");
  assert.equal(mediaUploadErrorCode({ code: "EEXIST" }), "eexist");
  assert.equal(mediaUploadErrorCode(new Error("other")), "upload_failed");
});
