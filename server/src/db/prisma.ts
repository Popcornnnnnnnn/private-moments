import { PrismaClient } from "@prisma/client";

import type { AppConfig } from "../config/app-config.js";

export function createPrismaClient(config: AppConfig): PrismaClient {
  return new PrismaClient({
    datasources: {
      db: {
        url: config.databaseUrl,
      },
    },
  });
}

