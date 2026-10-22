import { afterEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen } from "@testing-library/svelte";
import ComposePanel from "./ComposePanel.svelte";
import type {
  AssistAcceptResponse,
  AssistRejectResponse,
  AssistRequest,
  AssistResponse,
} from "$lib/api";

function makeResponse(overrides: Partial<AssistResponse> = {}): AssistResponse {
  return {
    pendingId:
      overrides.pendingId === undefined ? "pending-1" : overrides.pendingId,
    summary: overrides.summary ?? "Updated the heading.",
    fullFile:
      overrides.fullFile === undefined
        ? "# Alpha\n\nNew body.\n"
        : overrides.fullFile,
    path:
      overrides.path === undefined
        ? "/home/test/.claude/skills/skill-1.md"
        : overrides.path,
    agent: overrides.agent ?? "claude",
    skillId: overrides.skillId ?? 7,
  };
}

function makeAccepted(
  overrides: Partial<AssistAcceptResponse> = {},
): AssistAcceptResponse {
  return {
    accepted: overrides.accepted ?? true,
    pendingId: overrides.pendingId ?? "pending-1",
    path: overrides.path ?? "/home/test/.claude/skills/skill-1.md",
    skill: overrides.skill ?? null,
  };
}

function makeRejected(pendingId = "pending-1"): AssistRejectResponse {
  return { rejected: true, pendingId };
}

function deferred<T>() {
  let resolve!: (value: T) => void;
  let reject!: (reason?: unknown) => void;
  const promise = new Promise<T>((resolvePromise, rejectPromise) => {
    resolve = resolvePromise;
    reject = rejectPromise;
  });
  return { promise, resolve, reject };
}

interface Harness {
  onsend: ReturnType<typeof vi.fn>;
  onaccept: ReturnType<typeof vi.fn>;
  onreject: ReturnType<typeof vi.fn>;
  onaccepted: ReturnType<typeof vi.fn>;
  onclose: ReturnType<typeof vi.fn>;
}

function renderPanel(overrides: Partial<Harness> = {}) {
  const harness: Harness = {
    onsend:
      overrides.onsend ??
      vi.fn(async (_request: AssistRequest) => makeResponse()),
    onaccept:
      overrides.onaccept ??
      vi.fn(async (pendingId: string) => makeAccepted({ pendingId })),
    onreject:
      overrides.onreject ??
      vi.fn(async (pendingId: string) => makeRejected(pendingId)),
    onaccepted: overrides.onaccepted ?? vi.fn(),
    onclose: overrides.onclose ?? vi.fn(),
  };
  render(ComposePanel, {
    props: {
      skillId: 7,
      skillName: "Alpha",
      content: "# Alpha\n\nOld body.",
      onsend: harness.onsend as (request: AssistRequest) => Promise<AssistResponse>,
      onaccept: harness.onaccept as (
        pendingId: string,
      ) => Promise<AssistAcceptResponse>,
      onreject: harness.onreject as (
        pendingId: string,
      ) => Promise<AssistRejectResponse>,
      onaccepted: harness.onaccepted as (
        response: AssistAcceptResponse,
        fullFile: string,
      ) => void,
      onclose: harness.onclose as () => void,
    },
  });
  return harness;
}

async function typePrompt(value = "Tighten the wording") {
  await fireEvent.input(screen.getByLabelText("Compose prompt"), {
    target: { value },
  });
}

afterEach(cleanup);

describe("ComposePanel (T16 part B)", () => {
  it("never calls the live API until the user clicks Send", async () => {
    const harness = renderPanel();
    expect(harness.onsend).not.toHaveBeenCalled();

    await typePrompt();
    expect(harness.onsend).not.toHaveBeenCalled();

    await fireEvent.click(screen.getByRole("button", { name: "Send" }));
    await vi.waitFor(() => expect(harness.onsend).toHaveBeenCalledTimes(1));

    const request = harness.onsend.mock.calls[0][0] as AssistRequest;
    expect(request).toEqual({
      skillId: 7,
      prompt: "Tighten the wording",
      agent: "claude",
      content: "# Alpha\n\nOld body.",
    });
    // The chopsd AssistRequest contract has no model field.
    expect("model" in request).toBe(false);
  });

  it("maps the picker to AgentID raw values and shows a read-only model", async () => {
    const harness = renderPanel();
    const select = screen.getByRole("combobox", { name: "Agent" }) as HTMLSelectElement;
    expect(select.value).toBe("claude");
    expect(screen.getByLabelText("Default model").textContent).toBe("sonnet");
    expect(select.options).toHaveLength(2);
    expect(select.options[1].value).toBe("codex");

    await fireEvent.change(select, { target: { value: "codex" } });
    expect(screen.getByLabelText("Default model").textContent).toBe("CLI default");

    await typePrompt("Switch to codex");
    await fireEvent.click(screen.getByRole("button", { name: "Send" }));
    await vi.waitFor(() =>
      expect(harness.onsend).toHaveBeenCalledWith(
        expect.objectContaining({ agent: "codex" }),
      ),
    );
  });

  it("shows a loading state while the turn is in flight", async () => {
    const gate = deferred<AssistResponse>();
    const harness = renderPanel({
      onsend: vi.fn(() => gate.promise),
    });
    await typePrompt();
    await fireEvent.click(screen.getByRole("button", { name: "Send" }));

    await screen.findByText("Sending…");
    expect(screen.getByText("Waiting for Claude Code…")).toBeTruthy();
    expect(
      (screen.getByRole("button", { name: "Sending…" }) as HTMLButtonElement)
        .disabled,
    ).toBe(true);

    gate.resolve(makeResponse());
    await screen.findByText("Updated the heading.");
    expect(harness.onsend).toHaveBeenCalledTimes(1);
  });

  it("surfaces send failures and re-enables Send", async () => {
    renderPanel({
      onsend: vi.fn(async () => {
        throw new Error("claude exited 1");
      }),
    });
    await typePrompt();
    await fireEvent.click(screen.getByRole("button", { name: "Send" }));

    await screen.findByText("claude exited 1");
    expect(
      (screen.getByRole("button", { name: "Send" }) as HTMLButtonElement)
        .disabled,
    ).toBe(false);
  });

  it("renders a diff proposal with summary, unified diff, and full file", async () => {
    renderPanel();
    await typePrompt();
    await fireEvent.click(screen.getByRole("button", { name: "Send" }));

    await screen.findByText("Updated the heading.");
    expect(screen.getByLabelText("Unified diff").textContent).toContain(
      "Old body.",
    );
    expect(screen.getByLabelText("Proposed full file").textContent).toBe(
      "# Alpha\n\nNew body.\n",
    );
    expect(screen.getByRole("button", { name: "Accept" })).toBeTruthy();
    expect(screen.getByRole("button", { name: "Reject" })).toBeTruthy();
  });

  it("accepts the pending write and hands the result back to the editor", async () => {
    const accepted = makeAccepted();
    const harness = renderPanel({
      onaccept: vi.fn(async () => accepted),
    });
    await typePrompt();
    await fireEvent.click(screen.getByRole("button", { name: "Send" }));
    await screen.findByRole("button", { name: "Accept" });

    await fireEvent.click(screen.getByRole("button", { name: "Accept" }));

    await vi.waitFor(() =>
      expect(harness.onaccept).toHaveBeenCalledWith("pending-1"),
    );
    expect(harness.onaccepted).toHaveBeenCalledWith(
      accepted,
      "# Alpha\n\nNew body.\n",
    );
    await screen.findByText(/Changes accepted/);
    expect(screen.queryByRole("button", { name: "Accept" })).toBeNull();
  });

  it("rejects the pending write and reports the discarded review", async () => {
    const harness = renderPanel();
    await typePrompt();
    await fireEvent.click(screen.getByRole("button", { name: "Send" }));
    await screen.findByRole("button", { name: "Reject" });

    await fireEvent.click(screen.getByRole("button", { name: "Reject" }));

    await vi.waitFor(() =>
      expect(harness.onreject).toHaveBeenCalledWith("pending-1"),
    );
    await screen.findByText("Changes rejected.");
  });

  it("handles prose-only responses without an accept/reject gate", async () => {
    renderPanel({
      onsend: vi.fn(async () =>
        makeResponse({
          pendingId: null,
          fullFile: null,
          path: null,
          summary: "I explained the skill but changed no files.",
        }),
      ),
    });
    await typePrompt();
    await fireEvent.click(screen.getByRole("button", { name: "Send" }));

    await screen.findByText("I explained the skill but changed no files.");
    expect(screen.getByText("No file changes to review.")).toBeTruthy();
    expect(screen.queryByRole("button", { name: "Accept" })).toBeNull();
    expect(screen.queryByRole("button", { name: "Reject" })).toBeNull();
  });

  it("keeps the diff open when accept fails", async () => {
    renderPanel({
      onaccept: vi.fn(async () => {
        throw new Error("403 outside scan roots");
      }),
    });
    await typePrompt();
    await fireEvent.click(screen.getByRole("button", { name: "Send" }));
    await screen.findByRole("button", { name: "Accept" });

    await fireEvent.click(screen.getByRole("button", { name: "Accept" }));

    await screen.findByText("403 outside scan roots");
    expect(screen.getByRole("button", { name: "Accept" })).toBeTruthy();
  });

  it("closes through the Close button", async () => {
    const harness = renderPanel();
    await fireEvent.click(screen.getByRole("button", { name: "Close" }));
    expect(harness.onclose).toHaveBeenCalledTimes(1);
  });
});
