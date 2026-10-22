// Unified diff for the diff-review gate, ported from the frozen macOS
// `Chops/Views/Shared/DiffReviewPanel.swift` (`computeDiff(from:to:)`).
//
// The compose flow compares the editor buffer captured at send time with the
// agent's fenced full file. The UI renders a compact unified diff next to the
// fenced proposal; Accept still goes through chopsd (`assist/{id}/accept`), so
// this module is purely presentational.

export type DiffLineKind = "unchanged" | "added" | "removed";

export interface DiffLine {
  kind: DiffLineKind;
  text: string;
}

/** macOS caps the O(n·m) LCS table at 3 000 lines and falls back to replacement. */
export const DIFF_LINE_LIMIT = 3_000;

function fullReplacement(a: string[], b: string[]): DiffLine[] {
  return [
    ...a.map((text): DiffLine => ({ kind: "removed", text })),
    ...b.map((text): DiffLine => ({ kind: "added", text })),
  ];
}

function lcsDiff(a: string[], b: string[]): DiffLine[] {
  const m = a.length;
  const n = b.length;
  if (m === 0) return b.map((text): DiffLine => ({ kind: "added", text }));
  if (n === 0) return a.map((text): DiffLine => ({ kind: "removed", text }));
  if (m > DIFF_LINE_LIMIT || n > DIFF_LINE_LIMIT) return fullReplacement(a, b);

  const dp: Uint32Array[] = Array.from({ length: m + 1 }, () => new Uint32Array(n + 1));
  for (let i = 1; i <= m; i += 1) {
    for (let j = 1; j <= n; j += 1) {
      dp[i][j] =
        a[i - 1] === b[j - 1] ? dp[i - 1][j - 1] + 1 : Math.max(dp[i - 1][j], dp[i][j - 1]);
    }
  }

  const pairs: [number, number][] = [];
  let i = m;
  let j = n;
  while (i > 0 && j > 0) {
    if (a[i - 1] === b[j - 1]) {
      pairs.push([i - 1, j - 1]);
      i -= 1;
      j -= 1;
    } else if (dp[i - 1][j] >= dp[i][j - 1]) {
      i -= 1;
    } else {
      j -= 1;
    }
  }
  pairs.reverse();

  const result: DiffLine[] = [];
  let ai = 0;
  let bi = 0;
  for (const [oi, pi] of pairs) {
    while (ai < oi) result.push({ kind: "removed", text: a[ai++] });
    while (bi < pi) result.push({ kind: "added", text: b[bi++] });
    result.push({ kind: "unchanged", text: a[ai] });
    ai += 1;
    bi += 1;
  }
  while (ai < m) result.push({ kind: "removed", text: a[ai++] });
  while (bi < n) result.push({ kind: "added", text: b[bi++] });
  return result;
}

/** Computes the unified diff (unchanged/added/removed lines) between two files. */
export function computeDiff(original: string, proposed: string): DiffLine[] {
  const a = original === "" ? [] : original.split("\n");
  const b = proposed === "" ? [] : proposed.split("\n");

  // Trim the common prefix/suffix first so the LCS table only covers the change.
  let start = 0;
  while (start < a.length && start < b.length && a[start] === b[start]) start += 1;

  let endA = a.length;
  let endB = b.length;
  while (endA > start && endB > start && a[endA - 1] === b[endB - 1]) {
    endA -= 1;
    endB -= 1;
  }

  return [
    ...a.slice(0, start).map((text): DiffLine => ({ kind: "unchanged", text })),
    ...lcsDiff(a.slice(start, endA), b.slice(start, endB)),
    ...a.slice(endA).map((text): DiffLine => ({ kind: "unchanged", text })),
  ];
}

export interface DiffStats {
  added: number;
  removed: number;
}

export function diffStats(lines: DiffLine[]): DiffStats {
  let added = 0;
  let removed = 0;
  for (const line of lines) {
    if (line.kind === "added") added += 1;
    else if (line.kind === "removed") removed += 1;
  }
  return { added, removed };
}

export function diffPrefix(kind: DiffLineKind): string {
  if (kind === "added") return "+";
  if (kind === "removed") return "-";
  return " ";
}
