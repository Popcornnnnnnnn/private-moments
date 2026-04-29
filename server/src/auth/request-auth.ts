import type { Device, PrismaClient } from "@prisma/client";
import type { FastifyRequest } from "fastify";

import { hashDeviceToken } from "./device-token.js";

export class UnauthorizedError extends Error {
  constructor(message = "Unauthorized") {
    super(message);
    this.name = "UnauthorizedError";
  }
}

export async function authenticateDevice(
  request: FastifyRequest,
  prisma: PrismaClient,
): Promise<Device> {
  const authorization = request.headers.authorization;
  const token = parseBearerToken(authorization);

  if (!token) {
    throw new UnauthorizedError("Missing bearer token");
  }

  const device = await prisma.device.findFirst({
    where: {
      tokenHash: hashDeviceToken(token),
      revokedAt: null,
    },
  });

  if (!device) {
    throw new UnauthorizedError("Invalid bearer token");
  }

  await prisma.device.update({
    where: {
      id: device.id,
    },
    data: {
      lastSeenAt: new Date(),
    },
  });

  return device;
}

function parseBearerToken(authorization: string | undefined): string | null {
  if (!authorization) {
    return null;
  }

  const [scheme, token] = authorization.split(" ");
  if (scheme?.toLowerCase() !== "bearer" || !token) {
    return null;
  }

  return token;
}

