import { afterEach, describe, expect, it, vi } from "vitest";
import {
  type ChopsApi,
  type EventHandlers,
  type Settings,
  type Skill,
  type Tool,
} from "./api";
import { ChopsApp } from "./app.svelte.js";
import { applyTheme } from "./theme";
import { makeSettings, makeSkill, makeTool } from "./test-fixtures";

interface FakeClient {
  client: ChopsApi;
  handlers: EventHandlers[];
  close: ReturnType<typeof vi.fn>;
  listTools: ReturnType<typeof vi.fn>;
  listSkills: ReturnType<typeof vi.fn>;
  getSettings: ReturnType<typeof vi.fn>;
  updateSettings: ReturnType<typeof vi.fn>;
  tools: Tool[];
  skills: Skill[];
  settings: Settings;
}

function makeFakeClient(overrides: Partial<ChopsApi> = {}): FakeClient {
  const tools = [
    makeTool({ id: "claude", displayName: "Claude Code" }),
    makeTool({ id: "codex", displayName: "Codex" }),
  ];
  const skills = [
    makeSkill({
      id: 2,
      name: "beta",
      kind: "agent",
      toolSources: ["codex"],
      description: "review agent",
    }),
    makeSkill({
      id: 1,
      name: "Alpha",
      toolSources: ["claude"],
      description: "first skill",
      content: "# Alpha\nneedle",
    }),
  ];
  const settings = makeSettings({ theme: "dark" });
  const handlers: EventHandlers[] = [];
  const close = vi.fn();

  const listTools = vi.fn(async () => tools);
  const listSkills = vi.fn(async () => skills);
  const getSettings = vi.fn(async () => settings);
  const updateSettings = vi.fn(async (patch: Partial<Settings>) => ({
    ...settings,
    ...patch,
  }));

  const client: ChopsApi = {
    listTools,
    listSkills,
    getSettings,
    updateSettings,
    connectEvents: (nextHandlers) => {
      handlers.push(nextHandlers);
      return { close };
    },
    ...overrides,
  };

  return {
    client,
    handlers,
    close,
    listTools,
    listSkills,
    getSettings,
    updateSettings,
    tools,
    skills,
    settings,
  };
}

function createApp(fake: FakeClient, debounceMs = 0): ChopsApp {
  return new ChopsApp(fake.client, {
    refreshDebounceMs: debounceMs,
    prefersDark: () => true,
    watchSystem: () => () => {},
  });
}

const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

afterEach(() => {
  applyTheme("system");
});

describe("ChopsApp bootstrap", () => {
  it("loads tools, skills, and settings; selects the first visible row", async () => {
    const fake = makeFakeClient();
    const app = createApp(fake);
    const stop = app.start();
    await app.ready;

    expect(app.tools).toEqual(fake.tools);
    expect(app.skills.map((skill) => skill.name)).toEqual(["Alpha", "beta"]);
    expect(app.selectedId).toBe(1);
    expect(app.theme).toBe("dark");
    expect(document.documentElement.getAttribute("data-theme")).toBe("dark");
    expect(app.connection).toBe("connecting");
    expect(fake.handlers).toHaveLength(1);

    stop();
  });

  it("reports a daemon failure without clearing the default theme", async () => {
    const failure = new Error("chopsd is not reachable at http://127.0.0.1:47115");
    const fake = makeFakeClient({
      getSettings: vi.fn(async () => {
        throw failure;
      }),
      listTools: vi.fn(async () => {
        throw failure;
      }),
      listSkills: vi.fn(async () => {
        throw failure;
      }),
    });
    const app = createApp(fake);
    const stop = app.start();
    await app.ready;

    expect(app.loadError).toContain("not reachable");
    expect(app.settingsError).toContain("not reachable");
    expect(app.theme).toBe("system");
    expect(app.skills).toEqual([]);
    stop();
  });
});

describe("filters, search, and selection", () => {
  it("reconciles selection when the sidebar filter changes", async () => {
    const fake = makeFakeClient();
    const app = createApp(fake);
    app.start();
    await app.ready;

    expect(app.visibleSkills.map((skill) => skill.name)).toEqual(["Alpha"]);
    app.setFilter({ type: "allAgents" });
    expect(app.visibleSkills.map((skill) => skill.name)).toEqual(["beta"]);
    expect(app.selectedId).toBe(2);

    app.setFilter({ type: "tool", tool: "claude" });
    expect(app.visibleSkills.map((skill) => skill.name)).toEqual(["Alpha"]);
    expect(app.selectedId).toBe(1);
    app.stop();
  });

  it("searches name/description/content without stealing the selection", async () => {
    const fake = makeFakeClient();
    const app = createApp(fake);
    app.start();
    await app.ready;

    app.setSearchText("review");
    expect(app.visibleSkills).toEqual([]);
    expect(app.selectedId).toBe(1);

    app.setSearchText("needle");
    expect(app.visibleSkills.map((skill) => skill.name)).toEqual(["Alpha"]);
    expect(app.selectedId).toBe(1);
    app.stop();
  });
});

describe("live refresh", () => {
  it("refetches skills after rescan and file-changed events", async () => {
    const fake = makeFakeClient();
    const app = createApp(fake);
    app.start();
    await app.ready;

    const before = fake.listSkills.mock.calls.length;
    app.handleEvent({ type: "file-changed", timestamp: "t", path: "/tmp/a.md" });
    await sleep(10);
    expect(fake.listSkills.mock.calls.length).toBe(before + 1);

    app.handleEvent({ type: "rescan", timestamp: "t", reason: "watch", count: 2 });
    await sleep(10);
    expect(fake.listSkills.mock.calls.length).toBe(before + 2);
    app.stop();
  });

  it("ignores assist-status events in this shell", async () => {
    const fake = makeFakeClient();
    const app = createApp(fake);
    app.start();
    await app.ready;

    const before = fake.listSkills.mock.calls.length;
    app.handleEvent({
      type: "assist-status",
      timestamp: "t",
      pendingId: "p1",
      status: "running",
    });
    await sleep(10);
    expect(fake.listSkills.mock.calls.length).toBe(before);
    app.stop();
  });
});

describe("theme persistence", () => {
  it("PUTs the selected mode and applies it", async () => {
    const fake = makeFakeClient();
    const app = createApp(fake);
    app.start();
    await app.ready;

    await app.setTheme("light");
    expect(fake.updateSettings).toHaveBeenCalledWith({ theme: "light" });
    expect(app.theme).toBe("light");
    expect(document.documentElement.getAttribute("data-theme")).toBe("light");
    app.stop();
  });

  it("keeps the in-memory mode and surfaces a persistence error", async () => {
    const fake = makeFakeClient();
    fake.updateSettings.mockRejectedValueOnce(new Error("PUT failed"));
    const app = createApp(fake);
    app.start();
    await app.ready;

    await app.setTheme("light");
    expect(app.theme).toBe("light");
    expect(app.settingsError).toContain("PUT failed");
    app.stop();
  });
});

describe("shell state", () => {
  it("drives palette, sidebar, unsaved chip, and retry state", async () => {
    const fake = makeFakeClient();
    const app = createApp(fake);
    const stop = app.start();
    await app.ready;

    app.openPalette();
    expect(app.paletteOpen).toBe(true);
    app.runPaletteAction({ type: "favorites" });
    expect(app.filter).toEqual({ type: "favorites" });
    expect(app.paletteOpen).toBe(false);

    expect(app.sidebarVisible).toBe(true);
    app.toggleSidebar();
    expect(app.sidebarVisible).toBe(false);

    app.setUnsaved(true);
    expect(app.unsaved).toBe(true);

    stop();
    expect(fake.close).toHaveBeenCalledTimes(1);
    expect(app.connection).toBe("disconnected");
  });
});
