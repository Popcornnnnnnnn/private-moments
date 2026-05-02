-- CreateTable
CREATE TABLE "users" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "password_hash" TEXT NOT NULL,
    "created_at" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" DATETIME NOT NULL
);

-- CreateTable
CREATE TABLE "devices" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "user_id" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "token_hash" TEXT NOT NULL,
    "platform" TEXT NOT NULL,
    "last_seen_at" DATETIME,
    "revoked_at" DATETIME,
    "created_at" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" DATETIME NOT NULL,
    CONSTRAINT "devices_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users" ("id") ON DELETE CASCADE ON UPDATE CASCADE
);

-- CreateTable
CREATE TABLE "posts" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "text" TEXT NOT NULL,
    "occurred_at" DATETIME NOT NULL,
    "created_at" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" DATETIME NOT NULL,
    "deleted_at" DATETIME,
    "client_created_at" DATETIME,
    "client_updated_at" DATETIME,
    "server_version" INTEGER NOT NULL DEFAULT 0,
    "created_by_device_id" TEXT,
    "updated_by_device_id" TEXT,
    CONSTRAINT "posts_created_by_device_id_fkey" FOREIGN KEY ("created_by_device_id") REFERENCES "devices" ("id") ON DELETE SET NULL ON UPDATE CASCADE,
    CONSTRAINT "posts_updated_by_device_id_fkey" FOREIGN KEY ("updated_by_device_id") REFERENCES "devices" ("id") ON DELETE SET NULL ON UPDATE CASCADE
);

-- CreateTable
CREATE TABLE "media" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "post_id" TEXT NOT NULL,
    "kind" TEXT NOT NULL,
    "status" TEXT NOT NULL,
    "compressed_path" TEXT,
    "original_path" TEXT,
    "thumbnail_path" TEXT,
    "original_preserved" BOOLEAN NOT NULL DEFAULT false,
    "width" INTEGER,
    "height" INTEGER,
    "compressed_size_bytes" INTEGER,
    "original_size_bytes" INTEGER,
    "checksum" TEXT,
    "sort_order" INTEGER NOT NULL DEFAULT 0,
    "created_at" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" DATETIME NOT NULL,
    "deleted_at" DATETIME,
    CONSTRAINT "media_post_id_fkey" FOREIGN KEY ("post_id") REFERENCES "posts" ("id") ON DELETE CASCADE ON UPDATE CASCADE
);

-- CreateTable
CREATE TABLE "sync_operations" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "op_id" TEXT NOT NULL,
    "device_id" TEXT NOT NULL,
    "type" TEXT NOT NULL,
    "entity_type" TEXT NOT NULL,
    "entity_id" TEXT NOT NULL,
    "payload_json" TEXT NOT NULL,
    "received_at" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "applied_at" DATETIME,
    "rejected_at" DATETIME,
    "rejection_reason" TEXT,
    CONSTRAINT "sync_operations_device_id_fkey" FOREIGN KEY ("device_id") REFERENCES "devices" ("id") ON DELETE CASCADE ON UPDATE CASCADE
);

-- CreateTable
CREATE TABLE "server_changes" (
    "version" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    "entity_type" TEXT NOT NULL,
    "entity_id" TEXT NOT NULL,
    "change_type" TEXT NOT NULL,
    "payload_json" TEXT NOT NULL,
    "created_at" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- CreateIndex
CREATE INDEX "devices_user_id_idx" ON "devices"("user_id");

-- CreateIndex
CREATE INDEX "devices_revoked_at_idx" ON "devices"("revoked_at");

-- CreateIndex
CREATE INDEX "posts_occurred_at_idx" ON "posts"("occurred_at");

-- CreateIndex
CREATE INDEX "posts_deleted_at_idx" ON "posts"("deleted_at");

-- CreateIndex
CREATE INDEX "posts_server_version_idx" ON "posts"("server_version");

-- CreateIndex
CREATE INDEX "media_post_id_idx" ON "media"("post_id");

-- CreateIndex
CREATE INDEX "media_status_idx" ON "media"("status");

-- CreateIndex
CREATE INDEX "media_deleted_at_idx" ON "media"("deleted_at");

-- CreateIndex
CREATE INDEX "sync_operations_entity_type_entity_id_idx" ON "sync_operations"("entity_type", "entity_id");

-- CreateIndex
CREATE UNIQUE INDEX "sync_operations_device_id_op_id_key" ON "sync_operations"("device_id", "op_id");

-- CreateIndex
CREATE INDEX "server_changes_entity_type_entity_id_idx" ON "server_changes"("entity_type", "entity_id");
