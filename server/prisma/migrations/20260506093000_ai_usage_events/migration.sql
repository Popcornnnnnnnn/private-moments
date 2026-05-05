CREATE TABLE "ai_usage_events" (
  "id" TEXT NOT NULL PRIMARY KEY,
  "feature" TEXT NOT NULL,
  "subject_type" TEXT NOT NULL,
  "subject_id" TEXT,
  "provider" TEXT,
  "model" TEXT,
  "prompt_version" TEXT,
  "status" TEXT NOT NULL,
  "input_chars" INTEGER,
  "output_chars" INTEGER,
  "input_tokens" INTEGER,
  "output_tokens" INTEGER,
  "total_tokens" INTEGER,
  "cached_input_tokens" INTEGER,
  "estimated_input_tokens" INTEGER,
  "estimated_output_tokens" INTEGER,
  "estimated_total_tokens" INTEGER,
  "duration_ms" INTEGER,
  "error_code" TEXT,
  "created_at" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX "ai_usage_events_created_at_idx" ON "ai_usage_events"("created_at");
CREATE INDEX "ai_usage_events_feature_created_at_idx" ON "ai_usage_events"("feature", "created_at");
CREATE INDEX "ai_usage_events_status_created_at_idx" ON "ai_usage_events"("status", "created_at");
