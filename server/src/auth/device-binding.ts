import type { PrismaClient } from "@prisma/client";

export interface LoginDeviceBindingInput {
  userId: string;
  deviceName: string;
  deviceKey: string | undefined;
  platform: string;
  tokenHash: string;
}

export interface LoginDeviceBindingResult {
  id: string;
  name: string;
  platform: string;
  wasCreated: boolean;
}

export async function upsertLoginDevice(
  prisma: PrismaClient,
  input: LoginDeviceBindingInput,
): Promise<LoginDeviceBindingResult> {
  const now = new Date();

  if (input.deviceKey) {
    const existingByKey = await prisma.device.findUnique({
      where: {
        userId_platform_deviceKey: {
          userId: input.userId,
          platform: input.platform,
          deviceKey: input.deviceKey,
        },
      },
      select: {
        id: true,
      },
    });

    if (existingByKey) {
      const device = await prisma.device.update({
        where: {
          id: existingByKey.id,
        },
        data: {
          name: input.deviceName,
          tokenHash: input.tokenHash,
          lastSeenAt: now,
          revokedAt: null,
        },
        select: {
          id: true,
          name: true,
          platform: true,
        },
      });

      return {
        ...device,
        wasCreated: false,
      };
    }

    const existingByName = await prisma.device.findFirst({
      where: {
        userId: input.userId,
        platform: input.platform,
        name: input.deviceName,
        deviceKey: null,
        revokedAt: null,
      },
      orderBy: [
        {
          lastSeenAt: "desc",
        },
        {
          createdAt: "desc",
        },
      ],
      select: {
        id: true,
      },
    });

    if (existingByName) {
      const device = await prisma.device.update({
        where: {
          id: existingByName.id,
        },
        data: {
          deviceKey: input.deviceKey,
          tokenHash: input.tokenHash,
          lastSeenAt: now,
          revokedAt: null,
        },
        select: {
          id: true,
          name: true,
          platform: true,
        },
      });

      return {
        ...device,
        wasCreated: false,
      };
    }
  }

  const device = await prisma.device.create({
    data: {
      userId: input.userId,
      name: input.deviceName,
      deviceKey: input.deviceKey,
      platform: input.platform,
      tokenHash: input.tokenHash,
      lastSeenAt: now,
    },
    select: {
      id: true,
      name: true,
      platform: true,
    },
  });

  return {
    ...device,
    wasCreated: true,
  };
}
