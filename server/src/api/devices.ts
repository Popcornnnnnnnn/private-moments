import type { PrismaClient } from "@prisma/client";
import type { FastifyInstance } from "fastify";

import { authenticateDevice, UnauthorizedError } from "../auth/request-auth.js";
import type { FileLogger } from "../logging/file-logger.js";
import { sendNotFound, sendUnauthorized } from "./http-errors.js";

export interface DeviceRouteContext {
  prisma: PrismaClient;
  fileLogger: FileLogger;
}

export async function registerDeviceRoutes(
  app: FastifyInstance,
  context: DeviceRouteContext,
): Promise<void> {
  app.get("/api/v1/devices", async (request, reply) => {
    try {
      await authenticateDevice(request, context.prisma);
    } catch (error) {
      if (error instanceof UnauthorizedError) {
        return sendUnauthorized(reply, error.message);
      }

      throw error;
    }

    const devices = await context.prisma.device.findMany({
      orderBy: {
        createdAt: "desc",
      },
      select: {
        id: true,
        name: true,
        platform: true,
        lastSeenAt: true,
        revokedAt: true,
        createdAt: true,
      },
    });

    return reply.send({
      devices,
    });
  });

  app.delete<{ Params: { deviceId: string } }>(
    "/api/v1/devices/:deviceId",
    async (request, reply) => {
      try {
        await authenticateDevice(request, context.prisma);
      } catch (error) {
        if (error instanceof UnauthorizedError) {
          return sendUnauthorized(reply, error.message);
        }

        throw error;
      }

      const device = await context.prisma.device.findUnique({
        where: {
          id: request.params.deviceId,
        },
      });

      if (!device) {
        return sendNotFound(reply, "Device not found");
      }

      const revokedAt = new Date();
      const updated = await context.prisma.device.update({
        where: {
          id: device.id,
        },
        data: {
          revokedAt,
        },
        select: {
          id: true,
          name: true,
          platform: true,
          lastSeenAt: true,
          revokedAt: true,
          createdAt: true,
        },
      });

      await context.fileLogger.info("auth.device_revoked", {
        deviceId: device.id,
      });

      return reply.send({
        device: updated,
      });
    },
  );
}

