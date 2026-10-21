import { describe, expect, it } from "vitest";
import {
  buildPaletteCommands,
  filterPaletteCommands,
  fuzzyMatch,
  isPaletteShortcut,
  isSidebarShortcut,
  moveSelection,
} from "./palette";
import { makeTool } from "./test-fixtures";

const tools = [
  makeTool({ id: "claude", displayName: "Claude Code" }),
  makeTool({ id: "codex", displayName: "Codex" }),
  makeTool({ id: "cursor", displayName: "Cursor", isInstalled: false }),
  makeTool({ id: "aider", displayName: "Aider", listable: false }),
];

describe("buildPaletteCommands", () => {
  it("lists the library views plus installed, listable tools", () => {
    const commands = buildPaletteCommands(tools);
    expect(commands.map((command) => command.title)).toEqual([
      "Skills",
      "Agents",
      "Rules",
      "Favorites",
      "Claude Code",
      "Codex",
    ]);
    expect(commands.every((command) => command.category === "Navigate")).toBe(true);
  });

  it("carries the navigation action for each command", () => {
    const claude = buildPaletteCommands(tools).find(
      (command) => command.title === "Claude Code",
    );
    expect(claude?.action).toEqual({
      type: "navigate",
      filter: { type: "tool", tool: "claude" },
    });
    expect(claude?.toolId).toBe("claude");
  });
});

describe("fuzzyMatch", () => {
  it("matches case-insensitive substrings", () => {
    expect(fuzzyMatch("claude", "Claude Code")).not.toBeNull();
    expect(fuzzyMatch("CODE", "Claude Code")).not.toBeNull();
  });

  it("matches subsequences for abbreviations", () => {
    const match = fuzzyMatch("cc", "Claude Code");
    expect(match).not.toBeNull();
    expect(match?.positions).toEqual([0, 7]);
  });

  it("rejects strings missing a character", () => {
    expect(fuzzyMatch("czz", "Claude Code")).toBeNull();
    expect(fuzzyMatch("aider", "Claude Code")).toBeNull();
  });

  it("ranks prefix matches above loose subsequences", () => {
    const prefix = fuzzyMatch("cl", "Claude Code")?.score ?? 0;
    const loose = fuzzyMatch("cc", "Claude Code")?.score ?? 0;
    expect(prefix).toBeGreaterThan(loose);
  });

  it("treats an empty query as a neutral match", () => {
    expect(fuzzyMatch("", "Claude Code")).toEqual({ score: 0, positions: [] });
    expect(fuzzyMatch("   ", "Claude Code")).toEqual({ score: 0, positions: [] });
  });
});

describe("filterPaletteCommands", () => {
  const commands = buildPaletteCommands(tools);

  it("returns every command for an empty query", () => {
    expect(filterPaletteCommands(commands, "")).toHaveLength(6);
    expect(filterPaletteCommands(commands, "  ")).toHaveLength(6);
  });

  it("jumps to a tool from a prefix", () => {
    const filtered = filterPaletteCommands(commands, "cla");
    expect(filtered.map((command) => command.title)).toEqual(["Claude Code"]);
  });

  it("filters on category, mirroring the macOS palette", () => {
    expect(filterPaletteCommands(commands, "nav")).toHaveLength(6);
  });

  it("returns no commands when nothing matches", () => {
    expect(filterPaletteCommands(commands, "zzzz")).toEqual([]);
  });
});

describe("moveSelection", () => {
  it("clamps like the macOS palette", () => {
    expect(moveSelection(0, 1, 3)).toBe(1);
    expect(moveSelection(0, -1, 3)).toBe(0);
    expect(moveSelection(2, 1, 3)).toBe(2);
    expect(moveSelection(0, 1, 0)).toBe(0);
  });
});

describe("keyboard shortcuts", () => {
  it("recognizes Ctrl+K / Meta+K", () => {
    expect(isPaletteShortcut({ key: "k", ctrlKey: true, metaKey: false, altKey: false })).toBe(true);
    expect(isPaletteShortcut({ key: "K", ctrlKey: false, metaKey: true, altKey: false })).toBe(true);
    expect(isPaletteShortcut({ key: "k", ctrlKey: false, metaKey: false, altKey: false })).toBe(false);
    expect(isPaletteShortcut({ key: "k", ctrlKey: true, metaKey: false, altKey: true })).toBe(false);
  });

  it("recognizes Ctrl+B", () => {
    expect(isSidebarShortcut({ key: "b", ctrlKey: true, metaKey: false, altKey: false })).toBe(true);
    expect(isSidebarShortcut({ key: "k", ctrlKey: true, metaKey: false, altKey: false })).toBe(false);
  });
});
