-- AlterTable
ALTER TABLE "posts" ADD COLUMN "ai_tag_processed_at" DATETIME;
ALTER TABLE "posts" ADD COLUMN "tags_user_edited_at" DATETIME;

-- CreateTable
CREATE TABLE "tags" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "type" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "normalized_name" TEXT NOT NULL,
    "color_hex" TEXT,
    "is_default" BOOLEAN NOT NULL DEFAULT false,
    "is_archived" BOOLEAN NOT NULL DEFAULT false,
    "ai_usable_as_primary" BOOLEAN NOT NULL DEFAULT false,
    "created_at" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" DATETIME NOT NULL,
    "archived_at" DATETIME
);

-- CreateTable
CREATE TABLE "tag_aliases" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "tag_id" TEXT NOT NULL,
    "alias" TEXT NOT NULL,
    "normalized_alias" TEXT NOT NULL,
    "created_at" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "deleted_at" DATETIME,
    CONSTRAINT "tag_aliases_tag_id_fkey" FOREIGN KEY ("tag_id") REFERENCES "tags" ("id") ON DELETE CASCADE ON UPDATE CASCADE
);

-- CreateTable
CREATE TABLE "post_tags" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "post_id" TEXT NOT NULL,
    "tag_id" TEXT NOT NULL,
    "role" TEXT NOT NULL,
    "source" TEXT NOT NULL,
    "confidence" REAL,
    "ai_summary_id" TEXT,
    "created_at" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" DATETIME NOT NULL,
    "deleted_at" DATETIME,
    CONSTRAINT "post_tags_post_id_fkey" FOREIGN KEY ("post_id") REFERENCES "posts" ("id") ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT "post_tags_tag_id_fkey" FOREIGN KEY ("tag_id") REFERENCES "tags" ("id") ON DELETE CASCADE ON UPDATE CASCADE
);

-- CreateIndex
CREATE UNIQUE INDEX "tags_normalized_name_key" ON "tags"("normalized_name");
CREATE INDEX "tags_type_idx" ON "tags"("type");
CREATE INDEX "tags_is_archived_idx" ON "tags"("is_archived");
CREATE UNIQUE INDEX "tag_aliases_normalized_alias_key" ON "tag_aliases"("normalized_alias");
CREATE INDEX "tag_aliases_tag_id_idx" ON "tag_aliases"("tag_id");
CREATE UNIQUE INDEX "post_tags_post_id_tag_id_key" ON "post_tags"("post_id", "tag_id");
CREATE INDEX "post_tags_post_id_idx" ON "post_tags"("post_id");
CREATE INDEX "post_tags_tag_id_idx" ON "post_tags"("tag_id");
CREATE INDEX "post_tags_role_idx" ON "post_tags"("role");

-- Seed the small fixed primary vocabulary. IDs are stable so offline iOS defaults
-- and server-seeded defaults converge to the same records.
INSERT INTO "tags" (
    "id",
    "type",
    "name",
    "normalized_name",
    "color_hex",
    "is_default",
    "is_archived",
    "ai_usable_as_primary",
    "updated_at"
) VALUES
    ('tag-primary-diary', 'primary', '日记', '日记', '#D7E3F4', true, false, true, CURRENT_TIMESTAMP),
    ('tag-primary-idea', 'primary', '想法', '想法', '#E3DCF4', true, false, true, CURRENT_TIMESTAMP),
    ('tag-primary-learning', 'primary', '学习整理', '学习整理', '#DDEBD8', true, false, true, CURRENT_TIMESTAMP),
    ('tag-primary-emotion', 'primary', '情绪', '情绪', '#F4DEE4', true, false, true, CURRENT_TIMESTAMP),
    ('tag-primary-casual', 'primary', '碎碎念', '碎碎念', '#E7E2DA', true, false, true, CURRENT_TIMESTAMP),
    ('tag-primary-review', 'primary', '复盘', '复盘', '#F0E4D4', true, false, true, CURRENT_TIMESTAMP);

INSERT INTO "server_changes" ("entity_type", "entity_id", "change_type", "payload_json") VALUES
    ('tag', 'tag-primary-diary', 'tag_updated', '{"id":"tag-primary-diary","type":"primary","name":"日记","normalizedName":"日记","colorHex":"#D7E3F4","isDefault":true,"isArchived":false,"aiUsableAsPrimary":true,"createdAt":"2026-05-03T00:00:00.000Z","updatedAt":"2026-05-03T00:00:00.000Z","archivedAt":null}'),
    ('tag', 'tag-primary-idea', 'tag_updated', '{"id":"tag-primary-idea","type":"primary","name":"想法","normalizedName":"想法","colorHex":"#E3DCF4","isDefault":true,"isArchived":false,"aiUsableAsPrimary":true,"createdAt":"2026-05-03T00:00:00.000Z","updatedAt":"2026-05-03T00:00:00.000Z","archivedAt":null}'),
    ('tag', 'tag-primary-learning', 'tag_updated', '{"id":"tag-primary-learning","type":"primary","name":"学习整理","normalizedName":"学习整理","colorHex":"#DDEBD8","isDefault":true,"isArchived":false,"aiUsableAsPrimary":true,"createdAt":"2026-05-03T00:00:00.000Z","updatedAt":"2026-05-03T00:00:00.000Z","archivedAt":null}'),
    ('tag', 'tag-primary-emotion', 'tag_updated', '{"id":"tag-primary-emotion","type":"primary","name":"情绪","normalizedName":"情绪","colorHex":"#F4DEE4","isDefault":true,"isArchived":false,"aiUsableAsPrimary":true,"createdAt":"2026-05-03T00:00:00.000Z","updatedAt":"2026-05-03T00:00:00.000Z","archivedAt":null}'),
    ('tag', 'tag-primary-casual', 'tag_updated', '{"id":"tag-primary-casual","type":"primary","name":"碎碎念","normalizedName":"碎碎念","colorHex":"#E7E2DA","isDefault":true,"isArchived":false,"aiUsableAsPrimary":true,"createdAt":"2026-05-03T00:00:00.000Z","updatedAt":"2026-05-03T00:00:00.000Z","archivedAt":null}'),
    ('tag', 'tag-primary-review', 'tag_updated', '{"id":"tag-primary-review","type":"primary","name":"复盘","normalizedName":"复盘","colorHex":"#F0E4D4","isDefault":true,"isArchived":false,"aiUsableAsPrimary":true,"createdAt":"2026-05-03T00:00:00.000Z","updatedAt":"2026-05-03T00:00:00.000Z","archivedAt":null}');
