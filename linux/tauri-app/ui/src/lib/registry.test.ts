import { describe, expect, it } from "vitest";
import type { RegistrySkill } from "./api";
import { makeTool } from "./test-fixtures";
import {
  SEARCH_DEBOUNCE_MS,
  SEARCH_MIN_LENGTH,
  filterRegistry,
  formattedInstalls,
  installTargetTools,
  isBrowsing,
  officialOnlyRows,
  registrySkillId,
  visibleRegistrySkills,
} from "./registry";

function makeRegistrySkill(overrides: Partial<RegistrySkill> = {}): RegistrySkill {
  return {
    skillId: overrides.skillId ?? "demo-skill",
    name: overrides.name ?? "Demo Skill",
    installs: overrides.installs ?? 5,
    source: overrides.source ?? "demo/repo",
    isOfficial: overrides.isOfficial ?? null,
  };
}

describe("formattedInstalls (macOS RegistrySkill.formattedInstalls)", () => {
  it("leaves sub-thousand counts as-is", () => {
    expect(formattedInstalls(0)).toBe("0");
    expect(formattedInstalls(999)).toBe("999");
  });

  it("scales thousands with K", () => {
    expect(formattedInstalls(1_000)).toBe("1K");
    expect(formattedInstalls(12_300)).toBe("12.3K");
  });

  it("scales millions with M", () => {
    expect(formattedInstalls(1_000_000)).toBe("1M");
    expect(formattedInstalls(1_230_000)).toBe("1.2M");
  });
});

describe("browse vs search mode (macOS isBrowsing)", () => {
  it("browses while the query is shorter than 2 characters", () => {
    expect(isBrowsing("")).toBe(true);
    expect(isBrowsing("a")).toBe(true);
    expect(isBrowsing("ab")).toBe(false);
  });
});

describe("SEARCH constants", () => {
  it("uses the frozen macOS debounce and minimum length", () => {
    expect(SEARCH_DEBOUNCE_MS).toBe(300);
    expect(SEARCH_MIN_LENGTH).toBe(2);
  });
});

describe("filterRegistry (macOS SkillRegistry.filter)", () => {
  const rows = [
    makeRegistrySkill({ name: "React Compose", skillId: "react-compose", source: "acme/lib" }),
    makeRegistrySkill({ name: "Deploy Fast", skillId: "deploy-fast", source: "other/tool" }),
  ];

  it("matches name, skillId, or source case-insensitively", () => {
    expect(filterRegistry(rows, "react")).toHaveLength(1);
    expect(filterRegistry(rows, "deploy-fast")).toHaveLength(1);
    expect(filterRegistry(rows, "ACME")).toHaveLength(1);
    expect(filterRegistry(rows, "zzz")).toHaveLength(0);
  });

  it("returns everything for an empty query", () => {
    expect(filterRegistry(rows, "  ")).toHaveLength(2);
  });
});

describe("officialOnlyRows", () => {
  const rows = [
    makeRegistrySkill({ skillId: "a", isOfficial: true }),
    makeRegistrySkill({ skillId: "b", isOfficial: false }),
    makeRegistrySkill({ skillId: "c", isOfficial: null }),
  ];

  it("keeps only rows whose official flag is true", () => {
    expect(
      officialOnlyRows(rows, true).map((skill) => skill.skillId),
    ).toEqual(["a"]);
  });

  it("returns the list unchanged when off", () => {
    expect(officialOnlyRows(rows, false)).toHaveLength(3);
  });
});

describe("visibleRegistrySkills (macOS RegistrySheet.visibleSkills)", () => {
  const trending = [
    makeRegistrySkill({ skillId: "popular", name: "Popular", source: "top/repo" }),
    makeRegistrySkill({ skillId: "official", name: "Official Skill", source: "chops/core", isOfficial: true }),
  ];

  it("browsing shows the trending list, optionally official-only", () => {
    expect(visibleRegistrySkills({
      trending,
      results: [],
      searchText: "",
      officialOnly: false,
    })).toHaveLength(2);
    expect(
      visibleRegistrySkills({ trending, results: [], searchText: "", officialOnly: true }).map((s) => s.skillId),
    ).toEqual(["official"]);
  });

  it("searching shows local trending matches first, then API extras", () => {
    const results = [
      makeRegistrySkill({ skillId: "popular", name: "Popular", source: "top/repo", installs: 1 }),
      makeRegistrySkill({ skillId: "extra", name: "Long Tail", source: "deep/repo" }),
    ];
    const rows = visibleRegistrySkills({
      trending,
      results,
      searchText: "po",
      officialOnly: false,
    });
    expect(rows.map((skill) => skill.skillId)).toEqual(["popular", "extra"]);
  });

  it("dedupes by source/skillId so local hits are not repeated", () => {
    const results = [
      makeRegistrySkill({ skillId: "popular", name: "Popular", source: "top/repo" }),
    ];
    expect(
      visibleRegistrySkills({ trending, results, searchText: "po", officialOnly: false }),
    ).toHaveLength(1);
  });
});

describe("registrySkillId", () => {
  it("is source/skillId (the macOS RegistrySkill.id)", () => {
    expect(registrySkillId(makeRegistrySkill())).toBe("demo/repo/demo-skill");
  });
});

describe("installTargetTools (chopsd resolveInstallTargets default)", () => {
  const tools = [
    makeTool({ id: "claude", isInstalled: true, supportsSkills: true }),
    makeTool({ id: "codex", isInstalled: false, supportsSkills: true }),
    makeTool({ id: "windsurf", isInstalled: true, supportsSkills: false }),
    makeTool({ id: "agents", isInstalled: true, supportsSkills: true }),
  ];

  it("keeps installed, skill-capable tools and drops the agents bucket", () => {
    expect(installTargetTools(tools).map((tool) => tool.id)).toEqual(["claude"]);
  });

  it("lists nothing when no installed tool can receive skills", () => {
    expect(
      installTargetTools([makeTool({ id: "windsurf", isInstalled: true, supportsSkills: false })]),
    ).toHaveLength(0);
  });
});
