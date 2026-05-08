-- Add lightweight synced pin metadata for M011 Pinned Moments.
ALTER TABLE "posts" ADD COLUMN "is_pinned" BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE "posts" ADD COLUMN "pinned_at" DATETIME;

CREATE INDEX "posts_is_pinned_pinned_at_idx" ON "posts"("is_pinned", "pinned_at");
