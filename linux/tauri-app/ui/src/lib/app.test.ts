import { afterEach, describe, expect, it, vi } from "vitest";
import {
  type AssistRequest,
  type ChopsApi,
  type CollectionSummary,
  type EventHandlers,
  type RegistrySkill,
  type RemoteBrowseResponse,
  type RemoteInstallRequest,
  type RemoteServer,
  type RemoteServerRequest,
  type Settings,
  type Skill,
  type Tool,
} from "./api";
import { ChopsApp } from "./app.svelte.js";
import { applyTheme } from "./theme";
import { makeSettings, makeSkill, makeTool } from "./test-fixtures";

function makeCollection(overrides: Partial<CollectionSummary> = {}): CollectionSummary {
  return {
    id: overrides.id ?? 1,
    name: overrides.name ?? "collection",
    icon: overrides.icon ?? "folder",
    sortOrder: overrides.sortOrder ?? 0,
    skillCount: overrides.skillCount ?? 0,
  };
}

function makeRemoteServer(overrides: Partial<RemoteServer> = {}): RemoteServer {
  return {
    id: overrides.id ?? "srv-1",
    label: overrides.label ?? "Production",
    host: overrides.host ?? "192.168.1.100",
    port: overrides.port ?? 22,
    username: overrides.username ?? "root",
    skillsBasePath: overrides.skillsBasePath ?? "~/.hermes/skills",
    sshKeyPath: overrides.sshKeyPath ?? null,
    lastSyncDate: overrides.lastSyncDate ?? null,
    lastSyncError: overrides.lastSyncError ?? null,
  };
}

function makeRegistrySkill(overrides: Partial<RegistrySkill> = {}): RegistrySkill {
  return {
    skillId: overrides.skillId ?? "demo-skill",
    name: overrides.name ?? "Demo Skill",
    installs: overrides.installs ?? 1000,
    source: overrides.source ?? "demo/repo",
    isOfficial: overrides.isOfficial ?? false,
  };
}

interface FakeClient {
  client: ChopsApi;
  handlers: EventHandlers[];
  close: ReturnType<typeof vi.fn>;
  listTools: ReturnType<typeof vi.fn>;
  listSkills: ReturnType<typeof vi.fn>;
  getSkill: ReturnType<typeof vi.fn>;
  updateSkill: ReturnType<typeof vi.fn>;
  createSkill: ReturnType<typeof vi.fn>;
  listCollections: ReturnType<typeof vi.fn>;
  createCollection: ReturnType<typeof vi.fn>;
  deleteCollection: ReturnType<typeof vi.fn>;
  getCollection: ReturnType<typeof vi.fn>;
  addCollectionSkill: ReturnType<typeof vi.fn>;
  removeCollectionSkill: ReturnType<typeof vi.fn>;
  listTrending: ReturnType<typeof vi.fn>;
  searchRegistry: ReturnType<typeof vi.fn>;
  installRegistry: ReturnType<typeof vi.fn>;
  assist: ReturnType<typeof vi.fn>;
  acceptAssist: ReturnType<typeof vi.fn>;
  rejectAssist: ReturnType<typeof vi.fn>;
  listRemoteServers: ReturnType<typeof vi.fn>;
  createRemoteServer: ReturnType<typeof vi.fn>;
  updateRemoteServer: ReturnType<typeof vi.fn>;
  deleteRemoteServer: ReturnType<typeof vi.fn>;
  browseRemote: ReturnType<typeof vi.fn>;
  installRemote: ReturnType<typeof vi.fn>;
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
  let collections: CollectionSummary[] = [
    makeCollection({ id: 1, name: "Work" }),
  ];
  const handlers: EventHandlers[] = [];
  const close = vi.fn();

  const listTools = vi.fn(async () => tools);
  const listSkills = vi.fn(async () => skills);
  const getSkill = vi.fn(
    async (id: number) => skills.find((skill) => skill.id === id) ?? skills[0],
  );
  const updateSkill = vi.fn(async (id: number, content: string) => ({
    ...(skills.find((skill) => skill.id === id) ?? skills[0]),
    content,
  }));
  const createSkill = vi.fn(async (request: { name: string; tool: string; kind?: string }) =>
    makeSkill({
      name: request.name,
      toolSources: [request.tool],
      kind: request.kind ?? "skill",
    }),
  );
  const listCollections = vi.fn(async () => collections);
  const createCollection = vi.fn(async (request: { name: string; icon?: string }) => {
    const created = makeCollection({
      id: collections.length + 1,
      name: request.name,
      icon: request.icon ?? "folder",
      sortOrder: collections.length,
      skillCount: 0,
    });
    collections = [...collections, created];
    return created;
  });
  const deleteCollection = vi.fn(async (id: number) => {
    collections = collections.filter((collection) => collection.id !== id);
    return { deleted: true };
  });
  const getCollection = vi.fn(async (id: number) => ({
    collection:
      collections.find((collection) => collection.id === id) ?? makeCollection({ id }),
    skills: skills.filter((skill) =>
      skill.collections.some((ref) =>
        collections.some(
          (collection) =>
            collection.id === id && collection.name === ref.name,
        ),
      ),
    ),
  }));
  const addCollectionSkill = vi.fn(async (collectionId: number, skillId: number) => {
    const skill = skills.find((row) => row.id === skillId);
    const collection = collections.find((row) => row.id === collectionId);
    if (skill && collection && !skill.collections.some((ref) => ref.name === collection.name)) {
      skill.collections = [...skill.collections, { id: collection.id, name: collection.name, icon: collection.icon, sortOrder: collection.sortOrder }];
    }
    return { added: true };
  });
  const removeCollectionSkill = vi.fn(async (collectionId: number, skillId: number) => {
    const skill = skills.find((row) => row.id === skillId);
    const collection = collections.find((row) => row.id === collectionId);
    if (skill && collection) {
      skill.collections = skill.collections.filter((ref) => ref.name !== collection.name);
    }
    return { removed: true };
  });
  const listTrending = vi.fn(async () => [makeRegistrySkill()]);
  const searchRegistry = vi.fn(async (q: string) =>
    q.length >= 2 ? [makeRegistrySkill({ skillId: `search-${q}` })] : [],
  );
  const installRegistry = vi.fn(async (request: { skillId: string }) => ({
    installed: true,
    skillName: request.skillId,
    path: "/home/test/.agents/skills/demo-skill/SKILL.md",
    targets: ["claude"],
    skill: makeSkill({ id: 9, name: request.skillId, toolSources: ["claude"] }),
  }));
  const assist = vi.fn(async (request: AssistRequest) => ({
    pendingId: "pending-1",
    summary: "Updated the heading.",
    fullFile: "# Alpha\n\nAccepted body.",
    path: request.skillId === 1
      ? "/home/test/.claude/skills/skill-1.md"
      : "/home/test/.claude/skills/other.md",
    agent: request.agent ?? "claude",
    skillId: request.skillId,
  }));
  const acceptAssist = vi.fn(async (pendingId: string) => ({
    accepted: true,
    pendingId,
    path: "/home/test/.claude/skills/skill-1.md",
    skill: makeSkill({
      id: 1,
      name: "Alpha",
      content: "# Alpha\n\nAccepted body.",
      toolSources: ["claude"],
    }),
  }));
  const rejectAssist = vi.fn(async (pendingId: string) => ({
    rejected: true,
    pendingId,
  }));
  let remoteServers = [makeRemoteServer()];
  const listRemoteServers = vi.fn(async () => remoteServers);
  const createRemoteServer = vi.fn(async (request: RemoteServerRequest) => {
    const created = makeRemoteServer({
      id: `srv-${remoteServers.length + 1}`,
      label: request.label,
      host: request.host,
      port: request.port ?? 22,
      username: request.username,
      skillsBasePath: request.skillsBasePath,
      sshKeyPath: request.sshKeyPath ?? null,
    });
    remoteServers = [...remoteServers, created];
    return created;
  });
  const updateRemoteServer = vi.fn(
    async (id: string, request: RemoteServerRequest) => {
      const updated = makeRemoteServer({
        id,
        label: request.label,
        host: request.host,
        port: request.port ?? 22,
        username: request.username,
        skillsBasePath: request.skillsBasePath,
        sshKeyPath: request.sshKeyPath ?? null,
      });
      remoteServers = remoteServers.map((row) => (row.id === id ? updated : row));
      return updated;
    },
  );
  const deleteRemoteServer = vi.fn(async (id: string) => {
    remoteServers = remoteServers.filter((row) => row.id !== id);
    return { deleted: true };
  });
  const browseRemote = vi.fn(
    async (serverId: string): Promise<RemoteBrowseResponse> => ({
      serverId,
      skills: [
        {
          path: "skills/r-one/SKILL.md",
          name: "r-one",
          description: "remote fixture one",
          content: "# R One",
        },
      ],
      lastSyncDate: "2026-10-22T12:00:00Z",
    }),
  );
  const installRemote = vi.fn(async (request: RemoteInstallRequest) => ({
    installed: true,
    skillName: "r-one",
    path: "/home/test/.agents/skills/r-one/SKILL.md",
    targets: ["claude"],
    skill: makeSkill({ id: 12, name: "r-one", toolSources: ["claude"] }),
  }));
  const getSettings = vi.fn(async () => settings);
  const updateSettings = vi.fn(async (patch: Partial<Settings>) => ({
    ...settings,
    ...patch,
  }));

  const client: ChopsApi = {
    listTools,
    listSkills,
    getSkill,
    updateSkill,
    createSkill,
    listCollections,
    createCollection,
    deleteCollection,
    getCollection,
    addCollectionSkill,
    removeCollectionSkill,
    listTrending,
    searchRegistry,
    installRegistry,
    assist,
    acceptAssist,
    rejectAssist,
    listRemoteServers,
    createRemoteServer,
    updateRemoteServer,
    deleteRemoteServer,
    browseRemote,
    installRemote,
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
    getSkill,
    updateSkill,
    createSkill,
    listCollections,
    createCollection,
    deleteCollection,
    getCollection,
    addCollectionSkill,
    removeCollectionSkill,
    listTrending,
    searchRegistry,
    installRegistry,
    assist,
    acceptAssist,
    rejectAssist,
    listRemoteServers,
    createRemoteServer,
    updateRemoteServer,
    deleteRemoteServer,
    browseRemote,
    installRemote,
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

describe("collections (T16 part A)", () => {
  it("loads sorted collections during bootstrap", async () => {
    const fake = makeFakeClient({
      listCollections: vi.fn(async () => [
        makeCollection({ id: 2, sortOrder: 1, name: "Later" }),
        makeCollection({ id: 1, sortOrder: 0, name: "First" }),
      ]),
    });
    const app = createApp(fake);
    app.start();
    await app.ready;
    expect(app.collections.map((c) => c.name)).toEqual(["First", "Later"]);
    app.stop();
  });

  it("records a bootstrap failure in its own error lane", async () => {
    const fake = makeFakeClient({
      listCollections: vi.fn(async () => {
        throw new Error("collections 500");
      }),
    });
    const app = createApp(fake);
    app.start();
    await app.ready;
    expect(app.collections).toEqual([]);
    expect(app.collectionsError).toContain("collections 500");
    app.stop();
  });

  it("creates through chopsd and refreshes the sidebar list", async () => {
    const fake = makeFakeClient({ listCollections: vi.fn(async () => []) });
    const fakeCreate = fake.client.createCollection as ReturnType<typeof vi.fn>;
    const app = createApp(fake);
    app.start();
    await app.ready;

    await app.createCollection("New C", "star");
    expect(fakeCreate).toHaveBeenCalledWith({ name: "New C", icon: "star" });
    app.stop();
  });

  it("surfaces create failures", async () => {
    const fake = makeFakeClient();
    (fake.client.createCollection as ReturnType<typeof vi.fn>).mockRejectedValue(
      new Error("duplicate name"),
    );
    const app = createApp(fake);
    app.start();
    await app.ready;

    await expect(app.createCollection("X", "folder")).rejects.toThrow(
      "duplicate name",
    );
    app.stop();
  });

  it("deleting the collection backing the active filter resets to Skills", async () => {
    const app = createApp(makeFakeClient());
    app.start();
    await app.ready;
    app.setFilter({ type: "collection", name: "Work" });
    await sleep(10);
    expect(app.filter).toEqual({ type: "collection", name: "Work" });

    await app.deleteCollection(1);
    expect(app.filter).toEqual({ type: "allSkills" });
    app.stop();
  });

  it("deleting an unrelated collection keeps the current filter", async () => {
    const fake = makeFakeClient({
      listCollections: vi.fn(async () => [
        makeCollection({ id: 1, name: "Work" }),
        makeCollection({ id: 2, name: "Keep", sortOrder: 1 }),
      ]),
    });
    const app = createApp(fake);
    app.start();
    await app.ready;

    app.setFilter({ type: "collection", name: "Keep" });
    await sleep(10);

    await app.deleteCollection(1);
    expect(app.filter).toEqual({ type: "collection", name: "Keep" });
    app.setFilter({ type: "collection", name: "Work" });
    await sleep(10);
    app.stop();
  });

  it("collection filters load the server-authoritative detail", async () => {
    const fake = makeFakeClient();
    const app = createApp(fake);
    app.start();
    await app.ready;

    app.setFilter({ type: "collection", name: "Work" });
    await sleep(10);
    expect(fake.getCollection).toHaveBeenCalledWith(1);
    expect(app.collectionDetail).not.toBeNull();
    app.stop();
  });

  it("records detail fetch failures without masking the fallback", async () => {
    const fake = makeFakeClient({
      getCollection: vi.fn(async () => {
        throw new Error("detail 500");
      }),
    });
    const app = createApp(fake);
    app.start();
    await app.ready;

    app.setFilter({ type: "collection", name: "Work" });
    await sleep(10);
    expect(app.collectionDetail).toBeNull();
    expect(app.collectionDetailError).toContain("detail 500");
    app.stop();
  });

  it("adds and removes memberships, then refreshes skills and counts", async () => {
    const fake = makeFakeClient();
    const app = createApp(fake);
    app.start();
    await app.ready;

    const collection = { ...makeCollection(), id: 1 };
    const added = await app.addToCollection(1, collection);
    expect(fake.addCollectionSkill).toHaveBeenCalledWith(1, 1);
    expect(added).toBe(true);

    const removed = await app.removeFromCollection(1, collection);
    expect(fake.removeCollectionSkill).toHaveBeenCalledWith(1, 1);
    expect(removed).toBe(true);
    app.stop();
  });

  it("toggles membership off when the skill already belongs", async () => {
    const fake = makeFakeClient();
    // Skill 1 carries the collection ref from the store.
    const member = fake.skills[1]; // created with collections: []
    void member;
    const app = createApp(fake);
    app.start();
    await app.ready;

    app.skills = [
      {
        ...fake.skills[1],
        collections: [
          { id: 1, name: "Work", icon: "folder", sortOrder: 0 },
        ],
      },
      ...fake.skills.filter((skill) => skill.id !== 1),
    ];
    await app.toggleCollectionMembership(
      app.skills[0],
      makeCollection({ id: 1, name: "Work" }),
    );
    expect(fake.removeCollectionSkill).toHaveBeenCalled();
    app.stop();
  });
});

describe("registry install (T16 part A)", () => {
  it("installs through chopsd and refreshes the library", async () => {
    const fake = makeFakeClient();
    const app = createApp(fake);
    app.start();
    await app.ready;

    const before = fake.listSkills.mock.calls.length;
    await app.installRegistrySkill({
      skillId: "demo",
      name: "Demo",
      source: "demo/repo",
      targets: ["claude"],
    });
    expect(fake.installRegistry).toHaveBeenCalled();
    expect(fake.listSkills.mock.calls.length).toBeGreaterThan(before);
    app.stop();
  });

  it("shares the fixed trending/search passthroughs", async () => {
    const fake = makeFakeClient();
    const app = createApp(fake);
    app.start();
    await app.ready;

    await app.fetchTrending();
    expect(fake.listTrending).toHaveBeenCalled();
    await app.searchRegistry("demo");
    expect(fake.searchRegistry).toHaveBeenCalledWith("demo");
    app.stop();
  });
});

describe("settings persistence (T16 part A)", () => {
  it("saves scan-root overrides through PUT /api/settings", async () => {
    const fake = makeFakeClient();
    const app = createApp(fake);
    app.start();
    await app.ready;

    await app.saveSettings({ scanRoots: ["/home/test/dev"] });
    expect(fake.updateSettings).toHaveBeenCalledWith({
      scanRoots: ["/home/test/dev"],
    });
    expect(app.settings?.scanRoots).toEqual(["/home/test/dev"]);
    app.stop();
  });

  it("surfaces save failures (no silent revert)", async () => {
    const fake = makeFakeClient();
    fake.updateSettings.mockRejectedValueOnce(new Error("PUT failed"));
    const app = createApp(fake);
    app.start();
    await app.ready;

    await expect(app.saveSettings({ includePluginSkills: true })).rejects.toThrow(
      "PUT failed",
    );
    expect(app.settingsError).toContain("PUT failed");
    app.stop();
  });
});

describe("assist wiring (T16 part B)", () => {
  it("sends the compose turn and applies the accepted skill row", async () => {
    const fake = makeFakeClient();
    const app = createApp(fake);
    app.start();
    await app.ready;

    const request = {
      skillId: 1,
      prompt: "Tighten the wording",
      agent: "codex" as const,
      content: "# Alpha\n",
    };
    const response = await app.assist(request);
    expect(fake.assist).toHaveBeenCalledWith(request);
    expect(response.pendingId).toBe("pending-1");

    app.setUnsaved(true);
    const accepted = await app.acceptAssist("pending-1");
    expect(fake.acceptAssist).toHaveBeenCalledWith("pending-1");
    expect(accepted.accepted).toBe(true);
    expect(app.skills.find((skill) => skill.id === 1)?.content).toContain(
      "Accepted body",
    );
    expect(app.unsaved).toBe(false);
    app.stop();
  });

  it("passes reject through to the pending-write discard route", async () => {
    const fake = makeFakeClient();
    const app = createApp(fake);
    app.start();
    await app.ready;

    await expect(app.rejectAssist("pending-1")).resolves.toEqual({
      rejected: true,
      pendingId: "pending-1",
    });
    expect(fake.rejectAssist).toHaveBeenCalledWith("pending-1");
    app.stop();
  });
});

describe("remote server wiring (T16 part B)", () => {
  it("lists, creates, updates, and deletes through the SSH CRUD routes", async () => {
    const fake = makeFakeClient();
    const app = createApp(fake);
    app.start();
    await app.ready;

    await expect(app.listRemoteServers()).resolves.toHaveLength(1);
    const request: RemoteServerRequest = {
      label: "Staging",
      host: "10.0.0.5",
      port: 2222,
      username: "deploy",
      skillsBasePath: "~/.hermes/skills",
    };
    const created = await app.createRemoteServer(request);
    expect(fake.createRemoteServer).toHaveBeenCalledWith(request);
    expect(created.label).toBe("Staging");

    const updated = await app.updateRemoteServer(created.id, {
      ...request,
      label: "Staging 2",
    });
    expect(fake.updateRemoteServer).toHaveBeenCalledWith(created.id, {
      ...request,
      label: "Staging 2",
    });
    expect(updated.label).toBe("Staging 2");

    await app.deleteRemoteServer(created.id);
    expect(fake.deleteRemoteServer).toHaveBeenCalledWith(created.id);
    app.stop();
  });

  it("browses and installs remote skills, then refreshes the library", async () => {
    const fake = makeFakeClient();
    const app = createApp(fake);
    app.start();
    await app.ready;

    const browse = await app.browseRemote("srv-1");
    expect(fake.browseRemote).toHaveBeenCalledWith("srv-1");
    expect(browse.skills.map((skill) => skill.name)).toEqual(["r-one"]);

    const before = fake.listSkills.mock.calls.length;
    const installed = await app.installRemote({
      serverId: "srv-1",
      remotePath: "skills/r-one/SKILL.md",
    });
    expect(fake.installRemote).toHaveBeenCalledWith({
      serverId: "srv-1",
      remotePath: "skills/r-one/SKILL.md",
    });
    expect(installed.installed).toBe(true);
    expect(fake.listSkills.mock.calls.length).toBeGreaterThan(before);
    app.stop();
  });
});
