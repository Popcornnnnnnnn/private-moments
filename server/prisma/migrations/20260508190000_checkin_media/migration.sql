-- Add check-in-owned image media without reusing ordinary post media.
CREATE TABLE "checkin_media" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "entry_id" TEXT NOT NULL,
    "kind" TEXT NOT NULL,
    "status" TEXT NOT NULL,
    "compressed_path" TEXT,
    "mime_type" TEXT,
    "compressed_size_bytes" INTEGER,
    "checksum" TEXT,
    "sort_order" INTEGER NOT NULL DEFAULT 0,
    "created_at" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" DATETIME NOT NULL,
    "deleted_at" DATETIME,
    CONSTRAINT "checkin_media_entry_id_fkey" FOREIGN KEY ("entry_id") REFERENCES "checkin_entries" ("id") ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE INDEX "checkin_media_entry_id_idx" ON "checkin_media"("entry_id");
CREATE INDEX "checkin_media_status_idx" ON "checkin_media"("status");
CREATE INDEX "checkin_media_deleted_at_idx" ON "checkin_media"("deleted_at");
