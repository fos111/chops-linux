// Typed client for the fixed UI <-> chopsd contract
// (`.omo/plans/debian-linux-port.md`, mirrored by `Core/chopsd/DTO.swift`).
//
// Every path here exists in the contract table; nothing is invented. The front-end
// never touches skill files directly: reads come from `/api/skills` and the only
// writes wired in this task are settings (theme).

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
  getSettings: () => Promise<Settings>;
  updateSettings: (patch: SettingsPatch) => Promise<Settings>;
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

    getSettings() {
      return request<Settings>("/api/settings");
    },

    updateSettings(patch) {
      return request<Settings>("/api/settings", {
        method: "PUT",
        body: JSON.stringify(patch),
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
