-- Add a stable per-installation/per-physical-device key so repeated logins
-- update the same device row instead of creating duplicate devices.
ALTER TABLE "devices" ADD COLUMN "device_key" TEXT;

CREATE UNIQUE INDEX "devices_user_id_platform_device_key_key"
ON "devices"("user_id", "platform", "device_key");
