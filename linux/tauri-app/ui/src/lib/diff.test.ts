import { describe, expect, it } from "vitest";
import { computeDiff, diffStats } from "./diff";

describe("computeDiff (macOS DiffReviewPanel parity)", () => {
  it("marks every line unchanged for identical files", () => {
    const lines = computeDiff("# Alpha\n\nBody.", "# Alpha\n\nBody.");
    expect(lines.every((line) => line.kind === "unchanged")).toBe(true);
    expect(lines.map((line) => line.text)).toEqual(["# Alpha", "", "Body."]);
    expect(diffStats(lines)).toEqual({ added: 0, removed: 0 });
  });

  it("reports added/removed lines around the common prefix and suffix", () => {
    const lines = computeDiff("# Alpha\nold body\nfooter", "# Alpha\nnew body\nfooter");
    expect(diffStats(lines)).toEqual({ added: 1, removed: 1 });
    expect(lines[0]).toEqual({ kind: "unchanged", text: "# Alpha" });
    expect(lines).toContainEqual({ kind: "removed", text: "old body" });
    expect(lines).toContainEqual({ kind: "added", text: "new body" });
    expect(lines.at(-1)).toEqual({ kind: "unchanged", text: "footer" });
  });

  it("treats an empty original as a pure addition", () => {
    const lines = computeDiff("", "# New\nBody");
    expect(diffStats(lines)).toEqual({ added: 2, removed: 0 });
  });

  it("treats an empty proposal as a pure removal", () => {
    const lines = computeDiff("# Old\nBody", "");
    expect(diffStats(lines)).toEqual({ added: 0, removed: 2 });
  });
});
