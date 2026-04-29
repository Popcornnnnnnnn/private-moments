import { createHash, randomBytes } from "node:crypto";

const TOKEN_BYTES = 32;

export function generateDeviceToken(): string {
  return randomBytes(TOKEN_BYTES).toString("base64url");
}

export function hashDeviceToken(token: string): string {
  return `sha256$${createHash("sha256").update(token).digest("hex")}`;
}

