-- CreateTable
CREATE TABLE "comments" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "post_id" TEXT NOT NULL,
    "text" TEXT NOT NULL,
    "created_at" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" DATETIME NOT NULL,
    "deleted_at" DATETIME,
    "client_created_at" DATETIME,
    "client_updated_at" DATETIME,
    "server_version" INTEGER NOT NULL DEFAULT 0,
    "created_by_device_id" TEXT,
    "updated_by_device_id" TEXT,
    CONSTRAINT "comments_post_id_fkey" FOREIGN KEY ("post_id") REFERENCES "posts" ("id") ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT "comments_created_by_device_id_fkey" FOREIGN KEY ("created_by_device_id") REFERENCES "devices" ("id") ON DELETE SET NULL ON UPDATE CASCADE,
    CONSTRAINT "comments_updated_by_device_id_fkey" FOREIGN KEY ("updated_by_device_id") REFERENCES "devices" ("id") ON DELETE SET NULL ON UPDATE CASCADE
);

-- CreateIndex
CREATE INDEX "comments_post_id_idx" ON "comments"("post_id");

-- CreateIndex
CREATE INDEX "comments_deleted_at_idx" ON "comments"("deleted_at");

-- CreateIndex
CREATE INDEX "comments_server_version_idx" ON "comments"("server_version");
