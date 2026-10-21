import { afterEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen } from "@testing-library/svelte";
import StatusBar from "./StatusBar.svelte";
import type { ConnectionState, ThemeMode } from "$lib/api";

afterEach(cleanup);

function renderBar(
  overrides: Partial<{
    connection: ConnectionState;
    total: number;
    visible: number;
    unsaved: boolean;
    theme: ThemeMode;
    settingsError: string | null;
  }> = {},
) {
  const ontheme = vi.fn();
  const result = render(StatusBar, {
    props: {
      connection: "connected",
      total: 5,
      visible: 3,
      unsaved: false,
      theme: "system",
      settingsError: null,
      ontheme,
      ...overrides,
    },
  });
  return { ...result, ontheme };
}

describe("StatusBar", () => {
  it("reports the daemon connection", () => {
    renderBar({ connection: "connected" });
    expect(screen.getByRole("status").textContent).toContain("chopsd connected");

    cleanup();
    renderBar({ connection: "disconnected" });
    expect(screen.getByRole("status").textContent).toContain("chopsd disconnected");
  });

  it("shows filtered and total counts", () => {
    renderBar();
    expect(screen.getByText("3 of 5 items")).toBeTruthy();
  });

  it("renders the unsaved chip only when dirty", () => {
    renderBar({ unsaved: false });
    expect(screen.queryByText("Unsaved changes")).toBeNull();

    cleanup();
    renderBar({ unsaved: true });
    expect(screen.getByText("Unsaved changes")).toBeTruthy();
  });

  it("reflects the active theme and emits changes", async () => {
    const { ontheme } = renderBar({ theme: "dark" });
    const dark = screen.getByRole("button", { name: "Dark" });
    const system = screen.getByRole("button", { name: "System" });
    expect(dark.getAttribute("aria-pressed")).toBe("true");
    expect(system.getAttribute("aria-pressed")).toBe("false");

    await fireEvent.click(screen.getByRole("button", { name: "Light" }));
    expect(ontheme).toHaveBeenCalledWith("light");
  });

  it("surfaces a settings persistence error", () => {
    renderBar({ settingsError: "PUT /api/settings failed (500)" });
    expect(screen.getByRole("alert").textContent).toContain("Settings not saved");
  });
});
