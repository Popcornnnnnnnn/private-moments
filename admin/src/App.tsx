import { useEffect, useMemo, useState } from "react";
import {
  Activity,
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
  };
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

type AdminTab = "overview" | "posts";
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
  const [activeTab, setActiveTab] = useState<AdminTab>("posts");
  const [status, setStatus] = useState<AdminStatus | null>(null);
  const [devices, setDevices] = useState<Device[]>([]);
  const [logs, setLogs] = useState<LogEntry[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [postsReloadKey, setPostsReloadKey] = useState(0);
  const [cleanPreview, setCleanPreview] = useState<CleanPreview | null>(null);
  const [cleanConfirmation, setCleanConfirmation] = useState("");
  const [cleanSubmitting, setCleanSubmitting] = useState(false);

  async function load() {
    setLoading(true);
    setError(null);

    try {
      const [statusResponse, devicesResponse, logsResponse] = await Promise.all([
        apiFetch<AdminStatus>("/api/v1/admin/status", token),
        apiFetch<{ devices: Device[] }>("/api/v1/devices", token),
        apiFetch<{ logs: LogEntry[] }>("/api/v1/admin/logs?limit=20", token),
      ]);

      setStatus(statusResponse);
      setDevices(devicesResponse.devices);
      setLogs(logsResponse.logs);
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
      setPostsReloadKey((value) => value + 1);
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
          className={activeTab === "overview" ? "tab-button active" : "tab-button"}
          onClick={() => setActiveTab("overview")}
          type="button"
        >
          Overview
        </button>
        <button
          className={activeTab === "posts" ? "tab-button active" : "tab-button"}
          onClick={() => setActiveTab("posts")}
          type="button"
        >
          Posts
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
          onCleanDevice={openCleanDevice}
          onRevokeDevice={revokeDevice}
          status={status}
        />
      ) : (
        <PostsManager
          devices={devices}
          onChanged={() => {
            setPostsReloadKey((value) => value + 1);
            void load();
          }}
          reloadSignal={postsReloadKey}
          token={token}
        />
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
  onCleanDevice,
  onRevokeDevice,
  status,
}: {
  activeDevices: Device[];
  currentDeviceId: string | null;
  devices: Device[];
  logs: LogEntry[];
  onCleanDevice: (deviceId: string) => void;
  onRevokeDevice: (deviceId: string) => void;
  status: AdminStatus | null;
}) {
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
          icon={<Smartphone size={20} />}
          label="Active devices"
          value={String(status?.counts.activeDevices ?? activeDevices.length)}
          detail={`${status?.counts.revokedDevices ?? 0} revoked`}
        />
        <Metric
          icon={<Database size={20} />}
          label="Posts"
          value={String(status?.counts.posts ?? 0)}
          detail={`${status?.counts.deletedPosts ?? 0} deleted`}
        />
        <Metric
          icon={<HardDrive size={20} />}
          label="Storage"
          value={status ? formatBytes(status.storage.totalBytes) : "-"}
          detail={`${status?.counts.media ?? 0} media files`}
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

function adminDeviceKey(): string {
  const existing = localStorage.getItem(ADMIN_DEVICE_KEY);
  if (existing) {
    return existing;
  }

  const next = crypto.randomUUID();
  localStorage.setItem(ADMIN_DEVICE_KEY, next);
  return next;
}
