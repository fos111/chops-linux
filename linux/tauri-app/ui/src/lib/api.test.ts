import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import {
  ApiError,
  DEFAULT_API_BASE,
  createApiClient,
  type ConnectionState,
  type WebSocketLike,
  type WsEvent,
} from "./api";
import { makeSettings, makeSkill, makeTool } from "./test-fixtures";

function jsonResponse(body: unknown, init: ResponseInit = {}): Response {
  return new Response(JSON.stringify(body), {
    status: 200,
    headers: { "Content-Type": "application/json" },
    ...init,
  });
}

interface RecordedCall {
  url: string;
  init?: RequestInit;
}

function recordingFetch(responseFactory: () => Response) {
  const calls: RecordedCall[] = [];
  const fetchImpl = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
    calls.push({ url: String(input), init });
    return responseFactory();
  });
  return { calls, fetchImpl: fetchImpl as unknown as typeof fetch };
}

describe("REST client", () => {
  it("GET /api/tools against the fixed loopback base", async () => {
    const tools = [makeTool()];
    const { calls, fetchImpl } = recordingFetch(() => jsonResponse(tools));
    const client = createApiClient({ fetch: fetchImpl });

    await expect(client.listTools()).resolves.toEqual(tools);
    expect(calls[0].url).toBe(`${DEFAULT_API_BASE}/api/tools`);
    expect(calls[0].init?.method).toBeUndefined();
  });

  it("GET /api/skills without params", async () => {
    const { calls, fetchImpl } = recordingFetch(() => jsonResponse([]));
    const client = createApiClient({ fetch: fetchImpl });

    await client.listSkills();
    expect(calls[0].url).toBe(`${DEFAULT_API_BASE}/api/skills`);
  });

  it("encodes the tool and q filters exactly", async () => {
    const { calls, fetchImpl } = recordingFetch(() => jsonResponse([makeSkill()]));
    const client = createApiClient({ fetch: fetchImpl });

    await client.listSkills({ tool: "claude", q: "foo bar" });
    expect(calls[0].url).toBe(
      `${DEFAULT_API_BASE}/api/skills?tool=claude&q=foo+bar`,
    );
  });

  it("GET /api/settings and PUT /api/settings", async () => {
    const settings = makeSettings();
    const { calls, fetchImpl } = recordingFetch(() => jsonResponse(settings));
    const client = createApiClient({ fetch: fetchImpl });

    await expect(client.getSettings()).resolves.toEqual(settings);
    expect(calls[0].url).toBe(`${DEFAULT_API_BASE}/api/settings`);

    await client.updateSettings({ theme: "dark" });
    expect(calls[1].url).toBe(`${DEFAULT_API_BASE}/api/settings`);
    expect(calls[1].init?.method).toBe("PUT");
    expect(calls[1].init?.body).toBe(JSON.stringify({ theme: "dark" }));
    expect((calls[1].init?.headers as Record<string, string>)["Content-Type"]).toBe(
      "application/json",
    );
  });

  it("surfaces non-OK responses as ApiError", async () => {
    const fetchImpl = vi.fn(async () =>
      new Response("boom", { status: 500, statusText: "Internal Server Error" }),
    ) as unknown as typeof fetch;
    const client = createApiClient({ fetch: fetchImpl });

    const error = await client.listSkills().catch((caught: unknown) => caught);
    expect(error).toBeInstanceOf(ApiError);
    expect((error as ApiError).status).toBe(500);
    expect((error as ApiError).message).toContain("boom");
  });

  it("surfaces an unreachable daemon with a useful message", async () => {
    const fetchImpl = vi.fn(async () => {
      throw new TypeError("fetch failed");
    }) as unknown as typeof fetch;
    const client = createApiClient({ fetch: fetchImpl });

    const error = await client.listTools().catch((caught: unknown) => caught);
    expect(error).toBeInstanceOf(ApiError);
    expect((error as ApiError).status).toBe(0);
    expect((error as ApiError).message).toContain(DEFAULT_API_BASE);
  });

  it("GET/POST /api/collections and DELETE /api/collections/{id}", async () => {
    const collection = {
      id: 1,
      name: "Work",
      icon: "folder",
      sortOrder: 0,
      skillCount: 2,
    };
    const responses = [[collection], collection, { deleted: true }];
    const { calls, fetchImpl } = recordingFetch(() =>
      jsonResponse(responses[calls.length - 1] ?? {}),
    );
    const client = createApiClient({ fetch: fetchImpl });

    await expect(client.listCollections()).resolves.toEqual([collection]);
    expect(calls[0].url).toBe(`${DEFAULT_API_BASE}/api/collections`);

    await expect(
      client.createCollection({ name: "Work", icon: "star" }),
    ).resolves.toEqual(collection);
    expect(calls[1].init?.method).toBe("POST");
    expect(calls[1].init?.body).toBe(
      JSON.stringify({ name: "Work", icon: "star" }),
    );

    await expect(client.deleteCollection(7)).resolves.toEqual({
      deleted: true,
    });
    expect(calls[2].init?.method).toBe("DELETE");
    expect(calls[2].url).toBe(`${DEFAULT_API_BASE}/api/collections/7`);
  });

  it("registry trending, search, and install use the chopsd mirror", async () => {    const rows = [makeRegistrySkill()];
    const installed = {
      installed: true,
      skillName: "demo",
      path: "/home/test/.agents/skills/demo/SKILL.md",
      targets: ["claude"],
      skill: makeSkill(),
    };
    const responses = [rows, rows, installed];
    const { calls, fetchImpl } = recordingFetch(() =>
      jsonResponse(responses[calls.length - 1] ?? {}),
    );
    const client = createApiClient({ fetch: fetchImpl });

    await expect(client.listTrending()).resolves.toEqual(rows);
    expect(calls[0].url).toBe(`${DEFAULT_API_BASE}/api/registry/trending`);

    await expect(client.searchRegistry("react ui")).resolves.toEqual(rows);
    expect(calls[1].url).toBe(
      `${DEFAULT_API_BASE}/api/registry/search?q=react+ui`,
    );

    await expect(
      client.installRegistry({
        skillId: "demo",
        name: "Demo",
        source: "demo/repo",
        targets: ["claude"],
      }),
    ).resolves.toEqual(installed);
    expect(calls[2].init?.method).toBe("POST");
    expect(calls[2].url).toBe(`${DEFAULT_API_BASE}/api/registry/install`);
    expect(JSON.parse(String(calls[2].init?.body))).toEqual({
      skillId: "demo",
      name: "Demo",
      source: "demo/repo",
      targets: ["claude"],
    });
  });

  it("collections detail and membership helpers ride the join-table routes", async () => {
    const detail = {
      collection: {
        id: 1,
        name: "Work",
        icon: "folder",
        sortOrder: 0,
        skillCount: 1,
      },
      skills: [makeSkill()],
    };
    const responses = [detail, detail, detail];
    const { calls, fetchImpl } = recordingFetch(() =>
      jsonResponse(responses[calls.length - 1] ?? {}),
    );
    const client = createApiClient({ fetch: fetchImpl });

    await expect(client.getCollection(1)).resolves.toEqual(detail);
    expect(calls[0].url).toBe(`${DEFAULT_API_BASE}/api/collections/1`);

    await expect(client.addCollectionSkill(1, 42)).resolves.toEqual(detail);
    expect(calls[1].init?.method).toBe("POST");
    expect(calls[1].url).toBe(`${DEFAULT_API_BASE}/api/collections/1/skills`);
    expect(calls[1].init?.body).toBe(JSON.stringify({ skillId: 42 }));

    await expect(client.removeCollectionSkill(1, 42)).resolves.toEqual(detail);
    expect(calls[2].init?.method).toBe("DELETE");
    expect(calls[2].url).toBe(
      `${DEFAULT_API_BASE}/api/collections/1/skills/42`,
    );
  });

  it("POST /api/assist sends only the frozen contract fields (no model)", async () => {
    const response = {
      pendingId: "pending-1",
      summary: "Updated the heading.",
      fullFile: "# Alpha\n\nBody.",
      path: "/home/test/.claude/skills/skill-1.md",
      agent: "codex",
      skillId: 1,
    };
    const { calls, fetchImpl } = recordingFetch(() => jsonResponse(response));
    const client = createApiClient({ fetch: fetchImpl });

    await expect(
      client.assist({
        skillId: 1,
        prompt: "Tighten the wording",
        agent: "codex",
        content: "# Alpha\n",
      }),
    ).resolves.toEqual(response);

    expect(calls[0].url).toBe(`${DEFAULT_API_BASE}/api/assist`);
    expect(calls[0].init?.method).toBe("POST");
    expect(JSON.parse(String(calls[0].init?.body))).toEqual({
      skillId: 1,
      prompt: "Tighten the wording",
      agent: "codex",
      content: "# Alpha\n",
    });
  });

  it("accepts and rejects pending assist writes on the diff gate", async () => {
    const accepted = {
      accepted: true,
      pendingId: "pending-1",
      path: "/home/test/.claude/skills/skill-1.md",
      skill: makeSkill({ id: 1 }),
    };
    const rejected = { rejected: true, pendingId: "pending-1" };
    const responses = [accepted, rejected];
    const { calls, fetchImpl } = recordingFetch(() =>
      jsonResponse(responses[calls.length - 1] ?? {}),
    );
    const client = createApiClient({ fetch: fetchImpl });

    await expect(client.acceptAssist("pending-1")).resolves.toEqual(accepted);
    expect(calls[0].init?.method).toBe("POST");
    expect(calls[0].url).toBe(`${DEFAULT_API_BASE}/api/assist/pending-1/accept`);

    await expect(client.rejectAssist("pending-1")).resolves.toEqual(rejected);
    expect(calls[1].init?.method).toBe("POST");
    expect(calls[1].url).toBe(
      `${DEFAULT_API_BASE}/api/assist/pending-1/reject`,
    );
  });

  it("remote server CRUD uses the SSH routes", async () => {
    const server = {
      id: "srv-1",
      label: "Production",
      host: "192.168.1.100",
      port: 22,
      username: "root",
      skillsBasePath: "~/.hermes/skills",
      sshKeyPath: null,
      lastSyncDate: null,
      lastSyncError: null,
    };
    const responses = [[server], server, server, { deleted: true }];
    const { calls, fetchImpl } = recordingFetch(() =>
      jsonResponse(responses[calls.length - 1] ?? {}),
    );
    const client = createApiClient({ fetch: fetchImpl });

    await expect(client.listRemoteServers()).resolves.toEqual([server]);
    expect(calls[0].url).toBe(`${DEFAULT_API_BASE}/api/remote/servers`);

    const request = {
      label: "Production",
      host: "192.168.1.100",
      port: 22,
      username: "root",
      skillsBasePath: "~/.hermes/skills",
    };
    await expect(client.createRemoteServer(request)).resolves.toEqual(server);
    expect(calls[1].init?.method).toBe("POST");
    expect(calls[1].url).toBe(`${DEFAULT_API_BASE}/api/remote/servers`);
    expect(JSON.parse(String(calls[1].init?.body))).toEqual(request);

    await expect(
      client.updateRemoteServer("srv-1", { ...request, label: "Staging" }),
    ).resolves.toEqual(server);
    expect(calls[2].init?.method).toBe("PUT");
    expect(calls[2].url).toBe(
      `${DEFAULT_API_BASE}/api/remote/servers/srv-1`,
    );

    await expect(client.deleteRemoteServer("srv-1")).resolves.toEqual({
      deleted: true,
    });
    expect(calls[3].init?.method).toBe("DELETE");
    expect(calls[3].url).toBe(
      `${DEFAULT_API_BASE}/api/remote/servers/srv-1`,
    );
  });

  it("browses and installs remote skills over the SSH bridge", async () => {
    const browse = {
      serverId: "srv-1",
      skills: [
        {
          path: "skills/r-one/SKILL.md",
          name: "r-one",
          description: "remote fixture",
          content: "# R One",
        },
      ],
      lastSyncDate: "2026-10-22T12:00:00Z",
    };
    const installed = {
      installed: true,
      skillName: "r-one",
      path: "/home/test/.agents/skills/r-one/SKILL.md",
      targets: ["claude"],
      skill: null,
    };
    const responses = [browse, installed];
    const { calls, fetchImpl } = recordingFetch(() =>
      jsonResponse(responses[calls.length - 1] ?? {}),
    );
    const client = createApiClient({ fetch: fetchImpl });

    await expect(client.browseRemote("srv-1")).resolves.toEqual(browse);
    expect(calls[0].url).toBe(`${DEFAULT_API_BASE}/api/remote/browse`);
    expect(calls[0].init?.method).toBe("POST");
    expect(calls[0].init?.body).toBe(JSON.stringify({ serverId: "srv-1" }));

    await expect(
      client.installRemote({
        serverId: "srv-1",
        remotePath: "skills/r-one/SKILL.md",
      }),
    ).resolves.toEqual(installed);
    expect(calls[1].url).toBe(`${DEFAULT_API_BASE}/api/remote/install`);
    expect(calls[1].init?.method).toBe("POST");
    expect(JSON.parse(String(calls[1].init?.body))).toEqual({
      serverId: "srv-1",
      remotePath: "skills/r-one/SKILL.md",
    });
  });
});

function makeRegistrySkill(overrides: Record<string, unknown> = {}) {
  return {
    skillId: "demo",
    name: "Demo",
    installs: 5,
    source: "demo/repo",
    isOfficial: false,
    ...overrides,
  };
}

class FakeSocket implements WebSocketLike {
  static instances: FakeSocket[] = [];

  onopen: ((event: unknown) => void) | null = null;
  onclose: ((event: unknown) => void) | null = null;
  onerror: ((event: unknown) => void) | null = null;
  onmessage: ((event: { data: unknown }) => void) | null = null;
  closed = false;

  constructor(readonly url: string) {
    FakeSocket.instances.push(this);
  }

  close(): void {
    this.closed = true;
  }

  open(): void {
    this.onopen?.({});
  }

  message(data: unknown): void {
    this.onmessage?.({ data });
  }

  drop(): void {
    this.onclose?.({});
  }
}

describe("WebSocket /ws client", () => {
  const statuses: ConnectionState[] = [];
  const events: WsEvent[] = [];
  const handlers = {
    onEvent: (event: WsEvent) => events.push(event),
    onStatus: (state: ConnectionState) => statuses.push(state),
  };

  let connection: { close: () => void } | null = null;

  beforeEach(() => {
    FakeSocket.instances = [];
    statuses.length = 0;
    events.length = 0;
  });

  afterEach(() => {
    connection?.close();
    connection = null;
    vi.useRealTimers();
  });

  it("connects to ws://127.0.0.1:47115/ws and delivers parsed events", () => {
    const client = createApiClient({
      webSocketFactory: (url) => new FakeSocket(url),
    });
    connection = client.connectEvents(handlers);

    expect(FakeSocket.instances).toHaveLength(1);
    expect(FakeSocket.instances[0].url).toBe("ws://127.0.0.1:47115/ws");
    expect(statuses).toEqual(["connecting"]);

    FakeSocket.instances[0].open();
    expect(statuses).toEqual(["connecting", "connected"]);

    FakeSocket.instances[0].message(
      JSON.stringify({ type: "rescan", timestamp: "t", reason: "watch", count: 8 }),
    );
    expect(events).toEqual([
      { type: "rescan", timestamp: "t", reason: "watch", count: 8 },
    ]);
  });

  it("ignores malformed frames instead of crashing the socket handler", () => {
    const client = createApiClient({
      webSocketFactory: (url) => new FakeSocket(url),
    });
    connection = client.connectEvents(handlers);

    expect(() => FakeSocket.instances[0].message("{not json")).not.toThrow();
    expect(() => FakeSocket.instances[0].message("null")).not.toThrow();
    expect(() => FakeSocket.instances[0].message(42)).not.toThrow();
    expect(events).toEqual([]);
  });

  it("reconnects after the socket closes", async () => {
    vi.useFakeTimers();
    const client = createApiClient({
      webSocketFactory: (url) => new FakeSocket(url),
      reconnectDelayMs: 500,
    });
    connection = client.connectEvents(handlers);

    FakeSocket.instances[0].open();
    FakeSocket.instances[0].drop();
    expect(statuses.at(-1)).toBe("disconnected");

    await vi.advanceTimersByTimeAsync(500);
    expect(FakeSocket.instances).toHaveLength(2);
    expect(statuses.at(-1)).toBe("connecting");

    FakeSocket.instances[1].open();
    expect(statuses.at(-1)).toBe("connected");
  });

  it("close() stops reconnection", async () => {
    vi.useFakeTimers();
    const client = createApiClient({
      webSocketFactory: (url) => new FakeSocket(url),
      reconnectDelayMs: 500,
    });
    connection = client.connectEvents(handlers);

    FakeSocket.instances[0].open();
    const socket = FakeSocket.instances[0];
    connection.close();
    connection = null;

    expect(socket.closed).toBe(true);
    await vi.advanceTimersByTimeAsync(2000);
    expect(FakeSocket.instances).toHaveLength(1);
    expect(statuses.at(-1)).toBe("disconnected");
  });
});
