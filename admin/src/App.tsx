import { useEffect, useMemo, useState } from "react";
import {
  Activity,
  Archive,
  Database,
  Eye,
  HardDrive,
  Image as ImageIcon,
  LogOut,
  Mic,
  RefreshCw,
  Search,
  Server,
  ShieldCheck,
  Smartphone,
  Star,
  Timer,
  Trash2,
  Video,
  X,
} from "lucide-react";

const TOKEN_KEY = "private-moments-admin-token";
const DEVICE_ID_KEY = "private-moments-admin-device-id";
const ADMIN_DEVICE_KEY = "private-moments-admin-device-key";

interface LoginResponse {
  deviceId: string;
  deviceToken: string;
}

interface Device {
  id: string;
  name: string;
  platform: string;
  lastSeenAt: string | null;
  revokedAt: string | null;
  createdAt: string;
}

interface AdminStatus {
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

interface MaintenanceState {
  active: boolean;
  jobId: string | null;
  reason: string | null;
  startedAt: string | null;
}

interface LogEntry {
  time?: string;
  level?: string;
  event?: string;
  [key: string]: unknown;
}

interface AdminMedia {
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

interface AdminPost {
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

interface PostsResponse {
  posts: AdminPost[];
  nextCursor: string | null;
  searchLimited: boolean;
}

interface CleanPreview {
  device: Device;
  candidateCount: number;
}

interface MaintenanceJob {
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

interface MaintenanceStateResponse {
  maintenance: MaintenanceState;
  runningJob: MaintenanceJob | null;
}

interface ArchiveRepositoryState {
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

interface ArchiveSnapshot {
  id: string;
  shortId: string;
  time: string;
  hostname: string | null;
  paths: string[];
  tags: string[];
}

type AdminTab = "overview" | "archive";
type DeletedFilter = "active" | "deleted" | "all";

export function App() {
  const [token, setToken] = useState(() => sessionStorage.getItem(TOKEN_KEY));
  const [deviceId, setDeviceId] = useState(() => sessionStorage.getItem(DEVICE_ID_KEY));

  function handleLogin(response: LoginResponse) {
    sessionStorage.setItem(TOKEN_KEY, response.deviceToken);
    sessionStorage.setItem(DEVICE_ID_KEY, response.deviceId);
    setToken(response.deviceToken);
    setDeviceId(response.deviceId);
  }

  function handleLogout() {
    sessionStorage.removeItem(TOKEN_KEY);
    sessionStorage.removeItem(DEVICE_ID_KEY);
    setToken(null);
    setDeviceId(null);
  }

  if (!token) {
    return <LoginScreen onLogin={handleLogin} />;
  }

  return <Dashboard currentDeviceId={deviceId} token={token} onLogout={handleLogout} />;
}

function LoginScreen({ onLogin }: { onLogin: (response: LoginResponse) => void }) {
  const [password, setPassword] = useState("");
  const [deviceName, setDeviceName] = useState("Mac Admin Browser");
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  async function submit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setSubmitting(true);
    setError(null);

    try {
      const response = await apiFetch<LoginResponse>("/api/v1/auth/login", null, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          password,
          deviceName,
          deviceKey: adminDeviceKey(),
          platform: "web",
        }),
      });

      onLogin(response);
    } catch (error) {
      setError(error instanceof Error ? error.message : "Login failed");
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <main className="login-shell">
      <form className="login-panel" onSubmit={submit}>
        <div>
          <p className="eyebrow">Private Moments</p>
          <h1>Mac Admin</h1>
        </div>
        <label>
          <span>Password</span>
          <input
            autoComplete="current-password"
            onChange={(event) => setPassword(event.target.value)}
            type="password"
            value={password}
          />
        </label>
        <label>
          <span>Device name</span>
          <input
            autoComplete="off"
            onChange={(event) => setDeviceName(event.target.value)}
            type="text"
            value={deviceName}
          />
        </label>
        {error ? <p className="error-text">{error}</p> : null}
        <button className="primary-button" disabled={submitting} type="submit">
          <ShieldCheck size={18} />
          {submitting ? "Signing in" : "Sign in"}
        </button>
      </form>
    </main>
  );
}

function Dashboard({
  currentDeviceId,
  token,
  onLogout,
}: {
  currentDeviceId: string | null;
  token: string;
  onLogout: () => void;
}) {
  const [activeTab, setActiveTab] = useState<AdminTab>("archive");
  const [status, setStatus] = useState<AdminStatus | null>(null);
  const [devices, setDevices] = useState<Device[]>([]);
  const [logs, setLogs] = useState<LogEntry[]>([]);
  const [maintenanceState, setMaintenanceState] = useState<MaintenanceStateResponse | null>(null);
  const [maintenanceJobs, setMaintenanceJobs] = useState<MaintenanceJob[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [cleanPreview, setCleanPreview] = useState<CleanPreview | null>(null);
  const [cleanConfirmation, setCleanConfirmation] = useState("");
  const [cleanSubmitting, setCleanSubmitting] = useState(false);

  async function load() {
    setLoading(true);
    setError(null);

    try {
      const [statusResponse, devicesResponse, logsResponse, maintenanceResponse, jobsResponse] = await Promise.all([
        apiFetch<AdminStatus>("/api/v1/admin/status", token),
        apiFetch<{ devices: Device[] }>("/api/v1/devices", token),
        apiFetch<{ logs: LogEntry[] }>("/api/v1/admin/logs?limit=20", token),
        apiFetch<MaintenanceStateResponse>("/api/v1/admin/maintenance/state", token),
        apiFetch<{ jobs: MaintenanceJob[] }>("/api/v1/admin/maintenance/jobs?limit=5", token),
      ]);

      setStatus(statusResponse);
      setDevices(devicesResponse.devices);
      setLogs(logsResponse.logs);
      setMaintenanceState(maintenanceResponse);
      setMaintenanceJobs(jobsResponse.jobs);
    } catch (error) {
      setError(error instanceof Error ? error.message : "Failed to load dashboard");
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    void load();
  }, []);

  async function revokeDevice(id: string) {
    await apiFetch(`/api/v1/devices/${id}`, token, {
      method: "DELETE",
    });
    await load();
  }

  async function openCleanDevice(deviceId: string) {
    setError(null);
    setNotice(null);

    try {
      const preview = await apiFetch<CleanPreview>(
        `/api/v1/admin/devices/${deviceId}/clean-posts/preview`,
        token,
      );
      setCleanPreview(preview);
      setCleanConfirmation("");
    } catch (error) {
      setError(error instanceof Error ? error.message : "Failed to load clean preview");
    }
  }

  async function confirmCleanDevice() {
    if (!cleanPreview || cleanConfirmation !== cleanPreview.device.name) {
      return;
    }

    setCleanSubmitting(true);
    setError(null);
    setNotice(null);

    try {
      const result = await apiFetch<{ deletedPosts: number; deletedMediaFiles: number }>(
        `/api/v1/admin/devices/${cleanPreview.device.id}/clean-posts`,
        token,
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            confirmDeviceName: cleanConfirmation,
          }),
        },
      );

      setNotice(
        `Cleaned ${result.deletedPosts} posts and ${result.deletedMediaFiles} media files from ${cleanPreview.device.name}.`,
      );
      setCleanPreview(null);
      setCleanConfirmation("");
      await load();
    } catch (error) {
      setError(error instanceof Error ? error.message : "Failed to clean device posts");
    } finally {
      setCleanSubmitting(false);
    }
  }

  const activeDevices = useMemo(
    () => devices.filter((device) => !device.revokedAt),
    [devices],
  );

  return (
    <main className="dashboard-shell">
      <header className="topbar">
        <div>
          <p className="eyebrow">Private Moments</p>
          <h1>Mac Admin</h1>
        </div>
        <div className="topbar-actions">
          <button className="icon-button" onClick={() => void load()} type="button">
            <RefreshCw size={18} />
            Refresh
          </button>
          <button className="icon-button subtle" onClick={onLogout} type="button">
            <LogOut size={18} />
            Sign out
          </button>
        </div>
      </header>

      <nav className="tabbar" aria-label="Admin sections">
        <button
          className={activeTab === "archive" ? "tab-button active" : "tab-button"}
          onClick={() => setActiveTab("archive")}
          type="button"
        >
          Archive
        </button>
        <button
          className={activeTab === "overview" ? "tab-button active" : "tab-button"}
          onClick={() => setActiveTab("overview")}
          type="button"
        >
          Overview
        </button>
      </nav>

      {error ? <div className="banner error">{error}</div> : null}
      {notice ? <div className="banner success">{notice}</div> : null}
      {loading ? <div className="banner">Loading</div> : null}

      {activeTab === "overview" ? (
        <Overview
          activeDevices={activeDevices}
          currentDeviceId={currentDeviceId}
          devices={devices}
          logs={logs}
          maintenanceJobs={maintenanceJobs}
          maintenanceState={maintenanceState}
          onCleanDevice={openCleanDevice}
          onRevokeDevice={revokeDevice}
          status={status}
        />
      ) : (
        <ArchiveManager token={token} />
      )}

      {cleanPreview ? (
        <CleanDeviceDialog
          confirmation={cleanConfirmation}
          onCancel={() => {
            setCleanPreview(null);
            setCleanConfirmation("");
          }}
          onChangeConfirmation={setCleanConfirmation}
          onConfirm={() => void confirmCleanDevice()}
          preview={cleanPreview}
          submitting={cleanSubmitting}
        />
      ) : null}
    </main>
  );
}

function Overview({
  activeDevices,
  currentDeviceId,
  devices,
  logs,
  maintenanceJobs,
  maintenanceState,
  onCleanDevice,
  onRevokeDevice,
  status,
}: {
  activeDevices: Device[];
  currentDeviceId: string | null;
  devices: Device[];
  logs: LogEntry[];
  maintenanceJobs: MaintenanceJob[];
  maintenanceState: MaintenanceStateResponse | null;
  onCleanDevice: (deviceId: string) => void;
  onRevokeDevice: (deviceId: string) => void;
  status: AdminStatus | null;
}) {
  const runningJob = maintenanceState?.runningJob ?? maintenanceJobs.find((job) => job.status === "running");
  const latestFailedJob = maintenanceJobs.find((job) => job.status === "failed");

  return (
    <>
      <section className="metric-grid">
        <Metric
          icon={<Server size={20} />}
          label="Server"
          value={status ? `v${status.serverVersion}` : "-"}
          detail={status ? `schema ${status.schemaVersion}` : ""}
        />
        <Metric
          icon={<Activity size={20} />}
          label="Maintenance"
          value={maintenanceState?.maintenance.active ? "Active" : "Idle"}
          detail={runningJob ? `${runningJob.type} · ${runningJob.progress}%` : "no running job"}
        />
        <Metric
          icon={<HardDrive size={20} />}
          label="Storage"
          value={status ? formatBytes(status.storage.totalBytes) : "-"}
          detail={
            status?.storage.availableBytes !== undefined && status.storage.availableBytes !== null
              ? `${formatBytes(status.storage.availableBytes)} available`
              : "runtime data"
          }
        />
        <Metric
          icon={<Smartphone size={20} />}
          label="Devices"
          value={String(status?.counts.activeDevices ?? activeDevices.length)}
          detail={`${status?.counts.revokedDevices ?? 0} revoked`}
        />
      </section>

      <section className="layout-grid">
        <section className="panel wide">
          <div className="panel-heading">
            <h2>Service</h2>
            <Activity size={18} />
          </div>
          <dl className="details-list">
            <div>
              <dt>Data directory</dt>
              <dd>{status?.dataDir ?? "-"}</dd>
            </div>
            <div>
              <dt>Uptime</dt>
              <dd>{status ? formatDuration(status.uptimeSeconds) : "-"}</dd>
            </div>
            <div>
              <dt>Storage</dt>
              <dd>{status ? formatBytes(status.storage.totalBytes) : "-"}</dd>
            </div>
            <div>
              <dt>Available disk</dt>
              <dd>
                {status?.storage.availableBytes !== undefined && status.storage.availableBytes !== null
                  ? formatBytes(status.storage.availableBytes)
                  : "-"}
              </dd>
            </div>
          </dl>
        </section>

        <section className="panel wide">
          <div className="panel-heading">
            <h2>Jobs</h2>
            <Activity size={18} />
          </div>
          <dl className="details-list compact">
            <div>
              <dt>Maintenance mode</dt>
              <dd>{maintenanceState?.maintenance.active ? "Active" : "Idle"}</dd>
            </div>
            <div>
              <dt>Running job</dt>
              <dd>{runningJob ? jobSummary(runningJob) : "None"}</dd>
            </div>
            <div>
              <dt>Recent failed job</dt>
              <dd>{latestFailedJob ? jobSummary(latestFailedJob) : "None"}</dd>
            </div>
            <div>
              <dt>Recent jobs</dt>
              <dd>{maintenanceJobs.length}</dd>
            </div>
          </dl>
        </section>

        <section className="panel">
          <div className="panel-heading">
            <h2>Devices</h2>
            <Smartphone size={18} />
          </div>
          <div className="device-list">
            {devices.map((device) => (
              <div className="device-row" key={device.id}>
                <div>
                  <strong>{device.name}</strong>
                  <span>
                    {device.platform} · {formatDate(device.lastSeenAt ?? device.createdAt)}
                  </span>
                  <span className="mono">{shortId(device.id)}</span>
                </div>
                <div className="row-actions">
                  <button
                    className="icon-button danger-outline"
                    onClick={() => onCleanDevice(device.id)}
                    title="Permanently clean posts created by this device"
                    type="button"
                  >
                    <Trash2 size={15} />
                    Clean posts
                  </button>
                  {device.revokedAt ? (
                    <span className="status-pill muted">Revoked</span>
                  ) : (
                    <button
                      className="danger-button"
                      disabled={device.id === currentDeviceId}
                      onClick={() => onRevokeDevice(device.id)}
                      title={device.id === currentDeviceId ? "Current device" : "Revoke device"}
                      type="button"
                    >
                      <Trash2 size={16} />
                    </button>
                  )}
                </div>
              </div>
            ))}
          </div>
        </section>

        <section className="panel">
          <div className="panel-heading">
            <h2>Recent Logs</h2>
            <Activity size={18} />
          </div>
          <div className="log-list">
            {logs.map((log, index) => (
              <div className="log-row" key={`${log.time ?? "log"}-${index}`}>
                <span className={`level ${String(log.level ?? "info")}`}>
                  {String(log.level ?? "info")}
                </span>
                <div>
                  <strong>{String(log.event ?? "log")}</strong>
                  <span>{formatDate(log.time)}</span>
                </div>
              </div>
            ))}
          </div>
        </section>
      </section>
    </>
  );
}

function PostsManager({
  devices,
  onChanged,
  reloadSignal,
  token,
}: {
  devices: Device[];
  onChanged: () => void;
  reloadSignal: number;
  token: string;
}) {
  const [posts, setPosts] = useState<AdminPost[]>([]);
  const [selectedPost, setSelectedPost] = useState<AdminPost | null>(null);
  const [deletedFilter, setDeletedFilter] = useState<DeletedFilter>("active");
  const [deviceId, setDeviceId] = useState("");
  const [searchText, setSearchText] = useState("");
  const [appliedSearch, setAppliedSearch] = useState("");
  const [nextCursor, setNextCursor] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [lightboxMedia, setLightboxMedia] = useState<AdminMedia | null>(null);

  async function loadPosts(reset: boolean) {
    setLoading(true);
    setError(null);

    try {
      const params = new URLSearchParams({
        deleted: deletedFilter,
        limit: appliedSearch ? "100" : "50",
      });

      if (deviceId) {
        params.set("deviceId", deviceId);
      }

      if (appliedSearch) {
        params.set("q", appliedSearch);
      } else if (!reset && nextCursor) {
        params.set("cursor", nextCursor);
      }

      const response = await apiFetch<PostsResponse>(`/api/v1/admin/posts?${params}`, token);
      setPosts((current) => (reset ? response.posts : [...current, ...response.posts]));
      setNextCursor(response.nextCursor);

      if (reset) {
        setSelectedPost(null);
      }
    } catch (error) {
      setError(error instanceof Error ? error.message : "Failed to load posts");
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    void loadPosts(true);
  }, [deletedFilter, deviceId, appliedSearch, reloadSignal]);

  async function selectPost(postId: string) {
    setError(null);

    try {
      const response = await apiFetch<{ post: AdminPost }>(
        `/api/v1/admin/posts/${postId}`,
        token,
      );
      setSelectedPost(response.post);
    } catch (error) {
      setError(error instanceof Error ? error.message : "Failed to load post");
    }
  }

  async function softDeleteSelectedPost() {
    if (!selectedPost) {
      return;
    }

    const confirmed = window.confirm("Soft delete this post and sync the deletion to iPhone?");
    if (!confirmed) {
      return;
    }

    setError(null);

    try {
      const response = await apiFetch<{ post: AdminPost | null }>(
        `/api/v1/admin/posts/${selectedPost.id}`,
        token,
        {
          method: "DELETE",
        },
      );
      setSelectedPost(response.post);
      await loadPosts(true);
      onChanged();
    } catch (error) {
      setError(error instanceof Error ? error.message : "Failed to delete post");
    }
  }

  function submitSearch(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setAppliedSearch(searchText.trim());
  }

  function clearSearch() {
    setSearchText("");
    setAppliedSearch("");
  }

  return (
    <section className="posts-manager">
      <div className="panel posts-toolbar">
        <form className="filter-bar" onSubmit={submitSearch}>
          <label>
            <span>Device</span>
            <select onChange={(event) => setDeviceId(event.target.value)} value={deviceId}>
              <option value="">All devices</option>
              {devices.map((device) => (
                <option key={device.id} value={device.id}>
                  {deviceOptionLabel(device)}
                </option>
              ))}
            </select>
          </label>
          <label>
            <span>Deleted</span>
            <select
              onChange={(event) => setDeletedFilter(event.target.value as DeletedFilter)}
              value={deletedFilter}
            >
              <option value="active">Active</option>
              <option value="deleted">Soft deleted</option>
              <option value="all">All</option>
            </select>
          </label>
          <label className="search-label">
            <span>Search</span>
            <div className="search-box">
              <input
                onChange={(event) => setSearchText(event.target.value)}
                placeholder="Search text"
                type="search"
                value={searchText}
              />
              {appliedSearch ? (
                <button className="inline-icon-button" onClick={clearSearch} type="button">
                  <X size={16} />
                </button>
              ) : null}
            </div>
          </label>
          <button className="primary-button" type="submit">
            <Search size={17} />
            Search
          </button>
        </form>
      </div>

      {error ? <div className="banner error">{error}</div> : null}

      <div className="posts-layout">
        <section className="panel posts-list-panel">
          <div className="panel-heading">
            <h2>Posts</h2>
            <span className="status-pill">{posts.length}</span>
          </div>
          <div className="post-list">
            {posts.map((post) => (
              <button
                className={selectedPost?.id === post.id ? "post-row active" : "post-row"}
                key={post.id}
                onClick={() => void selectPost(post.id)}
                type="button"
              >
                <div>
                  <strong>{post.text.trim() || "Image-only moment"}</strong>
                  <span>
                    {formatDate(post.occurredAt)} · {mediaSummary(post.media)}
                  </span>
                  <span>
                    {post.createdByDevice?.name ?? "Unknown device"} · v{post.serverVersion}
                  </span>
                </div>
                <div className="post-row-status">
                  {post.isFavorite ? <Star className="favorite-icon" fill="currentColor" size={15} /> : null}
                  <span className={post.deletedAt ? "status-pill danger" : "status-pill"}>
                    {post.deletedAt ? "deleted" : "active"}
                  </span>
                </div>
              </button>
            ))}
          </div>
          {!appliedSearch && nextCursor ? (
            <button
              className="icon-button load-more-button"
              disabled={loading}
              onClick={() => void loadPosts(false)}
              type="button"
            >
              <RefreshCw size={17} />
              {loading ? "Loading" : "Load more"}
            </button>
          ) : null}
          {loading && !posts.length ? <div className="empty-state">Loading posts</div> : null}
          {!loading && !posts.length ? <div className="empty-state">No posts found</div> : null}
        </section>

        <PostDetailDrawer
          onDelete={() => void softDeleteSelectedPost()}
          onOpenImage={setLightboxMedia}
          post={selectedPost}
          token={token}
        />
      </div>

      {lightboxMedia ? (
        <ImageLightbox
          media={lightboxMedia}
          onClose={() => setLightboxMedia(null)}
          token={token}
        />
      ) : null}
    </section>
  );
}

function ArchiveManager({ token }: { token: string }) {
  const [repository, setRepository] = useState<ArchiveRepositoryState | null>(null);
  const [repositoryPath, setRepositoryPath] = useState("");
  const [snapshots, setSnapshots] = useState<ArchiveSnapshot[]>([]);
  const [jobs, setJobs] = useState<MaintenanceJob[]>([]);
  const [scheduleEnabled, setScheduleEnabled] = useState(false);
  const [scheduleTime, setScheduleTime] = useState("03:30");
  const [restoreSnapshotId, setRestoreSnapshotId] = useState("");
  const [restoreName, setRestoreName] = useState("");
  const [promotePath, setPromotePath] = useState("");
  const [promoteConfirmation, setPromoteConfirmation] = useState("");
  const [exportFrom, setExportFrom] = useState("");
  const [exportTo, setExportTo] = useState("");
  const [importPackagePath, setImportPackagePath] = useState("");
  const [importName, setImportName] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [submitting, setSubmitting] = useState<string | null>(null);

  async function loadArchive() {
    setLoading(true);
    setError(null);

    try {
      const [repositoryResponse, snapshotsResponse, jobsResponse] = await Promise.all([
        apiFetch<{ repository: ArchiveRepositoryState }>("/api/v1/admin/archive/repository", token),
        apiFetch<{ snapshots: ArchiveSnapshot[] }>("/api/v1/admin/archive/snapshots", token).catch(() => ({
          snapshots: [],
        })),
        apiFetch<{ jobs: MaintenanceJob[] }>("/api/v1/admin/maintenance/jobs?limit=12", token),
      ]);

      setRepository(repositoryResponse.repository);
      setRepositoryPath(repositoryResponse.repository.repositoryPath ?? "");
      setScheduleEnabled(repositoryResponse.repository.schedule.enabled);
      setScheduleTime(repositoryResponse.repository.schedule.timeOfDay);
      setSnapshots(snapshotsResponse.snapshots);
      setJobs(jobsResponse.jobs);
    } catch (error) {
      setError(error instanceof Error ? error.message : "Failed to load archive state");
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    void loadArchive();
  }, []);

  async function runAction(name: string, action: () => Promise<string>) {
    setSubmitting(name);
    setError(null);
    setNotice(null);

    try {
      const message = await action();
      setNotice(message);
      await loadArchive();
    } catch (error) {
      setError(error instanceof Error ? error.message : "Archive action failed");
    } finally {
      setSubmitting(null);
    }
  }

  async function saveRepository() {
    await runAction("repository", async () => {
      const response = await apiFetch<{ repository: ArchiveRepositoryState }>(
        "/api/v1/admin/archive/repository",
        token,
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            repositoryPath,
          }),
        },
      );
      setRepository(response.repository);
      return "Backup repository path saved.";
    });
  }

  async function initializeRepository() {
    await runAction("init", async () => {
      await apiFetch("/api/v1/admin/archive/repository/init", token, {
        method: "POST",
      });
      return "Backup repository initialized.";
    });
  }

  async function saveSchedule() {
    await runAction("schedule", async () => {
      await apiFetch("/api/v1/admin/archive/schedule", token, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          enabled: scheduleEnabled,
          timeOfDay: scheduleTime,
        }),
      });
      return "Backup schedule updated.";
    });
  }

  async function startJob(kind: "backup" | "check") {
    await runAction(kind, async () => {
      await apiFetch(`/api/v1/admin/archive/jobs/${kind}`, token, {
        method: "POST",
      });
      return kind === "backup" ? "Backup job started." : "Repository check started.";
    });
  }

  async function startRestore(snapshotId: string) {
    await runAction("restore", async () => {
      await apiFetch("/api/v1/admin/archive/jobs/restore", token, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          snapshotId,
          restoreName,
        }),
      });
      setRestoreSnapshotId(snapshotId);
      return "Restore job started. Watch recent jobs for the verified restore path.";
    });
  }

  async function startPromote() {
    await runAction("promote", async () => {
      await apiFetch("/api/v1/admin/archive/jobs/promote", token, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          restoredDataDir: promotePath,
          confirmation: promoteConfirmation,
        }),
      });
      return "Promote preparation started. It will write restart instructions after verification and pre-promote backup.";
    });
  }

  async function startExport() {
    await runAction("export", async () => {
      await apiFetch("/api/v1/admin/archive/jobs/export", token, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          from: exportFrom ? startOfLocalDay(exportFrom).toISOString() : undefined,
          to: exportTo ? nextLocalDay(exportTo).toISOString() : undefined,
        }),
      });
      return "Export job started. The package path will appear in Recent Jobs.";
    });
  }

  async function startImport() {
    await runAction("import", async () => {
      await apiFetch("/api/v1/admin/archive/jobs/import", token, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          packagePath: importPackagePath,
          importName,
        }),
      });
      return "Import job started. It will create a new staged data directory and leave the current archive untouched.";
    });
  }

  const runningJob = jobs.find((job) => job.status === "running");

  return (
    <section className="archive-manager">
      {error ? <div className="banner error">{error}</div> : null}
      {notice ? <div className="banner success">{notice}</div> : null}
      {loading ? <div className="banner">Loading archive state</div> : null}

      <section className="metric-grid">
        <Metric
          icon={<Archive size={20} />}
          label="Repository"
          value={repository?.configured ? "Configured" : "Not set"}
          detail={repository?.initialized ? "initialized" : "not initialized"}
        />
        <Metric
          icon={<HardDrive size={20} />}
          label="restic"
          value={repository?.resticAvailable ? "Available" : "Missing"}
          detail={repository?.resticVersion ?? "brew install restic"}
        />
        <Metric
          icon={<Timer size={20} />}
          label="Schedule"
          value={repository?.schedule.enabled ? repository.schedule.timeOfDay : "Off"}
          detail={repository?.schedule.nextRunAt ? `next ${formatDate(repository.schedule.nextRunAt)}` : "manual only"}
        />
        <Metric
          icon={<Activity size={20} />}
          label="Running job"
          value={runningJob ? runningJob.type : "None"}
          detail={runningJob ? `${runningJob.progress}% · ${runningJob.stage ?? "running"}` : `${jobs.length} recent jobs`}
        />
      </section>

      <section className="layout-grid archive-grid">
        <section className="panel wide">
          <div className="panel-heading">
            <h2>Backup Repository</h2>
            <Archive size={18} />
          </div>
          <p className="muted-text">
            Repository plus key file can restore your archive. This is a recovery tool for your own
            Mac, not a separate encrypted vault if someone has both files.
          </p>
          <div className="form-grid">
            <label>
              <span>Repository path</span>
              <input
                onChange={(event) => setRepositoryPath(event.target.value)}
                placeholder="/Users/you/Library/Mobile Documents/com~apple~CloudDocs/PrivateMomentsBackup"
                value={repositoryPath}
              />
            </label>
            <button
              className="primary-button"
              disabled={submitting !== null || !repositoryPath.trim()}
              onClick={() => void saveRepository()}
              type="button"
            >
              Save path
            </button>
          </div>
          <dl className="details-list compact">
            <div>
              <dt>Key file</dt>
              <dd>{repository?.keyFilePath ?? "-"}</dd>
            </div>
            <div>
              <dt>Updated</dt>
              <dd>{formatDate(repository?.updatedAt)}</dd>
            </div>
          </dl>
          <div className="toolbar-row">
            <button
              className="icon-button"
              disabled={submitting !== null || !repository?.configured}
              onClick={() => void initializeRepository()}
              type="button"
            >
              <Database size={17} />
              Initialize
            </button>
            <button
              className="primary-button"
              disabled={submitting !== null || !repository?.configured}
              onClick={() => void startJob("backup")}
              type="button"
            >
              <Archive size={17} />
              Backup now
            </button>
            <button
              className="icon-button"
              disabled={submitting !== null || !repository?.initialized}
              onClick={() => void startJob("check")}
              type="button"
            >
              <ShieldCheck size={17} />
              Check repository
            </button>
            <button className="icon-button" onClick={() => void loadArchive()} type="button">
              <RefreshCw size={17} />
              Refresh
            </button>
          </div>
        </section>

        <section className="panel">
          <div className="panel-heading">
            <h2>Daily Backup</h2>
            <Timer size={18} />
          </div>
          <div className="form-grid compact-form">
            <label className="checkbox-label">
              <input
                checked={scheduleEnabled}
                onChange={(event) => setScheduleEnabled(event.target.checked)}
                type="checkbox"
              />
              <span>Enable daily backup</span>
            </label>
            <label>
              <span>Time</span>
              <input
                onChange={(event) => setScheduleTime(event.target.value)}
                type="time"
                value={scheduleTime}
              />
            </label>
            <button
              className="primary-button"
              disabled={submitting !== null}
              onClick={() => void saveSchedule()}
              type="button"
            >
              Save schedule
            </button>
          </div>
          <dl className="details-list compact">
            <div>
              <dt>Last run</dt>
              <dd>{formatDate(repository?.schedule.lastRunAt)}</dd>
            </div>
            <div>
              <dt>Next run</dt>
              <dd>{formatDate(repository?.schedule.nextRunAt)}</dd>
            </div>
          </dl>
        </section>

        <section className="panel">
          <div className="panel-heading">
            <h2>Promote Restore</h2>
            <ShieldCheck size={18} />
          </div>
          <p className="muted-text">
            Restore first, then paste the verified restore path here. Promotion creates a
            pre-promote backup and writes restart instructions instead of replacing the live SQLite
            database in-process.
          </p>
          <div className="form-grid compact-form">
            <label>
              <span>Restored data directory</span>
              <input
                onChange={(event) => setPromotePath(event.target.value)}
                placeholder="/path/from/restore/job"
                value={promotePath}
              />
            </label>
            <label>
              <span>Confirmation</span>
              <input
                onChange={(event) => setPromoteConfirmation(event.target.value)}
                placeholder={promotePath ? `PROMOTE ${lastPathSegment(promotePath)}` : "PROMOTE <folder>"}
                value={promoteConfirmation}
              />
            </label>
            <button
              className="primary-button destructive"
              disabled={submitting !== null || !promotePath.trim() || !promoteConfirmation.trim()}
              onClick={() => void startPromote()}
              type="button"
            >
              Prepare promote
            </button>
          </div>
        </section>

        <section className="panel wide">
          <div className="panel-heading">
            <h2>Snapshots</h2>
            <span className="status-pill">{snapshots.length}</span>
          </div>
          <div className="snapshot-list">
            {snapshots.map((snapshot) => (
              <div className="snapshot-row" key={snapshot.id}>
                <div>
                  <strong>{snapshot.shortId}</strong>
                  <span>{formatDate(snapshot.time)}</span>
                  <span>{snapshot.tags.length ? snapshot.tags.join(", ") : "private-moments"}</span>
                </div>
                <button
                  className="icon-button"
                  disabled={submitting !== null}
                  onClick={() => void startRestore(snapshot.id)}
                  type="button"
                >
                  Restore
                </button>
              </div>
            ))}
            {!snapshots.length ? <div className="empty-state">No snapshots yet</div> : null}
          </div>
          <label className="restore-name-label">
            <span>Restore label</span>
            <input
              onChange={(event) => setRestoreName(event.target.value)}
              placeholder="optional label"
              value={restoreName}
            />
          </label>
          {restoreSnapshotId ? (
            <p className="muted-text">Last selected snapshot: {restoreSnapshotId.slice(0, 12)}</p>
          ) : null}
        </section>

        <section className="panel wide">
          <div className="panel-heading">
            <h2>Exports</h2>
            <Archive size={18} />
          </div>
          <p className="muted-text">
            Export is migration-first: JSON is the source of truth, media files are included, and
            Markdown is only a preview. Import always stages into a new data directory.
          </p>
          <div className="form-grid export-form">
            <label>
              <span>From</span>
              <input
                onChange={(event) => setExportFrom(event.target.value)}
                type="date"
                value={exportFrom}
              />
            </label>
            <label>
              <span>To</span>
              <input
                onChange={(event) => setExportTo(event.target.value)}
                type="date"
                value={exportTo}
              />
            </label>
            <button
              className="primary-button"
              disabled={submitting !== null}
              onClick={() => void startExport()}
              type="button"
            >
              Create export
            </button>
          </div>
          <div className="form-grid import-form">
            <label>
              <span>Package path</span>
              <input
                onChange={(event) => setImportPackagePath(event.target.value)}
                placeholder="/path/to/private-moments-export.tar.gz"
                value={importPackagePath}
              />
            </label>
            <label>
              <span>Import label</span>
              <input
                onChange={(event) => setImportName(event.target.value)}
                placeholder="optional label"
                value={importName}
              />
            </label>
            <button
              className="icon-button"
              disabled={submitting !== null || !importPackagePath.trim()}
              onClick={() => void startImport()}
              type="button"
            >
              Import package
            </button>
          </div>
        </section>

        <section className="panel wide">
          <div className="panel-heading">
            <h2>Recent Jobs</h2>
            <Activity size={18} />
          </div>
          <div className="job-list">
            {jobs.map((job) => (
              <div className="job-row" key={job.id}>
                <div>
                  <strong>{job.type}</strong>
                  <span>
                    {formatDate(job.createdAt)} · {job.stage ?? "queued"} · {job.progress}%
                  </span>
                  {job.artifactPath ? <span className="mono">{job.artifactPath}</span> : null}
                  {job.errorMessage ? <span className="danger-text">{job.errorMessage}</span> : null}
                </div>
                <span className={job.status === "failed" ? "status-pill danger" : "status-pill"}>
                  {job.status}
                </span>
              </div>
            ))}
            {!jobs.length ? <div className="empty-state">No maintenance jobs yet</div> : null}
          </div>
        </section>
      </section>
    </section>
  );
}

function PostDetailDrawer({
  onDelete,
  onOpenImage,
  post,
  token,
}: {
  onDelete: () => void;
  onOpenImage: (media: AdminMedia) => void;
  post: AdminPost | null;
  token: string;
}) {
  if (!post) {
    return (
      <aside className="panel post-detail empty-detail">
        <Eye size={22} />
        <p>Select a post to inspect its content, media, devices, and sync metadata.</p>
      </aside>
    );
  }

  const visibleMedia = post.media.filter(
    (media) =>
      !media.deletedAt &&
      (media.kind === "image" || media.kind === "video") &&
      (media.thumbnailUrl || media.compressedUrl),
  );

  return (
    <aside className="panel post-detail">
      <div className="panel-heading">
        <h2>Post Detail</h2>
        <div className="post-row-status">
          {post.isFavorite ? <Star className="favorite-icon" fill="currentColor" size={15} /> : null}
          <span className={post.deletedAt ? "status-pill danger" : "status-pill"}>
            {post.deletedAt ? "deleted" : "active"}
          </span>
        </div>
      </div>

      <div className="post-body-text">{post.text.trim() || "Image-only moment"}</div>

      {visibleMedia.length ? (
        <div className="admin-media-grid">
          {visibleMedia.map((media) => (
            <button
              className="admin-media-thumb"
              disabled={media.kind !== "image"}
              key={media.id}
              onClick={() => onOpenImage(media)}
              type="button"
            >
              <AuthenticatedImage
                alt={`${media.kind} media`}
                className="admin-media-image"
                src={media.thumbnailUrl ?? media.compressedUrl}
                token={token}
              />
              {media.kind === "video" ? (
                <span className="admin-media-badge">
                  <Video size={14} />
                  {formatDuration(media.durationSeconds)}
                </span>
              ) : null}
            </button>
          ))}
        </div>
      ) : null}

      {post.media.some((media) => media.transcriptionText) ? (
        <div className="transcript-list">
          {post.media
            .filter((media) => media.transcriptionText)
            .map((media) => (
              <div className="transcript-block" key={`${media.id}-transcript`}>
                <span>{media.kind} transcript</span>
                <p>{media.transcriptionText}</p>
              </div>
            ))}
        </div>
      ) : null}

      <dl className="details-list compact">
        <div>
          <dt>Occurred</dt>
          <dd>{formatDate(post.occurredAt)}</dd>
        </div>
        <div>
          <dt>Created</dt>
          <dd>{formatDate(post.createdAt)}</dd>
        </div>
        <div>
          <dt>Updated</dt>
          <dd>{formatDate(post.updatedAt)}</dd>
        </div>
        <div>
          <dt>Deleted</dt>
          <dd>{formatDate(post.deletedAt)}</dd>
        </div>
        <div>
          <dt>Created by</dt>
          <dd>{deviceLabel(post.createdByDevice)}</dd>
        </div>
        <div>
          <dt>Updated by</dt>
          <dd>{deviceLabel(post.updatedByDevice)}</dd>
        </div>
        <div>
          <dt>Server version</dt>
          <dd>{post.serverVersion}</dd>
        </div>
        <div>
          <dt>Post id</dt>
          <dd className="mono">{post.id}</dd>
        </div>
      </dl>

      <section className="media-meta">
        <h3>Media</h3>
        {post.media.length ? (
          post.media.map((media) => (
            <div className="media-meta-row" key={media.id}>
              <div>
                <strong>
                  {media.kind} · #{media.sortOrder}
                </strong>
                <span>
                  {media.status}
                  {media.deletedAt ? ` · deleted ${formatDate(media.deletedAt)}` : ""}
                </span>
                <span>
                  {formatBytes(media.compressedSizeBytes ?? 0)}
                  {media.mimeType ? ` · ${media.mimeType}` : ""}
                  {media.durationSeconds ? ` · ${formatDuration(media.durationSeconds)}` : ""}
                  {media.checksum ? ` · ${media.checksum.slice(0, 12)}` : ""}
                </span>
              </div>
              {mediaIcon(media.kind)}
            </div>
          ))
        ) : (
          <p className="muted-text">No media</p>
        )}
      </section>

      {!post.deletedAt ? (
        <button className="primary-button destructive-wide" onClick={onDelete} type="button">
          <Trash2 size={17} />
          Soft delete post
        </button>
      ) : null}
    </aside>
  );
}

function CleanDeviceDialog({
  confirmation,
  onCancel,
  onChangeConfirmation,
  onConfirm,
  preview,
  submitting,
}: {
  confirmation: string;
  onCancel: () => void;
  onChangeConfirmation: (value: string) => void;
  onConfirm: () => void;
  preview: CleanPreview;
  submitting: boolean;
}) {
  const canConfirm = confirmation === preview.device.name && !submitting;

  return (
    <div className="modal-backdrop" role="presentation">
      <section aria-modal="true" className="modal-panel" role="dialog">
        <div>
          <p className="eyebrow danger-text">Danger zone</p>
          <h2>Clean posts from device</h2>
        </div>
        <p>
          This will permanently delete {preview.candidateCount} posts created by{" "}
          <strong>{preview.device.name}</strong>. iPhone devices will receive deletion events on
          next sync.
        </p>
        <label>
          <span>Type device name to confirm</span>
          <input
            autoComplete="off"
            onChange={(event) => onChangeConfirmation(event.target.value)}
            value={confirmation}
          />
        </label>
        <div className="modal-actions">
          <button className="icon-button subtle" disabled={submitting} onClick={onCancel} type="button">
            Cancel
          </button>
          <button
            className="primary-button destructive"
            disabled={!canConfirm}
            onClick={onConfirm}
            type="button"
          >
            <Trash2 size={17} />
            {submitting ? "Cleaning" : "Clean posts"}
          </button>
        </div>
      </section>
    </div>
  );
}

function ImageLightbox({
  media,
  onClose,
  token,
}: {
  media: AdminMedia;
  onClose: () => void;
  token: string;
}) {
  return (
    <div className="lightbox" onClick={onClose} role="presentation">
      <button className="lightbox-close" onClick={onClose} type="button">
        <X size={20} />
      </button>
      <AuthenticatedImage
        alt="Full size post media"
        className="lightbox-image"
        src={media.compressedUrl ?? media.originalUrl}
        token={token}
      />
    </div>
  );
}

function AuthenticatedImage({
  alt,
  className,
  src,
  token,
}: {
  alt: string;
  className: string;
  src: string | null;
  token: string;
}) {
  const [objectURL, setObjectURL] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    let nextURL: string | null = null;

    async function load() {
      if (!src) {
        setObjectURL(null);
        return;
      }

      const response = await fetch(src, {
        headers: {
          Authorization: `Bearer ${token}`,
        },
      });

      if (!response.ok) {
        throw new Error("Image unavailable");
      }

      const blob = await response.blob();
      nextURL = URL.createObjectURL(blob);
      if (!cancelled) {
        setObjectURL(nextURL);
      }
    }

    void load().catch(() => {
      if (!cancelled) {
        setObjectURL(null);
      }
    });

    return () => {
      cancelled = true;
      if (nextURL) {
        URL.revokeObjectURL(nextURL);
      }
    };
  }, [src, token]);

  if (!objectURL) {
    return (
      <div className={`${className} image-placeholder`}>
        <ImageIcon size={22} />
      </div>
    );
  }

  return <img alt={alt} className={className} src={objectURL} />;
}

function Metric({
  detail,
  icon,
  label,
  value,
}: {
  detail: string;
  icon: React.ReactNode;
  label: string;
  value: string;
}) {
  return (
    <article className="metric">
      <div className="metric-icon">{icon}</div>
      <div>
        <span>{label}</span>
        <strong>{value}</strong>
        <small>{detail}</small>
      </div>
    </article>
  );
}

function MetricLite({
  label,
  tone,
  value,
}: {
  label: string;
  tone: "good" | "warn" | "danger" | "neutral";
  value: string;
}) {
  return (
    <article className={`metric-lite ${tone}`}>
      <span>{label}</span>
      <strong>{value}</strong>
    </article>
  );
}

async function apiFetch<T>(
  path: string,
  token: string | null,
  init: RequestInit = {},
): Promise<T> {
  const headers = new Headers(init.headers);
  if (token) {
    headers.set("Authorization", `Bearer ${token}`);
  }

  const response = await fetch(path, {
    ...init,
    headers,
  });

  if (!response.ok) {
    const message = await readErrorMessage(response);
    throw new Error(message);
  }

  return (await response.json()) as T;
}

async function readErrorMessage(response: Response): Promise<string> {
  try {
    const body = (await response.json()) as { message?: unknown };
    return typeof body.message === "string" ? body.message : response.statusText;
  } catch {
    return response.statusText;
  }
}

function formatBytes(value: number): string {
  if (value < 1024) {
    return `${value} B`;
  }

  if (value < 1024 * 1024) {
    return `${(value / 1024).toFixed(1)} KB`;
  }

  return `${(value / 1024 / 1024).toFixed(1)} MB`;
}

function formatDuration(seconds: number | null | undefined): string {
  if (seconds === null || seconds === undefined || !Number.isFinite(seconds)) {
    return "-";
  }

  seconds = Math.round(seconds);
  if (seconds < 60) {
    return `${seconds}s`;
  }

  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) {
    return `${minutes}m`;
  }

  return `${Math.floor(minutes / 60)}h ${minutes % 60}m`;
}

function jobSummary(job: MaintenanceJob): string {
  if (job.status === "running") {
    return `${job.type} · ${job.progress}%${job.stage ? ` · ${job.stage}` : ""}`;
  }

  if (job.errorCode) {
    return `${job.type} · ${job.errorCode}`;
  }

  return `${job.type} · ${job.status}`;
}

function mediaSummary(media: AdminMedia[]): string {
  const active = media.filter((item) => !item.deletedAt);
  const images = active.filter((item) => item.kind === "image").length;
  const videos = active.filter((item) => item.kind === "video").length;
  const audio = active.filter((item) => item.kind === "audio").length;
  const parts = [
    images ? `${images} image${images === 1 ? "" : "s"}` : "",
    videos ? `${videos} video${videos === 1 ? "" : "s"}` : "",
    audio ? `${audio} audio` : "",
  ].filter(Boolean);

  return parts.length ? parts.join(", ") : "no media";
}

function mediaIcon(kind: string) {
  if (kind === "video") {
    return <Video size={18} />;
  }

  if (kind === "audio") {
    return <Mic size={18} />;
  }

  return <ImageIcon size={18} />;
}

function formatDate(value: string | null | undefined): string {
  if (!value) {
    return "-";
  }

  return new Intl.DateTimeFormat(undefined, {
    dateStyle: "medium",
    timeStyle: "short",
  }).format(new Date(value));
}

function shortId(value: string): string {
  return value.slice(0, 8);
}

function deviceLabel(device: Device | null): string {
  if (!device) {
    return "-";
  }

  return `${device.name} (${shortId(device.id)})`;
}

function deviceOptionLabel(device: Device): string {
  const state = device.revokedAt ? "revoked" : formatDate(device.lastSeenAt ?? device.createdAt);
  return `${device.name} · ${shortId(device.id)} · ${state}`;
}

function lastPathSegment(value: string): string {
  return value.split("/").filter(Boolean).at(-1) ?? "";
}

function startOfLocalDay(value: string): Date {
  return new Date(`${value}T00:00:00`);
}

function nextLocalDay(value: string): Date {
  const date = startOfLocalDay(value);
  date.setDate(date.getDate() + 1);
  return date;
}

function adminDeviceKey(): string {
  const existing = localStorage.getItem(ADMIN_DEVICE_KEY);
  if (existing) {
    return existing;
  }

  const next = crypto.randomUUID();
  localStorage.setItem(ADMIN_DEVICE_KEY, next);
  return next;
}
