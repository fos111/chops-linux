import { afterEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen } from "@testing-library/svelte";
import SkillEditor from "./SkillEditor.svelte";
import type {
  AssistAcceptResponse,
  AssistRejectResponse,
  AssistRequest,
  AssistResponse,
} from "$lib/api";
import { makeSkill, makeTool } from "$lib/test-fixtures";

function makeResponse(overrides: Partial<AssistResponse> = {}): AssistResponse {
  return {
    pendingId: overrides.pendingId ?? "pending-1",
    summary: overrides.summary ?? "Updated the body.",
    fullFile: overrides.fullFile ?? "# Alpha\n\nNew body.",
    path: overrides.path ?? "/home/test/.claude/skills/skill-5.md",
    agent: overrides.agent ?? "claude",
    skillId: overrides.skillId ?? 5,
  };
}

function renderEditor(overrides: {
  onassist?: (request: AssistRequest) => Promise<AssistResponse>;
  onacceptassist?: (pendingId: string) => Promise<AssistAcceptResponse>;
  onrejectassist?: (pendingId: string) => Promise<AssistRejectResponse>;
} = {}) {
  const skill = makeSkill({
    id: 5,
    name: "Alpha",
    content: "# Alpha\n\nOld body.",
    frontmatter: { name: "Alpha" },
    filePath: "/home/test/.claude/skills/skill-5.md",
  });
  const onsave = vi.fn(async () => skill);
  const onunsaved = vi.fn();
  const onassist =
    overrides.onassist ?? vi.fn(async () => makeResponse());
  const onacceptassist =
    overrides.onacceptassist ??
    vi.fn(async (pendingId: string) => ({
      accepted: true,
      pendingId,
      path: skill.filePath,
      skill: { ...skill, content: "# Alpha\n\nNew body." },
    }));
  const onrejectassist =
    overrides.onrejectassist ??
    vi.fn(async (pendingId: string) => ({ rejected: true, pendingId }));

  render(SkillEditor, {
    props: {
      skill,
      tools: [makeTool({ id: "claude", displayName: "Claude Code" })],
      onsave,
      onunsaved,
      onassist,
      onacceptassist,
      onrejectassist,
    },
  });
  return { onsave, onunsaved, onassist, onacceptassist, onrejectassist };
}

afterEach(cleanup);

describe("SkillEditor compose integration (T16 part B)", () => {
  it("opens the compose panel from the detail editor", async () => {
    renderEditor();
    expect(screen.queryByLabelText("Compose panel")).toBeNull();
    await fireEvent.click(
      screen.getByRole("button", { name: "Compose with AI" }),
    );
    expect(screen.getByLabelText("Compose panel")).toBeTruthy();
    expect(screen.getByRole("combobox", { name: "Agent" })).toBeTruthy();
  });

  it("updates the editor buffer from the accepted skill DTO", async () => {
    const harness = renderEditor();
    const textarea = screen.getByLabelText("Skill markdown") as HTMLTextAreaElement;
    await vi.waitFor(() =>
      expect(textarea.value).toBe("---\nname: Alpha\n---\n\n# Alpha\n\nOld body."),
    );

    await fireEvent.click(
      screen.getByRole("button", { name: "Compose with AI" }),
    );
    await fireEvent.input(screen.getByLabelText("Compose prompt"), {
      target: { value: "Rewrite the body" },
    });
    await fireEvent.click(screen.getByRole("button", { name: "Send" }));
    await screen.findByRole("button", { name: "Accept" });
    await fireEvent.click(screen.getByRole("button", { name: "Accept" }));

    await vi.waitFor(() =>
      expect(harness.onacceptassist).toHaveBeenCalledWith("pending-1"),
    );
    await vi.waitFor(() =>
      expect(textarea.value).toBe(
        "---\nname: Alpha\n---\n\n# Alpha\n\nNew body.",
      ),
    );
    await vi.waitFor(() => expect(harness.onunsaved).toHaveBeenLastCalledWith(false));
  });

  it("falls back to the reviewed full file when accept returns no skill row", async () => {
    const harness = renderEditor({
      onacceptassist: vi.fn(async (pendingId: string) => ({
        accepted: true,
        pendingId,
        path: "/home/test/.claude/skills/skill-5.md",
        skill: null,
      })),
    });
    const textarea = screen.getByLabelText("Skill markdown") as HTMLTextAreaElement;

    await fireEvent.click(
      screen.getByRole("button", { name: "Compose with AI" }),
    );
    await fireEvent.input(screen.getByLabelText("Compose prompt"), {
      target: { value: "Rewrite the body" },
    });
    await fireEvent.click(screen.getByRole("button", { name: "Send" }));
    await screen.findByRole("button", { name: "Accept" });
    await fireEvent.click(screen.getByRole("button", { name: "Accept" }));

    await vi.waitFor(() =>
      expect(harness.onacceptassist).toHaveBeenCalledWith("pending-1"),
    );
    await vi.waitFor(() =>
      expect(textarea.value).toBe("# Alpha\n\nNew body."),
    );
  });
});
