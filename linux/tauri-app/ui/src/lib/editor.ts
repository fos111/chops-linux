// Editor helpers ported from the frozen macOS specs:
// - `Chops/Views/Detail/SkillEditorView.swift` (raw file in the text buffer)
// - `Chops/Views/Shared/NewSkillSheet.swift` (name sanitizing + boilerplate)
// - `Chops/Services/TemplateManager.swift` (`boilerplate(kind:name:skillID:tool:)`)
//
// chopsd ships the parsed body plus the frontmatter map, never the raw file. The
// editor therefore rebuilds the complete Markdown document from those two pieces:
// the textarea always edits (and `PUT /api/skills/{id}` always writes) the full
// file, including YAML frontmatter, exactly like the macOS NSTextView editor.

import type { Skill, Tool } from "./api";
import type { ItemKind } from "./filters";

export const ITEM_KIND_OPTIONS: { id: ItemKind; label: string }[] = [
  { id: "skill", label: "Skill" },
  { id: "agent", label: "Agent" },
  { id: "rule", label: "Rule" },
];

export function singularKind(kind: ItemKind): string {
  switch (kind) {
    case "agent":
      return "Agent";
    case "rule":
      return "Rule";
    default:
      return "Skill";
  }
}

/** macOS `NewSkillSheet.createItem` sanitizing: lowercase, spaces → `-`, drop the rest. */
export function sanitizeItemName(name: string): string {
  return name
    .toLowerCase()
    .replace(/ /g, "-")
    .split("")
    .filter((character) => /[a-z0-9-]/.test(character))
    .join("");
}

/** Deterministic order for rebuilt frontmatter: identity fields first, then the rest. */
function orderedFrontmatter(frontmatter: Record<string, string>): [string, string][] {
  const preferred = ["name", "description"];
  const keys = Object.keys(frontmatter);
  const head = preferred.filter((key) => key in frontmatter);
  const tail = keys.filter((key) => !preferred.includes(key)).sort();
  return [...head, ...tail].map((key) => [key, frontmatter[key]]);
}

/** Rebuilds the complete Markdown file for the editor buffer. */
export function composeSkillMarkdown(
  skill: Pick<Skill, "content" | "frontmatter">,
): string {
  const entries = orderedFrontmatter(skill.frontmatter ?? {});
  if (entries.length === 0) return skill.content;
  const frontmatter = entries.map(([key, value]) => `${key}: ${value}`).join("\n");
  return `---\n${frontmatter}\n---\n\n${skill.content}`;
}

/** Boilerplate exactly as macOS `generateBoilerplate` / `TemplateManager.boilerplate`. */
export function buildBoilerplate(kind: ItemKind, name: string, tool: string): string {
  switch (kind) {
    case "agent":
      return `---
name: ${sanitizeItemName(name) || name}
description: ${name}
---

# ${name}

## Instructions

Add your agent instructions here.`;
    case "rule":
      return `# ${name}

Add your rule content here.`;
    default:
      if (tool === "claude" || tool === "cursor" || tool === "agents") {
        return `---
name: ${sanitizeItemName(name) || name}
description: ${name}
---

# ${name}

## When to Use

- Describe when this skill should be activated

## Instructions

Add your skill instructions here.`;
      }
      return `---
name: ${sanitizeItemName(name) || name}
description: ${name}
---

# ${name}

## Instructions

Add your skill instructions here.`;
  }
}

/** Tools able to host the given item kind (mirrors the sheet's `creatableTools`). */
export function creatableTools(tools: Tool[], kind: ItemKind): Tool[] {
  return tools.filter((tool) => {
    switch (kind) {
      case "agent":
        return tool.supportsAgents;
      case "rule":
        return tool.supportsRules;
      default:
        return tool.supportsSkills;
    }
  });
}

/** Abbreviates an absolute path under the given home directory to `~/…`. */
export function abbreviatePath(path: string, home: string | null): string {
  if (!home) return path;
  const normalized = home.replace(/\/+$/, "");
  if (!normalized) return path;
  if (path === normalized) return "~";
  return path.startsWith(`${normalized}/`) ? `~${path.slice(normalized.length)}` : path;
}

/** macOS `ByteCountFormatter`-style compact size (`1.2 KB`). */
export function formatByteCount(bytes: number): string {
  if (!Number.isFinite(bytes) || bytes < 0) return "0 bytes";
  const units = ["bytes", "KB", "MB", "GB"];
  let value = bytes;
  let index = 0;
  while (value >= 1024 && index < units.length - 1) {
    value /= 1024;
    index += 1;
  }
  const rounded = index === 0 ? Math.round(value) : Math.round(value * 10) / 10;
  return `${rounded} ${units[index]}`;
}

/** macOS `SkillMetadataBar.displayInstalledPaths`: canonical path first, then others. */
export function installedPathsFor(skill: Pick<Skill, "filePath" | "installedPaths">): string[] {
  const others = skill.installedPaths
    .filter((path) => path !== skill.filePath)
    .sort((a, b) => a.localeCompare(b));
  return [skill.filePath, ...others];
}
