export const TOKEN_KEY = "private-moments-admin-token";
export const DEVICE_ID_KEY = "private-moments-admin-device-id";
const ADMIN_DEVICE_KEY = "private-moments-admin-device-key";

export interface LoginResponse {
  deviceId: string;
  deviceToken: string;
}

export interface Device {
  id: string;
  name: string;
  platform: string;
  lastSeenAt: string | null;
  revokedAt: string | null;
  createdAt: string;
}

export interface AdminStatus {
  serverVersion: string;
  schemaVersion: number;
  dataDir: string;
  uptimeSeconds: number;
  counts: {
    activeDevices: number;
    revokedDevices: number;
    posts: number;
    deletedPosts: number;
    media: number;
  };
  storage: {
    totalBytes: number;
    databaseBytes?: number | null;
    mediaBytes?: number | null;
    logsBytes?: number | null;
    availableBytes?: number | null;
  };
  sync?: {
    latestServerChangeVersion: number;
    pendingOperations?: number;
    rejectedOperations?: number;
    failedMediaUploads?: number;
    aiNonReady?: number;
    lastServerChangeAt?: string | null;
    lastSyncOperationAt?: string | null;
    lastSuccessfulSyncAt?: string | null;
    lastRejectedSyncAt?: string | null;
  };
}

export interface MaintenanceState {
  active: boolean;
  jobId: string | null;
  reason: string | null;
  startedAt: string | null;
}

export interface LogEntry {
  time?: string;
  level?: string;
  event?: string;
  [key: string]: unknown;
}

export interface AdminMedia {
  id: string;
  kind: string;
  status: string;
  sortOrder: number;
  originalPreserved: boolean;
  width: number | null;
  height: number | null;
  mimeType: string | null;
  durationSeconds: number | null;
  transcriptionText: string | null;
  compressedSizeBytes: number | null;
  originalSizeBytes: number | null;
  checksum: string | null;
  deletedAt: string | null;
  compressedUrl: string | null;
  originalUrl: string | null;
  thumbnailUrl: string | null;
}

export interface AdminPost {
  id: string;
  text: string;
  isFavorite: boolean;
  occurredAt: string;
  createdAt: string;
  updatedAt: string;
  deletedAt: string | null;
  clientCreatedAt: string | null;
  clientUpdatedAt: string | null;
  serverVersion: number;
  createdByDevice: Device | null;
  updatedByDevice: Device | null;
  mediaCount: number;
  totalMediaCount: number;
  media: AdminMedia[];
}

export interface PostsResponse {
  posts: AdminPost[];
  nextCursor: string | null;
  searchLimited: boolean;
}

export interface CleanPreview {
  device: Device;
  candidateCount: number;
}

export interface MaintenanceJob {
  id: string;
  type: string;
  status: string;
  stage: string | null;
  progress: number;
  metadata: Record<string, unknown>;
  artifactPath: string | null;
  errorCode: string | null;
  errorMessage: string | null;
  createdAt: string;
  startedAt: string | null;
  finishedAt: string | null;
}

export interface MaintenanceStateResponse {
  maintenance: MaintenanceState;
  runningJob: MaintenanceJob | null;
}

export interface ArchiveRepositoryState {
  configured: boolean;
  repositoryPath: string | null;
  keyFilePath: string | null;
  resticAvailable: boolean;
  resticVersion: string | null;
  initialized: boolean;
  schedule: {
    enabled: boolean;
    timeOfDay: string;
    lastRunAt: string | null;
    nextRunAt: string | null;
  };
  updatedAt: string | null;
}

export interface ArchiveSnapshot {
  id: string;
  shortId: string;
  time: string;
  hostname: string | null;
  paths: string[];
  tags: string[];
}

export type AdminTab = "overview" | "archive";
export type DeletedFilter = "active" | "deleted" | "all";

export async function apiFetch<T>(
  path: string,
  token: string | null,
  init: RequestInit = {},
): Promise<T> {
  const headers = new Headers(init.headers);
  if (init.body && !headers.has("Content-Type")) {
    headers.set("Content-Type", "application/json");
  }
  if (token) {
    headers.set("Authorization", `Bearer ${token}`);
  }
  const response = await fetch(path, {
    ...init,
    headers,
  });

  if (!response.ok) {
    const message = await readErrorMessage(response);
    throw new Error(message || `Request failed with ${response.status}`);
  }

  return (await response.json()) as T;
}

export function adminDeviceKey(): string {
  const existing = localStorage.getItem(ADMIN_DEVICE_KEY);
  if (existing) {
    return existing;
  }

  const next = crypto.randomUUID();
  localStorage.setItem(ADMIN_DEVICE_KEY, next);
  return next;
}

async function readErrorMessage(response: Response): Promise<string | null> {
  try {
    const body = (await response.json()) as { message?: unknown };
    return typeof body.message === "string" ? body.message : null;
  } catch {
    return null;
  }
}
