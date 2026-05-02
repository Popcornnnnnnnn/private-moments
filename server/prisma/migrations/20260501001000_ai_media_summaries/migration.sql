-- CreateTable
CREATE TABLE "ai_summaries" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "post_id" TEXT NOT NULL,
    "media_id" TEXT NOT NULL,
    "status" TEXT NOT NULL,
    "format" TEXT,
    "language" TEXT,
    "overview" TEXT,
    "key_points_json" TEXT NOT NULL DEFAULT '[]',
    "sections_json" TEXT NOT NULL DEFAULT '[]',
    "summary_text" TEXT,
    "input_transcript_hash" TEXT,
    "input_transcript_length" INTEGER,
    "input_duration_seconds" REAL,
    "prompt_version" TEXT NOT NULL,
    "provider" TEXT,
    "model" TEXT,
    "error_code" TEXT,
    "error_message" TEXT,
    "requested_by_device_id" TEXT,
    "created_at" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" DATETIME NOT NULL,
    "deleted_at" DATETIME,
    CONSTRAINT "ai_summaries_post_id_fkey" FOREIGN KEY ("post_id") REFERENCES "posts" ("id") ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT "ai_summaries_media_id_fkey" FOREIGN KEY ("media_id") REFERENCES "media" ("id") ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT "ai_summaries_requested_by_device_id_fkey" FOREIGN KEY ("requested_by_device_id") REFERENCES "devices" ("id") ON DELETE SET NULL ON UPDATE CASCADE
);

-- CreateIndex
CREATE UNIQUE INDEX "ai_summaries_media_id_key" ON "ai_summaries"("media_id");

-- CreateIndex
CREATE INDEX "ai_summaries_post_id_idx" ON "ai_summaries"("post_id");

-- CreateIndex
CREATE INDEX "ai_summaries_status_idx" ON "ai_summaries"("status");

-- CreateIndex
CREATE INDEX "ai_summaries_deleted_at_idx" ON "ai_summaries"("deleted_at");
