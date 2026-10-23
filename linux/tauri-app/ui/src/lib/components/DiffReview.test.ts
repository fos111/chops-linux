import { afterEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen } from "@testing-library/svelte";
import DiffReview from "./DiffReview.svelte";

const original = "# Alpha\n\nOld body.\nFooter.";
const proposed = "# Alpha\n\nNew body.\nFooter.\nAdded line.";

function renderDiff(overrides: { applying?: boolean } = {}) {
  const onaccept = vi.fn();
  const onreject = vi.fn();
  render(DiffReview, {
    props: {
      summary: "Rewrote the body and appended a line.",
      original,
      proposed,
      path: "/home/test/.claude/skills/skill-1.md",
      applying: overrides.applying ?? false,
      onaccept,
      onreject,
    },
  });
  return { onaccept, onreject };
}

afterEach(cleanup);

describe("DiffReview (T16 part B)", () => {
  it("renders the summary, path, diff stats, unified diff, and full file", () => {
    renderDiff();

    expect(
      screen.getByText("Rewrote the body and appended a line."),
    ).toBeTruthy();
    expect(
      screen.getByText("/home/test/.claude/skills/skill-1.md"),
    ).toBeTruthy();
    expect(screen.getByLabelText("Diff stats").textContent).toContain("+2");
    expect(screen.getByLabelText("Diff stats").textContent).toContain("−1");

    const diff = screen.getByLabelText("Unified diff");
    expect(diff.textContent).toContain("Old body.");
    expect(diff.textContent).toContain("New body.");
    expect(diff.textContent).toContain("Added line.");

    const fullFile = screen.getByLabelText("Proposed full file");
    expect(fullFile.textContent).toBe(proposed);
  });

  it("calls Accept and Reject", async () => {
    const { onaccept, onreject } = renderDiff();
    await fireEvent.click(screen.getByRole("button", { name: "Accept" }));
    expect(onaccept).toHaveBeenCalledTimes(1);
    await fireEvent.click(screen.getByRole("button", { name: "Reject" }));
    expect(onreject).toHaveBeenCalledTimes(1);
  });

  it("disables both actions while applying", () => {
    renderDiff({ applying: true });
    const accept = screen.getByRole("button", { name: "Applying…" });
    const reject = screen.getByRole("button", { name: "Reject" });
    expect((accept as HTMLButtonElement).disabled).toBe(true);
    expect((reject as HTMLButtonElement).disabled).toBe(true);
  });
});
