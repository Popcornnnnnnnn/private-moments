import assert from "node:assert/strict";
import test from "node:test";

import path from "node:path";

import {
  createUploadHashTracker,
  isPathInside,
  parseContentLength,
  tempUploadPath,
} from "./upload-helpers.js";

test("createUploadHashTracker records byte length and sha256 checksum", async () => {
  const tracker = createUploadHashTracker();
  tracker.stream.end(Buffer.from("abc"));
  await new Promise<void>((resolve, reject) => {
    tracker.stream.on("finish", resolve);
    tracker.stream.on("error", reject);
  });

  assert.deepEqual(tracker.result(), {
    sizeBytes: 3,
    checksum: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
  });
});

test("tempUploadPath stays in the target directory and hides the temp file", () => {
  const target = path.join("/tmp", "moments-upload", "photo.jpg");
  const temp = tempUploadPath(target);

  assert.equal(path.dirname(temp), path.dirname(target));
  assert.equal(path.basename(temp).startsWith(".photo."), true);
  assert.equal(temp.endsWith(".tmp"), true);
});

test("parseContentLength accepts only safe non-negative integers", () => {
  assert.equal(parseContentLength("12"), 12);
  assert.equal(parseContentLength(["34", "ignored"]), 34);
  assert.equal(parseContentLength("-1"), null);
  assert.equal(parseContentLength("1.5"), null);
  assert.equal(parseContentLength(undefined), null);
});

test("isPathInside rejects parent directory escapes", () => {
  assert.equal(isPathInside("/data/root", "/data/root/media/a.jpg"), true);
  assert.equal(isPathInside("/data/root", "/data/root"), false);
  assert.equal(isPathInside("/data/root", "/data/root/../secret.txt"), false);
});
