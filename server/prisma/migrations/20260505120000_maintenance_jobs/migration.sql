CREATE TABLE "maintenance_jobs" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "type" TEXT NOT NULL,
    "status" TEXT NOT NULL,
    "stage" TEXT,
    "progress" INTEGER NOT NULL DEFAULT 0,
    "metadata_json" TEXT NOT NULL DEFAULT '{}',
    "artifact_path" TEXT,
    "error_code" TEXT,
    "error_message" TEXT,
    "created_at" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "started_at" DATETIME,
    "finished_at" DATETIME
);

CREATE INDEX "maintenance_jobs_type_idx" ON "maintenance_jobs"("type");
CREATE INDEX "maintenance_jobs_status_idx" ON "maintenance_jobs"("status");
CREATE INDEX "maintenance_jobs_created_at_idx" ON "maintenance_jobs"("created_at");
