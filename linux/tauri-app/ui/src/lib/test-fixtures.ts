// Deterministic DTO builders for the vitest suite. Mirrors the payloads documented
// in `Core/chopsd/DTO.swift`; no test ever talks to a real chopsd or `$HOME`.

import type { Skill, Settings, Tool } from "./api";

let nextId = 1;

export function makeSkill(overrides: Partial<Skill> = {}): Skill {
  const id = overrides.id ?? nextId++;
  const filePath = overrides.filePath ?? `/home/test/.claude/skills/skill-${id}.md`;
  return {
    id,
    filePath,
    resolvedPath: overrides.resolvedPath ?? filePath,
    name: `skill-${id}`,
    description: `description ${id}`,
    content: `# skill-${id}`,
    frontmatter: {},
    isDirectory: false,
    isGlobal: true,
    isFavorite: false,
    fileModifiedDate: "2026-10-21T10:00:00Z",
    fileSize: 42,
    toolSources: ["claude"],
    kind: "skill",
    collections: [],
    remoteServerID: null,
    remotePath: null,
    ...overrides,
    installedPaths: overrides.installedPaths ?? [filePath],
  };
}

export function makeTool(overrides: Partial<Tool> = {}): Tool {
  const id = overrides.id ?? "claude";
  return {
    id,
    displayName: overrides.displayName ?? id,
    isInstalled: true,
    listable: true,
    supportsSkills: true,
    supportsAgents: false,
    supportsRules: false,
    globalPaths: [],
    globalAgentPaths: [],
    globalRulePaths: [],
    ...overrides,
  };
}

export function makeSettings(overrides: Partial<Settings> = {}): Settings {
  return {
    sotDir: "/home/test/.chops",
    scanRoots: [],
    includePluginSkills: false,
    theme: "system",
    homeDirectory: "/home/test",
    settingsPath: "/home/test/.config/chops/settings.json",
    databasePath: "/home/test/.local/share/Chops/chops.db",
    ...overrides,
  };
}
