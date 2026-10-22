// Collection rules, ported from the frozen macOS spec `Chops/Views/Sidebar/CollectionListView.swift`
// and the macOS `SkillMetadataBar` collection picker.
//
// Pure functions on purpose: the sidebar, the metadata-bar picker, and the tests all
// consume them without a DOM. chopsd enforces the same uniqueness constraints in the
// store (`UNIQUE(skill_collections.name)`); these checks exist so the sheet can show
// the same error strings macOS does *before* a doomed request goes out.

import type { CollectionSummary, Skill } from "./api";

/** Frozen macOS available-icon list (`CollectionListView.availableIcons`). */
export const COLLECTION_ICONS = [
  "folder", "star", "bookmark", "tag", "tray",
  "archivebox", "doc.text", "gearshape", "wrench",
  "hammer", "paintbrush", "wand.and.stars", "terminal",
  "network", "globe", "bolt", "flame", "leaf",
] as const;

export type CollectionIcon = (typeof COLLECTION_ICONS)[number];

export const DEFAULT_COLLECTION_ICON: CollectionIcon = "folder";

/** `CollectionListView.normalizedName` — trims whitespace and newlines. */
export function normalizeCollectionName(name: string): string {
  return name.trim();
}

export type CollectionCreateError =
  | { code: "empty"; message: string }
  | { code: "duplicate"; message: string }
  | null;

const EMPTY_MESSAGE = "Collection name can't be empty";
export const DUPLICATE_MESSAGE = "A collection with this name already exists";

/**
 * macOS `hasDuplicateName` + the create validation: case-insensitive duplicate
 * check against every collection (optionally excluding one, i.e. its own row).
 * `null` means the name validated.
 */
export function validateCollectionName(
  name: string,
  existing: CollectionSummary[] = [],
  excludeId: number | null = null,
): CollectionCreateError {
  const trimmed = normalizeCollectionName(name);
  if (!trimmed) {
    return { code: "empty", message: EMPTY_MESSAGE };
  }
  const duplicate = existing.some(
    (collection) =>
      collection.id !== excludeId &&
      collection.name.toLowerCase() === trimmed.toLowerCase(),
  );
  return duplicate ? { code: "duplicate", message: DUPLICATE_MESSAGE } : null;
}

/**
 * Changing a collection's name keeps the sidebar selection pointed at it
 * (`commitRename` posts `appState.sidebarFilter = .collection(trimmed)`), so the
 * pickers that key off names need the old → new pair.
 */
export function renamedCollectionFilterKey(oldName: string, newName: string): {
  from: string;
  to: string;
} {
  return { from: `collection:${oldName}`, to: `collection:${newName}` };
}

/** Mirrors the macOS `@Query(sort: \SkillCollection.sortOrder)`; id breaks ties. */
export function sortCollections(
  collections: CollectionSummary[],
): CollectionSummary[] {
  return [...collections].sort((a, b) =>
    a.sortOrder !== b.sortOrder
      ? a.sortOrder - b.sortOrder
      : a.id - b.id,
  );
}

/** Whether the skill row belongs to the collection (name-joined like the DTO). */
export function skillInCollection(
  skill: Skill,
  collection: Pick<CollectionSummary, "name">,
): boolean {
  return skill.collections.some((ref) => ref.name === collection.name);
}

/**
 * Server-authoritative collection members (`CollectionDetailDTO.skills`), still
 * filtered by the list-column search box (name/description/content, same as the
 * library list).
 */
export function filterCollectionDetail(
  skills: Skill[],
  searchText: string,
): Skill[] {
  const needle = searchText.trim().toLowerCase();
  if (!needle) return skills;
  return skills.filter(
    (skill) =>
      skill.name.toLowerCase().includes(needle) ||
      skill.description.toLowerCase().includes(needle) ||
      skill.content.toLowerCase().includes(needle),
  );
}
