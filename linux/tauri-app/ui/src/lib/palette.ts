// Command palette model, ported from `Chops/Views/Shared/CommandPaletteView.swift`.
//
// The macOS palette is a keyboard-first, grouped command list: ↑/↓ move, ↵ runs,
// ⎋ dismisses. T14 wires the navigation commands (library filters + installed
// tool jumps); T15/T16 add create/registry commands to the same model.

import type { Tool } from "./api";
import type { SidebarFilter } from "./filters";
import { installedTools } from "./filters";

export interface PaletteAction {
  type: "navigate";
  filter: SidebarFilter;
}

export interface PaletteCommand {
  /** Unique, stable DOM/test key (macOS uses `category/title`). */
  id: string;
  title: string;
  subtitle?: string;
  category: string;
  /** Icon family: a library kind, a star, or `tool` with `toolId` set. */
  glyph: "skill" | "agent" | "rule" | "favorite" | "tool";
  toolId?: string;
  action: PaletteAction;
}

export interface FuzzyMatch {
  score: number;
  positions: number[];
}

/**
 * Case-insensitive subsequence matching with small ranking bonuses for exact
 * substrings, consecutive runs, and word starts. This is a superset of the macOS
 * palette's `localizedCaseInsensitiveContains` filter, so typed prefixes behave
 * identically while abbreviations like `cc` still jump to Claude Code.
 */
export function fuzzyMatch(query: string, text: string): FuzzyMatch | null {
  const needle = query.trim().toLowerCase();
  const haystack = text.toLowerCase();
  if (!needle) return { score: 0, positions: [] };
  if (needle.length > haystack.length) return null;

  let queryIndex = 0;
  let previousIndex = -2;
  let score = 0;
  const positions: number[] = [];

  for (let index = 0; index < haystack.length && queryIndex < needle.length; index += 1) {
    if (haystack[index] !== needle[queryIndex]) continue;
    positions.push(index);
    score += 1;
    if (index === previousIndex + 1) score += 2;
    if (index === 0 || /[\s/_.:-]/.test(haystack[index - 1])) score += 3;
    previousIndex = index;
    queryIndex += 1;
  }

  if (queryIndex < needle.length) return null;

  const substringIndex = haystack.indexOf(needle);
  if (substringIndex >= 0) {
    score += 12 - Math.min(substringIndex, 11);
  }
  score += Math.max(0, 6 - haystack.length / 20);
  return { score, positions };
}

/** Best score across the fields macOS filters on: title, subtitle, category. */
function commandScore(command: PaletteCommand, query: string): number | null {
  const candidates = [command.title, command.subtitle ?? "", command.category];
  let best: number | null = null;
  for (const candidate of candidates) {
    const match = fuzzyMatch(query, candidate);
    if (match && (best === null || match.score > best)) {
      best = match.score;
    }
  }
  return best;
}

export function filterPaletteCommands(
  commands: PaletteCommand[],
  query: string,
): PaletteCommand[] {
  if (!query.trim()) return commands;

  return commands
    .map((command, index) => ({ command, index, score: commandScore(command, query) }))
    .filter((entry): entry is { command: PaletteCommand; index: number; score: number } =>
      entry.score !== null,
    )
    .sort((a, b) => (b.score - a.score) || (a.index - b.index))
    .map((entry) => entry.command);
}

/** macOS `move(_:)`: clamped, no wrap-around. */
export function moveSelection(index: number, delta: number, length: number): number {
  if (length <= 0) return 0;
  return Math.min(Math.max(index + delta, 0), length - 1);
}

type ShortcutEvent = Pick<KeyboardEvent, "key" | "ctrlKey" | "metaKey" | "altKey">;

/** Ctrl+K (⌘K also accepted for webview parity) opens the palette. */
export function isPaletteShortcut(event: ShortcutEvent): boolean {
  if (event.altKey) return false;
  return (event.ctrlKey || event.metaKey) && event.key.toLowerCase() === "k";
}

/** Ctrl+B toggles the sidebar (macOS keymap). */
export function isSidebarShortcut(event: ShortcutEvent): boolean {
  if (event.altKey) return false;
  return (event.ctrlKey || event.metaKey) && event.key.toLowerCase() === "b";
}

function navigateCommand(
  title: string,
  glyph: PaletteCommand["glyph"],
  filter: SidebarFilter,
  toolId?: string,
): PaletteCommand {
  return {
    id: `Navigate/${title}`,
    title,
    category: "Navigate",
    glyph,
    toolId,
    action: { type: "navigate", filter },
  };
}

/** Navigation commands: the four library views plus every installed tool. */
export function buildPaletteCommands(tools: Tool[]): PaletteCommand[] {
  const commands: PaletteCommand[] = [
    navigateCommand("Skills", "skill", { type: "allSkills" }),
    navigateCommand("Agents", "agent", { type: "allAgents" }),
    navigateCommand("Rules", "rule", { type: "allRules" }),
    navigateCommand("Favorites", "favorite", { type: "favorites" }),
  ];

  for (const tool of installedTools(tools)) {
    commands.push(
      navigateCommand(tool.displayName, "tool", { type: "tool", tool: tool.id }, tool.id),
    );
  }

  return commands;
}
