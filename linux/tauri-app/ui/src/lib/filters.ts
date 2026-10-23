// Library filtering/search rules, ported from the frozen macOS specs:
// - `SidebarFilter` / `SkillListView.filteredSkills` (`Chops/Views/Sidebar/SkillListView.swift`)
// - `SidebarView` library counts (`Chops/Views/Sidebar/SidebarView.swift`)
//
// Pure functions on purpose: the list, the sidebar, and the command palette all
// consume them, and the component tests exercise them without a DOM.

import type { Skill, Tool } from "./api";

export type ItemKind = "skill" | "agent" | "rule";

export type SidebarFilter =
  | { type: "allSkills" }
  | { type: "allAgents" }
  | { type: "allRules" }
  | { type: "favorites" }
  | { type: "tool"; tool: string }
  | { type: "collection"; name: string }
  | { type: "server"; id: string };

export const ITEM_KINDS: ItemKind[] = ["skill", "agent", "rule"];

export function skillKind(skill: Skill): ItemKind {
  return skill.kind === "agent" || skill.kind === "rule" ? skill.kind : "skill";
}

export function kindLabel(kind: ItemKind): string {
  switch (kind) {
    case "agent":
      return "Agent";
    case "rule":
      return "Rule";
    default:
      return "Skill";
  }
}

/** Stable key used for sidebar highlighting (`filterKey(filter) === activeKey`). */
export function filterKey(filter: SidebarFilter): string {
  switch (filter.type) {
    case "tool":
      return `tool:${filter.tool}`;
    case "collection":
      return `collection:${filter.name}`;
    case "server":
      return `server:${filter.id}`;
    default:
      return filter.type;
  }
}

export function filterTitle(filter: SidebarFilter, tools: Tool[] = []): string {
  switch (filter.type) {
    case "allSkills":
      return "Skills";
    case "allAgents":
      return "Agents";
    case "allRules":
      return "Rules";
    case "favorites":
      return "Favorites";
    case "tool":
      return tools.find((tool) => tool.id === filter.tool)?.displayName ?? filter.tool;
    case "collection":
      return filter.name;
    case "server":
      return filter.id;
  }
}

/** Mirrors `@Query(sort: \Skill.name)` from the macOS list. */
export function sortSkills(skills: Skill[]): Skill[] {
  return [...skills].sort((a, b) => {
    const byName = a.name.localeCompare(b.name, undefined, {
      sensitivity: "base",
      numeric: true,
    });
    return byName !== 0 ? byName : a.id - b.id;
  });
}

/** Name, description, or raw content — case-insensitive, macOS parity. */
export function matchesSearch(skill: Skill, searchText: string): boolean {
  const needle = searchText.trim().toLowerCase();
  if (!needle) return true;
  return (
    skill.name.toLowerCase().includes(needle) ||
    skill.description.toLowerCase().includes(needle) ||
    skill.content.toLowerCase().includes(needle)
  );
}

export function filterSkills(
  skills: Skill[],
  filter: SidebarFilter,
  searchText = "",
  toolKindFilter: ItemKind | null = null,
): Skill[] {
  let result = skills.filter((skill) => {
    switch (filter.type) {
      case "allSkills":
        return skillKind(skill) === "skill";
      case "allAgents":
        return skillKind(skill) === "agent";
      case "allRules":
        return skillKind(skill) === "rule";
      case "favorites":
        return skill.isFavorite;
      case "tool":
        return skill.toolSources.includes(filter.tool);
      case "collection":
        return skill.collections.some((collection) => collection.name === filter.name);
      case "server":
        return skill.remoteServerID === filter.id;
    }
  });

  if (filter.type === "tool" && toolKindFilter) {
    result = result.filter((skill) => skillKind(skill) === toolKindFilter);
  }

  return sortSkills(result.filter((skill) => matchesSearch(skill, searchText)));
}

export interface LibraryCounts {
  skill: number;
  agent: number;
  rule: number;
  favorite: number;
}

export function countByKind(skills: Skill[]): LibraryCounts {
  const counts: LibraryCounts = { skill: 0, agent: 0, rule: 0, favorite: 0 };
  for (const skill of skills) {
    counts[skillKind(skill)] += 1;
    if (skill.isFavorite) counts.favorite += 1;
  }
  return counts;
}

export function toolCount(skills: Skill[], tool: string): number {
  return skills.filter((skill) => skill.toolSources.includes(tool)).length;
}

/**
 * Sidebar tools are the listable tools chopsd reports as installed. `ToolSource.listable`
 * hides internal buckets (`custom`, `claudeDesktop`, `aider`) exactly like macOS.
 */
export function installedTools(tools: Tool[]): Tool[] {
  return tools.filter((tool) => tool.listable && tool.isInstalled);
}

/** macOS `SkillListView.onChange(sidebarFilter)` selection reconciliation. */
export function reconcileSelection(
  visibleSkills: Skill[],
  selectedId: number | null,
): number | null {
  if (selectedId !== null && visibleSkills.some((skill) => skill.id === selectedId)) {
    return selectedId;
  }
  return visibleSkills[0]?.id ?? null;
}

/** macOS `Skill.projectName` (path component before the dot-directory). */
export function projectName(skill: Skill): string | null {
  if (skill.isGlobal) return null;
  const components = skill.filePath.split("/");
  for (let index = 1; index < components.length; index += 1) {
    const component = components[index];
    if (component.startsWith(".") && component.length > 1) {
      return components[index - 1] || null;
    }
  }
  return null;
}

/**
 * A skill installed in more than one location (e.g. the `dup-a-md` symlink fixture)
 * is rendered with a duplicate badge. chopsd already dedupes by resolved path, so
 * this is a count of physical installs, not duplicate rows.
 */
export function duplicateCount(skill: Skill): number {
  return Math.max(1, new Set(skill.installedPaths).size);
}

export function primaryToolId(skill: Skill): string | null {
  return skill.toolSources[0] ?? null;
}
