import { afterEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen } from "@testing-library/svelte";
import SkillMetadataBar from "./SkillMetadataBar.svelte";
import { makeSkill, makeTool } from "$lib/test-fixtures";
import type { CollectionSummary } from "$lib/api";

const tools = [makeTool({ id: "claude", displayName: "Claude Code" })];

const collections: CollectionSummary[] = [
  { id: 1, name: "Work", icon: "folder", sortOrder: 0, skillCount: 1 },
  { id: 2, name: "Later", icon: "bolt", sortOrder: 1, skillCount: 0 },
];

afterEach(cleanup);

function baseSkill(overrides = {}) {
  return makeSkill({
    collections: [
      { id: 1, name: "Work", icon: "folder", sortOrder: 0 },
    ],
    ...overrides,
  });
}

describe("SkillMetadataBar collection picker (T16 part A)", () => {
  it("shows the tray picker button only when collections are wired", () => {
    render(SkillMetadataBar, {
      props: { skill: baseSkill(), tools },
    });
    expect(screen.queryByRole("button", { name: "Collections" })).toBeNull();
  });

  it("opens the macOS collectionPickerContent popover", async () => {
    const ontoggleCollection = vi.fn();
    render(SkillMetadataBar, {
      props: { skill: baseSkill(), tools, collections, ontoggleCollection },
    });
    await fireEvent.click(screen.getByRole("button", { name: "Collections" }));
    expect(screen.getByText("Work")).toBeTruthy();
    expect(screen.getByText("Later")).toBeTruthy();
  });

  it("marks assigned collections and toggles off on click", async () => {
    const ontoggleCollection = vi.fn();
    render(SkillMetadataBar, {
      props: { skill: baseSkill(), tools, collections, ontoggleCollection },
    });
    await fireEvent.click(screen.getByRole("button", { name: "Collections" }));
    await fireEvent.click(screen.getByRole("menuitem", { name: /Work/ }));
    expect(ontoggleCollection).toHaveBeenCalledWith(collections[0]);
  });

  it("shows unassigned collections without a check mark", async () => {
    render(SkillMetadataBar, {
      props: {
        skill: baseSkill(),
        tools,
        collections: [{ ...collections[1] }],
        ontoggleCollection: vi.fn(),
      },
    });
    await fireEvent.click(screen.getByRole("button", { name: "Collections" }));
    expect(screen.getByRole("menuitem", { name: /Later/ })).toBeTruthy();
    expect(screen.queryByText("✓")).toBeNull();
  });

  it("marks exactly the assigned collections", async () => {
    const ontoggleCollection = vi.fn();
    render(SkillMetadataBar, {
      props: { skill: baseSkill(), tools, collections, ontoggleCollection },
    });
    await fireEvent.click(screen.getByRole("button", { name: "Collections" }));
    const checks = screen.getAllByText("✓");
    expect(checks).toHaveLength(1);
    expect(screen.getByRole("menuitem", { name: /Later/ })).toBeTruthy();
  });

  it("shows the macOS empty state", async () => {
    render(SkillMetadataBar, {
      props: {
        skill: baseSkill(),
        tools,
        collections: [],
        ontoggleCollection: vi.fn(),
      },
    });
    await fireEvent.click(screen.getByRole("button", { name: "Collections" }));
    expect(screen.getByText("No collections yet")).toBeTruthy();
  });
});
