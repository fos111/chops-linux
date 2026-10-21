import { afterEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen } from "@testing-library/svelte";
import Sidebar from "./Sidebar.svelte";
import { makeSkill, makeTool } from "$lib/test-fixtures";
import type { SidebarFilter } from "$lib/filters";

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
