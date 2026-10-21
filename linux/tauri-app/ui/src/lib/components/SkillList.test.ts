import { afterEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen } from "@testing-library/svelte";
import SkillList from "./SkillList.svelte";
import { makeSkill } from "$lib/test-fixtures";

afterEach(cleanup);

const duplicate = makeSkill({
  id: 1,
  name: "dup-a",
  filePath: "/home/test/.claude/skills/dup-a-md",
  installedPaths: [
    "/home/test/.claude/skills/dup-a-md",
    "/home/test/.codex/skills/dup-a-md",
  ],
  toolSources: ["claude", "codex"],
});

const agent = makeSkill({
  id: 2,
  name: "reviewer",
  kind: "agent",
  isFavorite: true,
  toolSources: ["claude"],
});

function renderList(
  overrides: Partial<{
    skills: typeof duplicate[];
    searchText: string;
    error: string | null;
    loading: boolean;
    showTypeBadge: boolean;
    selectedId: number | null;
  }> = {},
) {
  const onselect = vi.fn();
  const onsearch = vi.fn();
  const onretry = vi.fn();
  const ontoggleSidebar = vi.fn();
  const result = render(SkillList, {
    props: {
      skills: [duplicate, agent],
      title: "Skills",
      searchText: "",
      selectedId: duplicate.id,
      showTypeBadge: false,
      loading: false,
      error: null,
      onselect,
      onsearch,
      onretry,
      ontoggleSidebar,
      ...overrides,
    },
  });
  return { ...result, onselect, onsearch, onretry, ontoggleSidebar };
}

describe("SkillList", () => {
  it("renders one row per skill", () => {
    const { container } = renderList();
    expect(container.querySelectorAll(".skill-row")).toHaveLength(2);
    expect(screen.getByText("dup-a")).toBeTruthy();
    expect(screen.getByText("reviewer")).toBeTruthy();
  });

  it("marks the selected row", () => {
    const { container } = renderList({ selectedId: agent.id });
    const rows = container.querySelectorAll(".skill-row");
    expect(rows[0].getAttribute("aria-current")).toBeNull();
    expect(rows[1].getAttribute("aria-current")).toBe("true");
  });

  it("shows a duplicate badge with the install count", () => {
    renderList();
    expect(screen.getByText("×2")).toBeTruthy();
    expect(screen.getByLabelText("Installed in 2 locations")).toBeTruthy();
  });

  it("shows a type badge when the list mixes kinds", () => {
    const { container } = renderList({ showTypeBadge: true });
    const titles = Array.from(container.querySelectorAll(".type-icon")).map((el) =>
      el.getAttribute("title"),
    );
    expect(titles).toEqual(["Skill", "Agent"]);
  });

  it("emits search text changes", async () => {
    const { onsearch } = renderList();
    const input = screen.getByLabelText("Search skills");
    await fireEvent.input(input, { target: { value: "review" } });
    expect(onsearch).toHaveBeenCalledWith("review");
  });

  it("renders the macOS empty state", () => {
    renderList({ skills: [] });
    expect(screen.getByText("No Skills")).toBeTruthy();
    expect(screen.getByText("No items match the current filter.")).toBeTruthy();
  });

  it("explains an empty search result", () => {
    renderList({ skills: [], searchText: "nothing" });
    expect(screen.getByText("No items match the current search.")).toBeTruthy();
  });

  it("shows a daemon error with retry", async () => {
    const { onretry } = renderList({
      skills: [],
      error: "chopsd is not reachable at http://127.0.0.1:47115",
    });
    expect(screen.getByRole("alert").textContent).toContain("not reachable");
    await fireEvent.click(screen.getByRole("button", { name: "Retry" }));
    expect(onretry).toHaveBeenCalledTimes(1);
  });

  it("selects a row and toggles the sidebar", async () => {
    const { onselect, ontoggleSidebar } = renderList();
    await fireEvent.click(screen.getByText("reviewer"));
    expect(onselect).toHaveBeenCalledWith(agent.id);

    await fireEvent.click(screen.getByRole("button", { name: "Toggle sidebar" }));
    expect(ontoggleSidebar).toHaveBeenCalledTimes(1);
  });
});
