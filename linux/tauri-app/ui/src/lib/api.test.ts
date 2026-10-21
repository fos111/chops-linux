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
});

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
