import { describe, expect, it } from "vitest";
import type { CollectionSummary } from "./api";
import { makeSkill } from "./test-fixtures";
import {
  COLLECTION_ICONS,
  DEFAULT_COLLECTION_ICON,
  filterCollectionDetail,
  normalizeCollectionName,
  skillInCollection,
  sortCollections,
  validateCollectionName,
} from "./collections";

function makeCollection(
  overrides: Partial<CollectionSummary> = {},
): CollectionSummary {
  return {
    id: overrides.id ?? 1,
    name: overrides.name ?? "Collection",
    icon: overrides.icon ?? "folder",
    sortOrder: overrides.sortOrder ?? 0,
    skillCount: overrides.skillCount ?? 0,
  };
}

describe("collection name rules (macOS CollectionListView)", () => {
  it("normalizes names by trimming whitespace and newlines", () => {
    expect(normalizeCollectionName("  Work  \n")).toBe("Work");
  });

  it("rejects empty names with the macOS message", () => {
    const error = validateCollectionName("   ", []);
    expect(error).toEqual({
      code: "empty",
      message: "Collection name can't be empty",
    });
  });

  it("rejects duplicates case-insensitively", () => {
    const error = validateCollectionName(
      "work",
      [makeCollection({ name: "Work" })],
    );
    expect(error).toEqual({
      code: "duplicate",
      message: "A collection with this name already exists",
    });
  });

  it("excludes the collection's own id when renaming", () => {
    const error = validateCollectionName(
      "Work",
      [makeCollection({ id: 3, name: "Work" })],
      3,
    );
    expect(error).toBeNull();
  });

  it("accepts unique names", () => {
    expect(validateCollectionName("New", [makeCollection()])).toBeNull();
  });
});

describe("collection icon data", () => {
  it("mirrors the frozen macOS availableIcons list", () => {
    expect(COLLECTION_ICONS).toHaveLength(18);
    expect(COLLECTION_ICONS[0]).toBe("folder");
    expect(COLLECTION_ICONS.at(-1)).toBe("leaf");
  });

  it("defaults to folder", () => {
    expect(DEFAULT_COLLECTION_ICON).toBe("folder");
  });
});

describe("sortCollections", () => {
  it("orders by sortOrder, id breaks ties (macOS @Query sort)", () => {
    expect(
      sortCollections([
        makeCollection({ id: 3, sortOrder: 2 }),
        makeCollection({ id: 2, sortOrder: 0 }),
        makeCollection({ id: 1, sortOrder: 0 }),
      ]).map((collection) => collection.id),
    ).toEqual([1, 2, 3]);
  });
});

describe("skillInCollection", () => {
  it("matches by collection name on the skill's ref list", () => {
    const skill = makeSkill({ collections: [{ id: 1, name: "Work", icon: "folder", sortOrder: 0 }] });
    expect(skillInCollection(skill, makeCollection({ name: "Work" }))).toBe(
      true,
    );
    expect(skillInCollection(skill, makeCollection({ name: "Other" }))).toBe(
      false,
    );
  });
});

describe("filterCollectionDetail", () => {
  const skills = [
    makeSkill({ id: 1, name: "Alpha", description: "first", content: "" }),
    makeSkill({ id: 2, name: "Beta", description: "", content: "needle" }),
  ];

  it("returns every member unfiltered with empty query", () => {
    expect(filterCollectionDetail(skills, "  ")).toHaveLength(2);
  });

  it("matches name, description, or content (library search parity)", () => {
    expect(filterCollectionDetail(skills, "alpha").map((s) => s.id)).toEqual([1]);
    expect(filterCollectionDetail(skills, "first").map((s) => s.id)).toEqual([1]);
    expect(filterCollectionDetail(skills, "needle").map((s) => s.id)).toEqual([2]);
  });
});
