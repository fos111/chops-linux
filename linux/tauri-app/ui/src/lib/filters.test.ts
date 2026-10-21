import { describe, expect, it } from "vitest";
import {
  countByKind,
  duplicateCount,
  filterKey,
  filterSkills,
  filterTitle,
  installedTools,
  matchesSearch,
  projectName,
  reconcileSelection,
  sortSkills,
  toolCount,
  type ItemKind,
  type SidebarFilter,
} from "./filters";
import { makeSkill, makeTool } from "./test-fixtures";

const alpha = makeSkill({
  id: 1,
  name: "Alpha",
  description: "The first skill",
  content: "# Alpha\nshared needle",
  toolSources: ["claude"],
  isFavorite: true,
});

const beta = makeSkill({
  id: 2,
  name: "beta",
  description: "An agent for reviews",
  content: "# beta",
  toolSources: ["codex"],
  kind: "agent",
});

const gamma = makeSkill({
  id: 3,
  name: "Gamma",
  description: "A cursor rule",
  content: "rule body",
  toolSources: ["cursor"],
  kind: "rule",
});

const delta = makeSkill({
  id: 4,
  name: "Delta",
  description: "Only matches the body",
  content: "unique-word-in-content",
  toolSources: ["claude", "codex"],
  installedPaths: [
    "/home/test/.claude/skills/delta.md",
    "/home/test/.codex/skills/delta.md",
  ],
});

const projectSkill = makeSkill({
  id: 5,
  name: "Epsilon",
  filePath: "/home/test/dev/my-project/.claude/skills/epsilon.md",
  isGlobal: false,
  toolSources: ["claude"],
});

const skills = [alpha, beta, gamma, delta, projectSkill];

function visibleNames(
  filter: SidebarFilter,
  search = "",
  kind: ItemKind | null = null,
) {
  return filterSkills(skills, filter, search, kind).map((skill) => skill.name);
}

describe("filterSkills", () => {
  it("splits the library by item kind", () => {
    expect(visibleNames({ type: "allSkills" })).toEqual([
      "Alpha",
      "Delta",
      "Epsilon",
    ]);
    expect(visibleNames({ type: "allAgents" })).toEqual(["beta"]);
    expect(visibleNames({ type: "allRules" })).toEqual(["Gamma"]);
  });

  it("filters favorites", () => {
    expect(visibleNames({ type: "favorites" })).toEqual(["Alpha"]);
  });

  it("filters by tool source, including multi-tool rows", () => {
    expect(visibleNames({ type: "tool", tool: "claude" })).toEqual([
      "Alpha",
      "Delta",
      "Epsilon",
    ]);
    expect(visibleNames({ type: "tool", tool: "codex" })).toEqual(["beta", "Delta"]);
  });

  it("applies the in-tool kind filter when present", () => {
    expect(visibleNames({ type: "tool", tool: "claude" }, "", "skill")).toEqual([
      "Alpha",
      "Delta",
      "Epsilon",
    ]);
    expect(visibleNames({ type: "tool", tool: "claude" }, "", "rule")).toEqual([]);
  });

  it("filters collections and remote servers", () => {
    const collected = makeSkill({
      id: 6,
      name: "Collected",
      collections: [{ id: 1, name: "Favorites", icon: "star", sortOrder: 0 }],
    });
    const remote = makeSkill({
      id: 7,
      name: "Remote",
      remoteServerID: "srv-1",
    });
    const pool = [collected, remote];
    expect(
      filterSkills(pool, { type: "collection", name: "Favorites" }).map((s) => s.name),
    ).toEqual(["Collected"]);
    expect(
      filterSkills(pool, { type: "server", id: "srv-1" }).map((s) => s.name),
    ).toEqual(["Remote"]);
  });

  it("search matches name, description, and raw content case-insensitively", () => {
    expect(visibleNames({ type: "allSkills" }, "alp")).toEqual(["Alpha"]);
    expect(visibleNames({ type: "allSkills" }, "FIRST SKILL")).toEqual(["Alpha"]);
    expect(visibleNames({ type: "allSkills" }, "unique-word")).toEqual(["Delta"]);
    expect(visibleNames({ type: "allSkills" }, "no such text")).toEqual([]);
  });

  it("ignores whitespace-only searches", () => {
    expect(visibleNames({ type: "allSkills" }, "   ")).toEqual([
      "Alpha",
      "Delta",
      "Epsilon",
    ]);
  });

  it("sorts by name with the macOS query order", () => {
    const unordered = [
      makeSkill({ id: 20, name: "zeta" }),
      makeSkill({ id: 21, name: "Alpha" }),
      makeSkill({ id: 22, name: "beta" }),
    ];
    expect(sortSkills(unordered).map((skill) => skill.name)).toEqual([
      "Alpha",
      "beta",
      "zeta",
    ]);
  });
});

describe("search", () => {
  it("matches on each searchable field", () => {
    expect(matchesSearch(alpha, "alpha")).toBe(true);
    expect(matchesSearch(alpha, "first")).toBe(true);
    expect(matchesSearch(alpha, "needle")).toBe(true);
    expect(matchesSearch(alpha, "gamma")).toBe(false);
  });
});

describe("library counts", () => {
  it("counts each kind and favorites", () => {
    expect(countByKind(skills)).toEqual({
      skill: 3,
      agent: 1,
      rule: 1,
      favorite: 1,
    });
  });

  it("counts a tool across multi-tool skills", () => {
    expect(toolCount(skills, "codex")).toBe(2);
    expect(toolCount(skills, "cursor")).toBe(1);
  });
});

describe("installedTools", () => {
  it("keeps only listable, installed tools", () => {
    const tools = [
      makeTool({ id: "claude", displayName: "Claude Code" }),
      makeTool({ id: "codex", displayName: "Codex", isInstalled: false }),
      makeTool({ id: "aider", displayName: "Aider", isInstalled: true, listable: false }),
      makeTool({ id: "custom", displayName: "Custom", isInstalled: true, listable: false }),
    ];
    expect(installedTools(tools).map((tool) => tool.id)).toEqual(["claude"]);
  });
});

describe("selection reconciliation", () => {
  it("keeps a selection that is still visible", () => {
    expect(reconcileSelection([alpha, delta], alpha.id)).toBe(alpha.id);
  });

  it("falls back to the first visible row", () => {
    expect(reconcileSelection([delta, alpha], beta.id)).toBe(delta.id);
  });

  it("clears the selection for an empty list", () => {
    expect(reconcileSelection([], alpha.id)).toBeNull();
  });
});

describe("row metadata", () => {
  it("uses the path component before the dot-directory as project name", () => {
    expect(projectName(projectSkill)).toBe("my-project");
    expect(projectName(alpha)).toBeNull();
  });

  it("counts duplicate install locations", () => {
    expect(duplicateCount(alpha)).toBe(1);
    expect(duplicateCount(delta)).toBe(2);
  });
});

describe("filter keys and titles", () => {
  it("maps filters to stable keys", () => {
    expect(filterKey({ type: "allSkills" })).toBe("allSkills");
    expect(filterKey({ type: "tool", tool: "claude" })).toBe("tool:claude");
    expect(filterKey({ type: "collection", name: "Mine" })).toBe("collection:Mine");
    expect(filterKey({ type: "server", id: "srv" })).toBe("server:srv");
  });

  it("uses tool display names in list titles", () => {
    const tools = [makeTool({ id: "claude", displayName: "Claude Code" })];
    expect(filterTitle({ type: "tool", tool: "claude" }, tools)).toBe("Claude Code");
    expect(filterTitle({ type: "tool", tool: "unknown" }, tools)).toBe("unknown");
    expect(filterTitle({ type: "allSkills" }, tools)).toBe("Skills");
  });
});
