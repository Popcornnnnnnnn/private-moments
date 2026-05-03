import { buildApp } from "./app.js";
import { ensureSingleUser } from "./auth/bootstrap.js";
import { loadConfig } from "./config/app-config.js";
import { loadEnvFile } from "./config/env-file.js";
import { createPrismaClient } from "./db/prisma.js";
import { FileLogger } from "./logging/file-logger.js";
import { cleanupExpiredDeletedContent } from "./storage/cleanup.js";
import { ensureDataDir } from "./storage/data-dir.js";
import { ensureDefaultTags } from "./tags/tagging.js";

const CLEANUP_INTERVAL_MS = 6 * 60 * 60 * 1000;

async function main(): Promise<void> {
  await loadEnvFile(".env");

  const config = loadConfig();
  const paths = await ensureDataDir(config.dataDir);
  const fileLogger = new FileLogger(paths.logsDir);
  const prisma = createPrismaClient(config);

  await fileLogger.info("server.starting", {
    host: config.host,
    port: config.port,
    dataDir: paths.dataDir,
  });

  await ensureSingleUser(prisma, config.initialPassword, fileLogger);
  await ensureDefaultTags(prisma, fileLogger);
  await runCleanup(prisma, paths, fileLogger);

  const app = await buildApp({
    config,
    paths,
    fileLogger,
    prisma,
  });
  const cleanupTimer = setInterval(() => {
    void runCleanup(prisma, paths, fileLogger);
  }, CLEANUP_INTERVAL_MS);
  cleanupTimer.unref();

  app.addHook("onClose", async () => {
    clearInterval(cleanupTimer);
  });

  await app.listen({
    host: config.host,
    port: config.port,
  });

  await fileLogger.info("server.started", {
    host: config.host,
    port: config.port,
  });
}

async function runCleanup(
  prisma: ReturnType<typeof createPrismaClient>,
  paths: Awaited<ReturnType<typeof ensureDataDir>>,
  fileLogger: FileLogger,
): Promise<void> {
  try {
    await cleanupExpiredDeletedContent(prisma, paths, fileLogger);
  } catch (error) {
    await fileLogger.error("cleanup.failed", {
      message: error instanceof Error ? error.message : "Unknown error",
    });
  }
}

main().catch((error: unknown) => {
  console.error(error);
  process.exitCode = 1;
});
