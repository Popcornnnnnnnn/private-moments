import type { PrismaClient } from "@prisma/client";
import type { FastifyInstance, FastifyReply } from "fastify";

import { generateDeviceToken, hashDeviceToken } from "../auth/device-token.js";
import { upsertLoginDevice } from "../auth/device-binding.js";
import { verifyPassword } from "../auth/password.js";
import { SCHEMA_VERSION, SERVER_VERSION } from "../config/app-config.js";
import type { FileLogger } from "../logging/file-logger.js";
import { sendBadRequest, sendConflict, sendUnauthorized } from "./http-errors.js";

const PLATFORMS = new Set(["ios", "mac", "web"]);

export interface AuthRouteContext {
  prisma: PrismaClient;
  fileLogger: FileLogger;
}

interface LoginRequestBody {
  password: string;
  deviceName: string;
  platform: string;
  deviceKey?: string;
}

export async function registerAuthRoutes(
  app: FastifyInstance,
  context: AuthRouteContext,
): Promise<void> {
  app.post("/api/v1/auth/login", async (request, reply) => {
    const body = parseLoginRequestBody(request.body, reply);
    if (!body) {
      return reply;
    }

    const user = await context.prisma.user.findFirst({
      orderBy: {
        createdAt: "asc",
      },
    });

    if (!user) {
      return sendConflict(
        reply,
        "No user exists. Set PRIVATE_MOMENTS_INITIAL_PASSWORD and restart the server.",
      );
    }

    const passwordMatches = await verifyPassword(body.password, user.passwordHash);
    if (!passwordMatches) {
      await context.fileLogger.warn("auth.login_failed", {
        deviceName: body.deviceName,
        platform: body.platform,
      });

      return sendUnauthorized(reply, "Invalid password");
    }

    const deviceToken = generateDeviceToken();
    const device = await upsertLoginDevice(context.prisma, {
      deviceKey: body.deviceKey,
      deviceName: body.deviceName,
      platform: body.platform,
      tokenHash: hashDeviceToken(deviceToken),
      userId: user.id,
    });

    await context.fileLogger.info(device.wasCreated ? "auth.device_created" : "auth.device_rebound", {
      deviceId: device.id,
      deviceName: device.name,
      platform: device.platform,
      deviceKey: body.deviceKey,
    });

    return reply.send({
      deviceId: device.id,
      deviceToken,
      serverVersion: SERVER_VERSION,
      schemaVersion: SCHEMA_VERSION,
    });
  });
}

function parseLoginRequestBody(
  body: unknown,
  reply: FastifyReply,
): LoginRequestBody | null {
  if (!isRecord(body)) {
    sendBadRequest(reply, "Request body must be an object");
    return null;
  }

  const password = getRequiredString(body, "password");
  const deviceName = getRequiredString(body, "deviceName");
  const platform = getRequiredString(body, "platform");
  const deviceKey = getOptionalString(body, "deviceKey");

  if (!password || !deviceName || !platform) {
    sendBadRequest(reply, "password, deviceName, and platform are required");
    return null;
  }

  if (!PLATFORMS.has(platform)) {
    sendBadRequest(reply, "platform must be one of: ios, mac, web");
    return null;
  }

  return {
    password,
    deviceName,
    platform,
    deviceKey,
  };
}

function getRequiredString(body: Record<string, unknown>, key: string): string | null {
  const value = body[key];
  if (typeof value !== "string") {
    return null;
  }

  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

function getOptionalString(body: Record<string, unknown>, key: string): string | undefined {
  const value = body[key];
  if (value === undefined) {
    return undefined;
  }

  if (typeof value !== "string") {
    return undefined;
  }

  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : undefined;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
