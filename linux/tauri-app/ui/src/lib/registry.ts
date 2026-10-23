// Registry browsing rules, ported from the frozen macOS spec
// `Chops/Views/Shared/RegistrySheet.swift` + `Chops/Services/SkillRegistry.swift`.
//
// Pure functions on purpose: the registry sheet and the tests consume them without
// a DOM. All registry traffic goes through chopsd (`/api/registry/*`); nothing here
// touches the network.

import type { RegistrySkill, Tool } from "./api";

/**
 * macOS `SkillRegistry.RegistrySkill.formattedInstalls`:
 * 1 000 000 → "1M", 1 230 000 → "1.2M", 12 300 → "12.3K", 999 → "999".
 * Trailing ".0" is dropped exactly like the Swift `String(format:)` port.
 */
export function formattedInstalls(installs: number): string {
  if (installs >= 1_000_000) {
    return trimLeadingZero(buildScaled(installs, 1_000_000), "M");
  }
  if (installs >= 1_000) {
    return trimLeadingZero(buildScaled(installs, 1_000), "K");
  }
  return String(installs);
}

function buildScaled(installs: number, divisor: number): string {
  return (installs / divisor).toFixed(1);
}

function trimLeadingZero(scaled: string, suffix: string): string {
  return `${scaled.endsWith(".0") ? scaled.slice(0, -2) : scaled}${suffix}`;
}

/**
 * macOS `isBrowsing` (RegistrySheet): the sheet shows the trending list while the
 * query is shorter than two characters and real search results from that point on.
 */
export function isBrowsing(searchText: string): boolean {
  return searchText.length < 2;
}

/**
 * macOS `SkillRegistry.filter`: case-insensitive substring match across name,
 * skillId, and source.
 */
export function filterRegistry(
  skills: RegistrySkill[],
  query: string,
): RegistrySkill[] {
  const needle = query.trim().toLowerCase();
  if (!needle) return skills;
  return skills.filter(
    (skill) =>
      skill.name.toLowerCase().includes(needle) ||
      skill.skillId.toLowerCase().includes(needle) ||
      skill.source.toLowerCase().includes(needle),
  );
}

/** macOS "Official only" filter: trending rows whose `isOfficial` flag is true. */
export function officialOnlyRows(
  trending: RegistrySkill[],
  officialOnly: boolean,
): RegistrySkill[] {
  return officialOnly ? trending.filter((skill) => skill.isOfficial === true) : trending;
}

/**
 * macOS `RegistrySheet.visibleSkills`:
 * - browsing → the trending list (Local filterable + official toggle);
 * - searching → local trending matches first ("they're the popular ones"), then
 *   long-tail API hits that aren't already in the trending set.
 */
export function visibleRegistrySkills(options: {
  trending: RegistrySkill[];
  results: RegistrySkill[];
  searchText: string;
  officialOnly: boolean;
}): RegistrySkill[] {
  const { trending, results, searchText, officialOnly } = options;
  if (isBrowsing(searchText)) {
    return officialOnlyRows(trending, officialOnly);
  }
  const local = filterRegistry(trending, searchText);
  const localIds = new Set(local.map((skill) => `${skill.source}/${skill.skillId}`));
  const extra = results.filter(
    (skill) => !localIds.has(`${skill.source}/${skill.skillId}`),
  );
  return [...local, ...extra];
}

/**
 * The registry list identity (`RegistrySkill.id`) — `<source>/<skillId>`; the
 * search and trending payloads can overlap, so rows are keyed by this.
 */
export function registrySkillId(skill: RegistrySkill): string {
  return `${skill.source}/${skill.skillId}`;
}

/**
 * Install targets mirror chopsd's `resolveInstallTargets` default:
 * installed, skill-capable tools, excluding the internal buckets the server skips
 * (`agents`, and `custom`/`claudeDesktop`/`aider` never reach the UI because chopsd
 * filters `listable` in `GET /api/tools`).
 */
export function installTargetTools(tools: Tool[]): Tool[] {
  return tools.filter(
    (tool) =>
      tool.isInstalled &&
      tool.listable &&
      tool.supportsSkills &&
      tool.id !== "agents",
  );
}

/** Search requests fire from 2 characters, as on macOS (`debounceSearch`). */
export const SEARCH_MIN_LENGTH = 2;

export const SEARCH_DEBOUNCE_MS = 300;

/** Stable ordering for the sheet list: trending order, then API extras. */
export function sortRegistryRows(rows: RegistrySkill[]): RegistrySkill[] {
  return rows;
}
