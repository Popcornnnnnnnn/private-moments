CREATE TABLE "reviews" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "kind" TEXT NOT NULL,
    "range_mode" TEXT NOT NULL,
    "range_start" DATETIME NOT NULL,
    "range_end" DATETIME NOT NULL,
    "status" TEXT NOT NULL,
    "trigger" TEXT NOT NULL,
    "content_json" TEXT NOT NULL DEFAULT '{}',
    "input_digest_hash" TEXT,
    "prompt_version" TEXT NOT NULL,
    "provider" TEXT,
    "model" TEXT,
    "language" TEXT,
    "error_code" TEXT,
    "error_message" TEXT,
    "generated_at" DATETIME,
    "regenerated_from_review_id" TEXT,
    "published_post_id" TEXT,
    "created_at" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" DATETIME NOT NULL,
    "deleted_at" DATETIME
);

CREATE TABLE "review_feedback" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "review_id" TEXT NOT NULL,
    "type" TEXT NOT NULL,
    "note" TEXT,
    "metadata_json" TEXT NOT NULL DEFAULT '{}',
    "created_at" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "review_feedback_review_id_fkey" FOREIGN KEY ("review_id") REFERENCES "reviews" ("id") ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE TABLE "review_memory" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "scope" TEXT NOT NULL,
    "key" TEXT NOT NULL,
    "value_json" TEXT NOT NULL DEFAULT '{}',
    "created_at" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" DATETIME NOT NULL
);

CREATE TABLE "review_settings" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "auto_weekly_enabled" BOOLEAN NOT NULL DEFAULT false,
    "publish_weekly_to_moments" BOOLEAN NOT NULL DEFAULT false,
    "last_auto_weekly_date" TEXT,
    "created_at" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" DATETIME NOT NULL
);

CREATE INDEX "reviews_kind_idx" ON "reviews"("kind");
CREATE INDEX "reviews_status_idx" ON "reviews"("status");
CREATE INDEX "reviews_range_start_range_end_idx" ON "reviews"("range_start", "range_end");
CREATE INDEX "reviews_created_at_idx" ON "reviews"("created_at");
CREATE INDEX "review_feedback_review_id_idx" ON "review_feedback"("review_id");
CREATE INDEX "review_feedback_type_idx" ON "review_feedback"("type");
CREATE UNIQUE INDEX "review_memory_scope_key_key" ON "review_memory"("scope", "key");

INSERT INTO "review_settings" ("id", "updated_at") VALUES ('default', CURRENT_TIMESTAMP);
