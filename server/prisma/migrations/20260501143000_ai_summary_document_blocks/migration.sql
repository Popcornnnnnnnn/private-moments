ALTER TABLE "ai_summaries" ADD COLUMN "document_title" TEXT;
ALTER TABLE "ai_summaries" ADD COLUMN "one_liner" TEXT;
ALTER TABLE "ai_summaries" ADD COLUMN "document_blocks_json" TEXT NOT NULL DEFAULT '[]';
