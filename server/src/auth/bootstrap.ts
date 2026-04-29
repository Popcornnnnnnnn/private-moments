import type { PrismaClient } from "@prisma/client";

import { hashPassword } from "./password.js";
import type { FileLogger } from "../logging/file-logger.js";

export async function ensureSingleUser(
  prisma: PrismaClient,
  initialPassword: string | undefined,
  fileLogger: FileLogger,
): Promise<void> {
  const userCount = await prisma.user.count();

  if (userCount > 0) {
    return;
  }

  if (!initialPassword) {
    await fileLogger.warn("auth.setup_required", {
      message: "No user exists. Set PRIVATE_MOMENTS_INITIAL_PASSWORD and restart.",
    });
    return;
  }

  await prisma.user.create({
    data: {
      passwordHash: await hashPassword(initialPassword),
    },
  });

  await fileLogger.info("auth.initial_user_created");
}

