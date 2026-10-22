import { afterEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen } from "@testing-library/svelte";
import Sidebar from "./Sidebar.svelte";
import { makeSkill, makeTool } from "$lib/test-fixtures";
import type { CollectionSummary } from "$lib/api";
import type { SidebarFilter as SidebarFilter } from "$lib/filters";

afterEach(cleanup);

const tools = [
  makeTool({ id: "claude", displayName: "Claude Code" }),
  makeTool({ id: "codex", displayName: "Codex" }),
  makeTool({ id: "cursor", displayName: "Cursor", isInstalled: false }),
  makeTool({ id: "aider", displayName: "Aider", listable: false }),
];

const skills = [
  makeSkill({ id: 1, name: "Alpha", toolSources: ["claude"] }),
  makeSkill({ id: 2, name: "Delta", toolSources: ["claude", "codex"] }),
  makeSkill({ id: 3, name: "Beta", kind: "agent", toolSources: ["codex"], isFavorite: true }),
  makeSkill({ id: 4, name: "Gamma", kind: "rule", toolSources: ["codex"] }),
];

function renderSidebar(filter: SidebarFilter = { type: "allSkills" }) {
  const onselect = vi.fn();
  const result = render(Sidebar, {
    props: { tools, skills, filter, onselect },
  });
  return { ...result, onselect };
}

describe("Sidebar", () => {
  it("shows library counts", () => {
    renderSidebar();
    expect(screen.getByRole("button", { name: /^Skills/ }).textContent).toContain("2");
    expect(screen.getByRole("button", { name: /^Agents/ }).textContent).toContain("1");
    expect(screen.getByRole("button", { name: /^Rules/ }).textContent).toContain("1");
    expect(screen.getByRole("button", { name: /^Favorites/ }).textContent).toContain("1");
  });

  it("lists installed, listable tools only", () => {
    renderSidebar();
    expect(screen.getByRole("button", { name: /Claude Code/ })).toBeTruthy();
    expect(screen.getByRole("button", { name: /Codex/ })).toBeTruthy();
    expect(screen.queryByRole("button", { name: /Cursor/ })).toBeNull();
    expect(screen.queryByRole("button", { name: /Aider/ })).toBeNull();
  });

  it("renders the copied tool logo for tools that have one", () => {
    const { container } = renderSidebar();
    expect(
      container.querySelector('img[src="/tool-logos/tool-claude.svg"]'),
    ).not.toBeNull();
    expect(
      container.querySelector('img[src="/tool-logos/tool-codex.svg"]'),
    ).not.toBeNull();
  });

  it("selects a tool filter on click", async () => {
    const { onselect } = renderSidebar();
    await fireEvent.click(screen.getByRole("button", { name: /Claude Code/ }));
    expect(onselect).toHaveBeenCalledWith({ type: "tool", tool: "claude" });
  });

  it("selects a library filter on click", async () => {
    const { onselect } = renderSidebar();
    await fireEvent.click(screen.getByRole("button", { name: /^Agents/ }));
    expect(onselect).toHaveBeenCalledWith({ type: "allAgents" });
  });

  it("marks the active filter", () => {
    renderSidebar({ type: "tool", tool: "claude" });
    const claude = screen.getByRole("button", { name: /Claude Code/ });
    expect(claude.getAttribute("aria-pressed")).toBe("true");
    const skillsButton = screen.getByRole("button", { name: /^Skills/ });
    expect(skillsButton.getAttribute("aria-pressed")).toBe("false");
  });
});

function makeCollection(
  overrides: Partial<CollectionSummary> = {},
): CollectionSummary {
  return {
    id: overrides.id ?? 1,
    name: overrides.name ?? "Work",
    icon: overrides.icon ?? "folder",
    sortOrder: overrides.sortOrder ?? 0,
    skillCount: overrides.skillCount ?? 2,
  };
}

describe("Sidebar collections (T16 part A)", () => {
  const collections = [
    makeCollection({ id: 1, name: "Work", skillCount: 2 }),
    makeCollection({ id: 2, name: "Later", icon: "bolt", sortOrder: 1, skillCount: 1 }),
  ];

  function renderWithCollections(
    filter: SidebarFilter = { type: "allSkills" },
    onselect = vi.fn(),
  ) {
    const oncreateCollection = vi.fn(async () => undefined);
    const ondeleteCollection = vi.fn();
    render(Sidebar, {
      props: {
        tools,
        skills,
        collections,
        filter,
        onselect,
        oncreateCollection,
        ondeleteCollection,
        onopenRegistry: vi.fn(),
        onopenSettings: vi.fn(),
      },
    });
    return { oncreateCollection, ondeleteCollection };
  }

  it("lists collections with their counts alongside the library rows", () => {
    renderWithCollections();
    const work = screen.getByRole("button", { name: /^Work/ });
    expect(work.textContent).toContain("2");
    const later = screen.getByRole("button", { name: /^Later/ });
    expect(later.textContent).toContain("1");
  });

  it("selects a collection filter on click", async () => {
    const onselect = vi.fn();
    renderWithCollections({ type: "allSkills" }, onselect);
    await fireEvent.click(screen.getByRole("button", { name: /^Work/ }));
    expect(onselect).toHaveBeenCalledWith({ type: "collection", name: "Work" });
  });

  it("marks the active collection", () => {
    renderWithCollections({ type: "collection", name: "Work" });
    expect(
      screen.getByRole("button", { name: /^Work/ }).getAttribute("aria-pressed"),
    ).toBe("true");
  });

  it("deletes a collection through its remove button", async () => {
    const handlers = renderWithCollections();
    await fireEvent.click(
      screen.getByRole("button", { name: "Delete collection Work" }),
    );
    expect(handlers.ondeleteCollection).toHaveBeenCalledWith(collections[0]);
  });

  it("opens the create popover and submits name + icon", async () => {
    const handlers = renderWithCollections();
    await fireEvent.click(screen.getByText("New Collection"));
    const nameInput = screen.getByLabelText("Collection name");
    await fireEvent.input(nameInput, { target: { value: "Ops" } });
    await fireEvent.click(screen.getByTitle("star"));
    await fireEvent.click(screen.getByText("Create"));
    await vi.waitFor(() =>
      expect(handlers.oncreateCollection).toHaveBeenCalledWith({
        name: "Ops",
        icon: "star",
      }),
    );
  });

  it("shows the macOS duplicate-name error before any request", async () => {
    const handlers = renderWithCollections();
    await fireEvent.click(screen.getByText("New Collection"));
    await fireEvent.input(screen.getByLabelText("Collection name"), {
      target: { value: "work" },
    });
    await fireEvent.click(screen.getByText("Create"));
    await screen.findByText("A collection with this name already exists");
    expect(handlers.oncreateCollection).not.toHaveBeenCalled();
  });

  it("disables Create for empty names, matching macOS", async () => {
    const handlers = renderWithCollections();
    await fireEvent.click(screen.getByText("New Collection"));
    // Create stays disabled while the name is empty/unwhitespace, so the
    // "empty" error path is unreachable in the UI (same as macOS).
    const create = screen
      .getByText("Create")
      .closest("button") as HTMLButtonElement;
    expect(create.disabled).toBe(true);
    await fireEvent.input(screen.getByLabelText("Collection name"), {
      target: { value: "   " },
    });
    expect(create.disabled).toBe(true);
    expect(handlers.oncreateCollection).not.toHaveBeenCalled();
  });

  it("surfaces a chopsd duplicate rejection in the popover", async () => {
    const oncreateCollection = vi.fn(async () => {
      throw new Error("500: duplicate key");
    });
    render(Sidebar, {
      props: {
        tools,
        skills,
        collections,
        filter: { type: "allSkills" },
        onselect: vi.fn(),
        oncreateCollection,
        ondeleteCollection: vi.fn(),
      },
    });
    await fireEvent.click(screen.getByText("New Collection"));
    await fireEvent.input(screen.getByLabelText("Collection name"), {
      target: { value: "Distinct" },
    });
    await fireEvent.click(screen.getByText("Create"));
    await screen.findByText("500: duplicate key");
  });

  it("shows the empty state without collections", () => {
    render(Sidebar, {
      props: {
        tools,
        skills,
        collections: [],
        filter: { type: "allSkills" },
        onselect: vi.fn(),
      },
    });
    expect(screen.getByText("No collections yet.")).toBeTruthy();
  });

  it("renders the discovery + settings rows", async () => {
    const onopenRegistry = vi.fn();
    const onopenSettings = vi.fn();
    render(Sidebar, {
      props: {
        tools,
        skills,
        collections,
        filter: { type: "allSkills" },
        onselect: vi.fn(),
        onopenRegistry,
        onopenSettings,
      },
    });
    await fireEvent.click(screen.getByText("Discovery"));
    await fireEvent.click(screen.getByText("Settings"));
    expect(onopenRegistry).toHaveBeenCalledTimes(1);
    expect(onopenSettings).toHaveBeenCalledTimes(1);
  });
});
