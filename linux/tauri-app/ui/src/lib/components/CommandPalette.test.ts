import { afterEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen } from "@testing-library/svelte";
import CommandPalette from "./CommandPalette.svelte";
import { buildPaletteCommands } from "$lib/palette";
import { makeTool } from "$lib/test-fixtures";

afterEach(cleanup);

const commands = buildPaletteCommands([
  makeTool({ id: "claude", displayName: "Claude Code" }),
  makeTool({ id: "codex", displayName: "Codex" }),
]);

function renderPalette(open = true) {
  const onaction = vi.fn();
  const onclose = vi.fn();
  const result = render(CommandPalette, {
    props: { open, commands, onaction, onclose },
  });
  return { ...result, onaction, onclose };
}

describe("CommandPalette", () => {
  it("renders nothing while closed", () => {
    renderPalette(false);
    expect(screen.queryByRole("dialog")).toBeNull();
  });

  it("opens as a dialog with every command", () => {
    renderPalette();
    expect(screen.getByRole("dialog", { name: "Command palette" })).toBeTruthy();
    expect(screen.getAllByRole("option")).toHaveLength(6);
    expect(screen.getByText("NAVIGATE")).toBeTruthy();
  });

  it("marks the first command active", () => {
    renderPalette();
    const options = screen.getAllByRole("option");
    expect(options[0].getAttribute("aria-selected")).toBe("true");
    expect(options[1].getAttribute("aria-selected")).toBe("false");
  });

  it("filters commands through the fuzzy matcher", async () => {
    renderPalette();
    const input = screen.getByLabelText("Search commands");
    await fireEvent.input(input, { target: { value: "cla" } });
    const options = screen.getAllByRole("option");
    expect(options).toHaveLength(1);
    expect(options[0].textContent).toContain("Claude Code");
  });

  it("moves with the arrow keys and runs with Enter", async () => {
    const { onaction } = renderPalette();
    const input = screen.getByLabelText("Search commands");

    await fireEvent.keyDown(input, { key: "ArrowDown" });
    expect(screen.getAllByRole("option")[1].getAttribute("aria-selected")).toBe("true");

    await fireEvent.keyDown(input, { key: "ArrowUp" });
    expect(screen.getAllByRole("option")[0].getAttribute("aria-selected")).toBe("true");

    await fireEvent.keyDown(input, { key: "ArrowDown" });
    await fireEvent.keyDown(input, { key: "Enter" });
    expect(onaction).toHaveBeenCalledWith(
      expect.objectContaining({
        title: "Agents",
        action: { type: "navigate", filter: { type: "allAgents" } },
      }),
    );
  });

  it("clamps at the ends like the macOS palette", async () => {
    renderPalette();
    const input = screen.getByLabelText("Search commands");
    await fireEvent.keyDown(input, { key: "ArrowUp" });
    expect(screen.getAllByRole("option")[0].getAttribute("aria-selected")).toBe("true");
  });

  it("closes on Escape", async () => {
    const { onclose } = renderPalette();
    await fireEvent.keyDown(screen.getByLabelText("Search commands"), {
      key: "Escape",
    });
    expect(onclose).toHaveBeenCalled();
  });

  it("shows the macOS no-results state", async () => {
    renderPalette();
    await fireEvent.input(screen.getByLabelText("Search commands"), {
      target: { value: "zzzz" },
    });
    expect(screen.getByText("No matching commands")).toBeTruthy();
    expect(screen.queryAllByRole("option")).toHaveLength(0);
  });

  it("runs a command on click", async () => {
    const { onaction } = renderPalette();
    await fireEvent.click(screen.getByText("Rules"));
    expect(onaction).toHaveBeenCalledWith(
      expect.objectContaining({
        action: { type: "navigate", filter: { type: "allRules" } },
      }),
    );
  });
});
