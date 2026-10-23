// Typed client for the fixed UI <-> chopsd contract
// (`.omo/plans/debian-linux-port.md`, mirrored by `Core/chopsd/DTO.swift`).
//
// Every path here exists in the contract table; nothing is invented. The front-end
// never touches skill files directly: reads come from `/api/skills`, saves go through
// `PUT /api/skills/{id}`, and creation goes through `POST /api/skills`.

export const DEFAULT_API_BASE = "http://127.0.0.1:47115";

export type ThemeMode = "system" | "light" | "dark";

export interface CollectionRef {
  id: number;
  name: string;
  icon: string;
  sortOrder: number;
}

/** `SkillDTO` from chopsd. */
export interface Skill {
  id: number;
  filePath: string;
  resolvedPath: string;
  name: string;
  description: string;
  content: string;
  frontmatter: Record<string, string>;
  isDirectory: boolean;
  isGlobal: boolean;
  isFavorite: boolean;
  fileModifiedDate: string;
  fileSize: number;
  toolSources: string[];
  installedPaths: string[];
  kind: string;
  collections: CollectionRef[];
  remoteServerID: string | null;
  remotePath: string | null;
}

/** `ToolDTO` from chopsd; `id` is the frozen `ToolSource` raw value. */
export interface Tool {
  id: string;
  displayName: string;
  isInstalled: boolean;
  listable: boolean;
  supportsSkills: boolean;
  supportsAgents: boolean;
  supportsRules: boolean;
  globalPaths: string[];
  globalAgentPaths: string[];
  globalRulePaths: string[];
}

/** `SettingsResponse` from chopsd. */
export interface Settings {
  sotDir: string;
  scanRoots: string[];
  includePluginSkills: boolean;
  theme: ThemeMode;
  homeDirectory: string;
  settingsPath: string;
  databasePath: string;
}

/** `SettingsUpdateRequest` accepts a subset of the mutable fields. */
export interface SettingsPatch {
  sotDir?: string;
  scanRoots?: string[];
  includePluginSkills?: boolean;
  theme?: ThemeMode;
}

/** `CollectionDTO` from chopsd (list payload, carries the member count). */
export interface CollectionSummary {
  id: number;
  name: string;
  icon: string;
  sortOrder: number;
  skillCount: number;
}

/** `CollectionDetailDTO` from chopsd (`GET /api/collections/{id}`). */
export interface CollectionDetail {
  collection: CollectionSummary;
  skills: Skill[];
}

/** `RegistrySkillDTO` from chopsd (port of macOS `SkillRegistry.RegistrySkill`). */
export interface RegistrySkill {
  skillId: string;
  name: string;
  installs: number;
  source: string;
  isOfficial: boolean | null;
}

/** `POST /api/registry/install` body (`RegistryInstallRequest` in chopsd). */
export interface RegistryInstallRequest {
  skillId: string;
  name: string;
  source: string;
  installs?: number;
  isOfficial?: boolean | null;
  /** Tool raw values (`claude`, `codex`, …). Omitted = every installed tool. */
  targets?: string[];
}

/** `RegistryInstallResponse` from chopsd. */
export interface RegistryInstallResponse {
  installed: boolean;
  skillName: string;
  path: string;
  targets: string[];
  skill: Skill | null;
}

/** `POST/DELETE …/collections/{id}/skills` response (`MembershipResponse`). */
export interface MembershipResult {
  added?: boolean;
  removed?: boolean;
}

/** `POST /api/skills` body (`SkillCreateRequest` in chopsd). */
export interface SkillCreateRequest {
  name: string;
  tool: string;
  kind?: string;
}

/**
 * Frozen `AgentID` raw values from the macOS app (`Chops/Models/AgentConfiguration.swift`).
 * chopsd accepts exactly these on `POST /api/assist`.
 */
export type AgentID = "claude" | "codex";

/** One compose turn (`AssistRequest` in chopsd). There is no `model` field. */
export interface AssistRequest {
  skillId: number;
  prompt: string;
  agent?: AgentID;
  /** Current editor buffer; chopsd falls back to the stored skill content. */
  content?: string;
}

/**
 * `AssistResponse` from chopsd. `pendingId`/`fullFile` are null when the agent
 * replied with prose only (no file proposal), so no diff gate is created.
 */
export interface AssistResponse {
  pendingId: string | null;
  summary: string;
  fullFile: string | null;
  path: string | null;
  agent: string;
  skillId: number;
}

/** `AssistAcceptResponse`: chopsd wrote the pending file and re-scanned it. */
export interface AssistAcceptResponse {
  accepted: boolean;
  pendingId: string;
  path: string;
  skill: Skill | null;
}

/** `AssistRejectResponse`: the pending write was discarded. */
export interface AssistRejectResponse {
  rejected: boolean;
  pendingId: string;
}

/** `RemoteServerDTO` from chopsd (key-based SSH target). */
export interface RemoteServer {
  id: string;
  label: string;
  host: string;
  port: number;
  username: string;
  skillsBasePath: string;
  sshKeyPath: string | null;
  lastSyncDate: string | null;
  lastSyncError: string | null;
}

/** `RemoteServerRequest` for POST/PUT `/api/remote/servers`. */
export interface RemoteServerRequest {
  id?: string;
  label: string;
  host: string;
  port?: number;
  username: string;
  skillsBasePath: string;
  sshKeyPath?: string | null;
}

/** One row in `RemoteBrowseResponse.skills`. */
export interface RemoteSkill {
  path: string;
  name: string;
  description: string;
  content: string;
}

/** `RemoteBrowseResponse` from `POST /api/remote/browse`. */
export interface RemoteBrowseResponse {
  serverId: string;
  skills: RemoteSkill[];
  lastSyncDate: string;
}

/** `RemoteInstallRequest` for `POST /api/remote/install`. */
export interface RemoteInstallRequest {
  serverId: string;
  remotePath: string;
  targets?: string[];
}

export type WsEventType = "rescan" | "file-changed" | "assist-status";

/** One `/ws` frame (`WSEvent` in chopsd). */
export interface WsEvent {
  type: WsEventType;
  timestamp: string;
  path?: string;
  kind?: string;
  reason?: string;
  count?: number;
  pendingId?: string;
  status?: string;
  message?: string;
  skillId?: number;
}

export type ConnectionState = "connecting" | "connected" | "disconnected";

export interface EventHandlers {
  onEvent: (event: WsEvent) => void;
  onStatus: (state: ConnectionState) => void;
}

export interface EventConnection {
  close: () => void;
}

/** Minimal WebSocket surface so tests can inject a fake. */
export interface WebSocketLike {
  onopen: ((event: unknown) => void) | null;
  onclose: ((event: unknown) => void) | null;
  onerror: ((event: unknown) => void) | null;
  onmessage: ((event: { data: unknown }) => void) | null;
  close: () => void;
}

export interface ApiClientOptions {
  baseUrl?: string;
  fetch?: typeof fetch;
  webSocketFactory?: (url: string) => WebSocketLike;
  reconnectDelayMs?: number;
  setTimeout?: (callback: () => void, delayMs: number) => unknown;
  clearTimeout?: (handle: unknown) => void;
}

export class ApiError extends Error {
  readonly status: number;
  readonly url: string;

  constructor(message: string, status: number, url: string) {
    super(message);
    this.name = "ApiError";
    this.status = status;
    this.url = url;
  }
}

export interface ChopsApi {
  listTools: () => Promise<Tool[]>;
  listSkills: (params?: { tool?: string; q?: string }) => Promise<Skill[]>;
  getSkill: (id: number) => Promise<Skill>;
  /** Writes the complete Markdown file (editor save, macOS parity). */
  updateSkill: (id: number, content: string) => Promise<Skill>;
  /** Creates a template file in chopsd; the UI never touches the filesystem. */
  createSkill: (request: SkillCreateRequest) => Promise<Skill>;
  // Assist (one compose turn, then the diff-review gate).
  assist: (request: AssistRequest) => Promise<AssistResponse>;
  acceptAssist: (pendingId: string) => Promise<AssistAcceptResponse>;
  rejectAssist: (pendingId: string) => Promise<AssistRejectResponse>;
  // Collections (chopsd join-table CRUD + the two membership helpers).
  listCollections: () => Promise<CollectionSummary[]>;
  createCollection: (request: {
    name: string;
    icon?: string;
    sortOrder?: number;
  }) => Promise<CollectionSummary>;
  deleteCollection: (id: number) => Promise<{ deleted: boolean }>;
  getCollection: (id: number) => Promise<CollectionDetail>;
  addCollectionSkill: (
    collectionId: number,
    skillId: number,
  ) => Promise<MembershipResult>;
  removeCollectionSkill: (
    collectionId: number,
    skillId: number,
  ) => Promise<MembershipResult>;
  // Registry (chopsd mirrors skills.sh; no direct network from the UI).
  listTrending: () => Promise<RegistrySkill[]>;
  searchRegistry: (q: string) => Promise<RegistrySkill[]>;
  installRegistry: (
    request: RegistryInstallRequest,
  ) => Promise<RegistryInstallResponse>;
  getSettings: () => Promise<Settings>;
  updateSettings: (patch: SettingsPatch) => Promise<Settings>;
  // Remote servers (SSH; the UI lists/edits targets and drives browse/install).
  listRemoteServers: () => Promise<RemoteServer[]>;
  createRemoteServer: (request: RemoteServerRequest) => Promise<RemoteServer>;
  updateRemoteServer: (
    id: string,
    request: RemoteServerRequest,
  ) => Promise<RemoteServer>;
  deleteRemoteServer: (id: string) => Promise<{ deleted: boolean }>;
  browseRemote: (serverId: string) => Promise<RemoteBrowseResponse>;
  installRemote: (
    request: RemoteInstallRequest,
  ) => Promise<RegistryInstallResponse>;
  connectEvents: (handlers: EventHandlers) => EventConnection;
}

function errorMessage(error: unknown): string {
  if (error instanceof Error) return error.message;
  return String(error);
}

export function createApiClient(options: ApiClientOptions = {}): ChopsApi {
  const baseUrl = (options.baseUrl ?? DEFAULT_API_BASE).replace(/\/+$/, "");
  const fetchImpl = options.fetch ?? globalThis.fetch.bind(globalThis);
  const webSocketFactory =
    options.webSocketFactory ??
    ((url: string) => new WebSocket(url) as unknown as WebSocketLike);
  const reconnectDelayMs = options.reconnectDelayMs ?? 1000;
  const schedule = options.setTimeout ?? ((fn, ms) => setTimeout(fn, ms));
  const cancel = options.clearTimeout ?? ((handle) => clearTimeout(handle as ReturnType<typeof setTimeout>));

  async function request<T>(path: string, init: RequestInit = {}): Promise<T> {
    const url = `${baseUrl}${path}`;
    const headers: Record<string, string> = {
      Accept: "application/json",
      ...(init.headers as Record<string, string> | undefined),
    };
    if (init.body !== undefined) {
      headers["Content-Type"] = "application/json";
    }

    let response: Response;
    try {
      response = await fetchImpl(url, { ...init, headers });
    } catch (error) {
      throw new ApiError(
        `chopsd is not reachable at ${baseUrl}: ${errorMessage(error)}`,
        0,
        url,
      );
    }

    if (!response.ok) {
      const detail = await response.text().catch(() => "");
      const reason = detail.trim() || response.statusText;
      throw new ApiError(
        `${init.method ?? "GET"} ${path} failed (${response.status}): ${reason}`,
        response.status,
        url,
      );
    }

    if (response.status === 204) {
      return undefined as T;
    }
    return (await response.json()) as T;
  }

  return {
    listTools() {
      return request<Tool[]>("/api/tools");
    },

    listSkills(params = {}) {
      const query = new URLSearchParams();
      if (params.tool) query.set("tool", params.tool);
      if (params.q) query.set("q", params.q);
      const suffix = query.toString();
      return request<Skill[]>(`/api/skills${suffix ? `?${suffix}` : ""}`);
    },

    getSkill(id) {
      return request<Skill>(`/api/skills/${id}`);
    },

    updateSkill(id, content) {
      return request<Skill>(`/api/skills/${id}`, {
        method: "PUT",
        body: JSON.stringify({ content }),
      });
    },

    createSkill(createRequest) {
      return request<Skill>("/api/skills", {
        method: "POST",
        body: JSON.stringify(createRequest),
      });
    },

    assist(assistRequest) {
      return request<AssistResponse>("/api/assist", {
        method: "POST",
        body: JSON.stringify(assistRequest),
      });
    },

    acceptAssist(pendingId) {
      return request<AssistAcceptResponse>(
        `/api/assist/${encodeURIComponent(pendingId)}/accept`,
        { method: "POST" },
      );
    },

    rejectAssist(pendingId) {
      return request<AssistRejectResponse>(
        `/api/assist/${encodeURIComponent(pendingId)}/reject`,
        { method: "POST" },
      );
    },

    listCollections() {
      return request<CollectionSummary[]>("/api/collections");
    },

    createCollection(createRequest) {
      return request<CollectionSummary>("/api/collections", {
        method: "POST",
        body: JSON.stringify(createRequest),
      });
    },

    deleteCollection(id) {
      return request<{ deleted: boolean }>(`/api/collections/${id}`, {
        method: "DELETE",
      });
    },

    getCollection(id) {
      return request<CollectionDetail>(`/api/collections/${id}`);
    },

    addCollectionSkill(collectionId, skillId) {
      return request<MembershipResult>(
        `/api/collections/${collectionId}/skills`,
        {
          method: "POST",
          body: JSON.stringify({ skillId }),
        },
      );
    },

    removeCollectionSkill(collectionId, skillId) {
      return request<MembershipResult>(
        `/api/collections/${collectionId}/skills/${skillId}`,
        { method: "DELETE" },
      );
    },

    listTrending() {
      return request<RegistrySkill[]>("/api/registry/trending");
    },

    searchRegistry(q) {
      const query = new URLSearchParams();
      query.set("q", q);
      return request<RegistrySkill[]>(`/api/registry/search?${query.toString()}`);
    },

    installRegistry(installRequest) {
      return request<RegistryInstallResponse>("/api/registry/install", {
        method: "POST",
        body: JSON.stringify(installRequest),
      });
    },

    getSettings() {
      return request<Settings>("/api/settings");
    },

    updateSettings(patch) {
      return request<Settings>("/api/settings", {
        method: "PUT",
        body: JSON.stringify(patch),
      });
    },

    listRemoteServers() {
      return request<RemoteServer[]>("/api/remote/servers");
    },

    createRemoteServer(createRequest) {
      return request<RemoteServer>("/api/remote/servers", {
        method: "POST",
        body: JSON.stringify(createRequest),
      });
    },

    updateRemoteServer(id, updateRequest) {
      return request<RemoteServer>(
        `/api/remote/servers/${encodeURIComponent(id)}`,
        {
          method: "PUT",
          body: JSON.stringify(updateRequest),
        },
      );
    },

    deleteRemoteServer(id) {
      return request<{ deleted: boolean }>(
        `/api/remote/servers/${encodeURIComponent(id)}`,
        { method: "DELETE" },
      );
    },

    browseRemote(serverId) {
      return request<RemoteBrowseResponse>("/api/remote/browse", {
        method: "POST",
        body: JSON.stringify({ serverId }),
      });
    },

    installRemote(installRequest) {
      return request<RegistryInstallResponse>("/api/remote/install", {
        method: "POST",
        body: JSON.stringify(installRequest),
      });
    },

    connectEvents(handlers) {
      let socket: WebSocketLike | null = null;
      let retryHandle: unknown = null;
      let closed = false;

      const connect = () => {
        if (closed) return;
        handlers.onStatus("connecting");
        const wsUrl = `${baseUrl.replace(/^http/, "ws")}/ws`;
        socket = webSocketFactory(wsUrl);

        socket.onopen = () => {
          if (closed) return;
          handlers.onStatus("connected");
        };

        socket.onmessage = (event) => {
          if (typeof event.data !== "string") return;
          let parsed: unknown;
          try {
            parsed = JSON.parse(event.data);
          } catch {
            return;
          }
          if (
            typeof parsed === "object" &&
            parsed !== null &&
            typeof (parsed as WsEvent).type === "string"
          ) {
            handlers.onEvent(parsed as WsEvent);
          }
        };

        socket.onerror = () => {
          // The close handler performs the reconnect; errors are not terminal.
        };

        socket.onclose = () => {
          if (closed) return;
          handlers.onStatus("disconnected");
          retryHandle = schedule(connect, reconnectDelayMs);
        };
      };

      connect();

      return {
        close() {
          if (closed) return;
          closed = true;
          if (retryHandle !== null) {
            cancel(retryHandle);
            retryHandle = null;
          }
          socket?.close();
          socket = null;
          handlers.onStatus("disconnected");
        },
      };
    },
  };
}
