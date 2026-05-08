-- Add local-first check-in items and entries for M012.
CREATE TABLE "checkin_items" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "name" TEXT NOT NULL,
    "symbol_name" TEXT NOT NULL,
    "color_hex" TEXT NOT NULL,
    "record_mode" TEXT NOT NULL,
    "active_weekdays_json" TEXT NOT NULL,
    "sort_order" INTEGER NOT NULL DEFAULT 0,
    "default_show_in_timeline" BOOLEAN NOT NULL DEFAULT false,
    "tag_id" TEXT,
    "created_at" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" DATETIME NOT NULL,
    "archived_at" DATETIME,
    "deleted_at" DATETIME,
    "server_version" INTEGER NOT NULL DEFAULT 0,
    CONSTRAINT "checkin_items_tag_id_fkey" FOREIGN KEY ("tag_id") REFERENCES "tags" ("id") ON DELETE SET NULL ON UPDATE CASCADE
);

CREATE TABLE "checkin_entries" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "item_id" TEXT NOT NULL,
    "occurred_at" DATETIME NOT NULL,
    "note" TEXT NOT NULL DEFAULT '',
    "show_in_timeline" BOOLEAN NOT NULL DEFAULT false,
    "client_created_at" DATETIME,
    "client_updated_at" DATETIME,
    "created_at" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" DATETIME NOT NULL,
    "deleted_at" DATETIME,
    "server_version" INTEGER NOT NULL DEFAULT 0,
    CONSTRAINT "checkin_entries_item_id_fkey" FOREIGN KEY ("item_id") REFERENCES "checkin_items" ("id") ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE INDEX "checkin_items_sort_order_idx" ON "checkin_items"("sort_order");
CREATE INDEX "checkin_items_archived_at_idx" ON "checkin_items"("archived_at");
CREATE INDEX "checkin_items_deleted_at_idx" ON "checkin_items"("deleted_at");
CREATE INDEX "checkin_items_tag_id_idx" ON "checkin_items"("tag_id");
CREATE INDEX "checkin_items_server_version_idx" ON "checkin_items"("server_version");

CREATE INDEX "checkin_entries_item_id_idx" ON "checkin_entries"("item_id");
CREATE INDEX "checkin_entries_occurred_at_idx" ON "checkin_entries"("occurred_at");
CREATE INDEX "checkin_entries_deleted_at_idx" ON "checkin_entries"("deleted_at");
CREATE INDEX "checkin_entries_server_version_idx" ON "checkin_entries"("server_version");
