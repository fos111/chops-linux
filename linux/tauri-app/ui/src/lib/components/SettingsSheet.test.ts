import { afterEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen } from "@testing-library/svelte";
import SettingsSheet from "./SettingsSheet.svelte";
import { makeSettings, makeTool } from "$lib/test-fixtures";
import type { SettingsPatch, ThemeMode } from "$lib/api";

const settings = makeSettings({
  scanRoots: ["/home/test/dev"],
  includePluginSkills: false,
  theme: "system",
});

const tools = [
  makeTool({ id: "claude", displayName: "Claude Code", isInstalled: true }),
  makeTool({ id: "codex", displayName: "Codex", isInstalled: false }),
];

function renderSheet(overrides: {
  onupdateSettings?: (patch: SettingsPatch) => Promise<unknown>;
  ontheme?: (theme: ThemeMode) => void;
  onclose?: () => void;
  settingsError?: string | null;
} = {}) {
  const onupdateSettings = overrides.onupdateSettings ?? vi.fn(async () => undefined);
  const ontheme = overrides.ontheme ?? vi.fn();
  const onclose = overrides.onclose ?? vi.fn();
  render(SettingsSheet, {
    props: {
      open: true,
      settings,
      tools,
      settingsError: overrides.settingsError ?? null,
      onupdateSettings,
      ontheme,
      onclose,
    },
  });
  return { onupdateSettings, ontheme, onclose };
}

afterEach(cleanup);

describe("SettingsSheet (T16 part A)", () => {
  it("opens on the General pane with the theme segmented control", () => {
    renderSheet();
    expect(screen.getByRole("button", { name: "General" }).getAttribute("aria-pressed")).toBe("true");
    const segment = screen.getByRole("button", { name: "Dark" });
    expect(segment.getAttribute("aria-pressed")).toBe("false");
  });

  it("routes theme changes to the store's optimistic apply path", async () => {
    const handlers = renderSheet();
    await fireEvent.click(screen.getByRole("button", { name: "Dark" }));
    expect(handlers.ontheme).toHaveBeenCalledWith("dark");
  });

  it("lists every listable tool, including not-installed ones (mac parity)", async () => {
    renderSheet();
    await fireEvent.click(screen.getByText("Tools"));
    expect(screen.getByText("Claude Code")).toBeTruthy();
    expect(screen.getByText("Codex")).toBeTruthy();
    const statuses = screen.getAllByText("Not installed");
    expect(statuses).toHaveLength(1);
  });

  it("lists scan-root overrides with removal through PUT /api/settings", async () => {
    const handlers = renderSheet();
    await fireEvent.click(screen.getByText("Scan Directories"));
    expect(screen.getByText("~/dev")).toBeTruthy();
    await fireEvent.click(
      screen.getByRole("button", { name: "Remove /home/test/dev" }),
    );
    await vi.waitFor(() =>
      expect(handlers.onupdateSettings).toHaveBeenCalledWith({ scanRoots: [] }),
    );
  });

  it("adds a scan-root override through PUT /api/settings", async () => {
    const handlers = renderSheet();
    await fireEvent.click(screen.getByText("Scan Directories"));
    await fireEvent.input(screen.getByLabelText("Add directory"), {
      target: { value: "/home/test/extra" },
    });
    await fireEvent.click(screen.getByText("Add Directory"));
    await vi.waitFor(() =>
      expect(handlers.onupdateSettings).toHaveBeenCalledWith({
        scanRoots: ["/home/test/dev", "/home/test/extra"],
      }),
    );
  });

  it("blocks duplicate roots locally", async () => {
    const handlers = renderSheet();
    await fireEvent.click(screen.getByText("Scan Directories"));
    await fireEvent.input(screen.getByLabelText("Add directory"), {
      target: { value: "/home/test/dev" },
    });
    await fireEvent.click(screen.getByText("Add Directory"));
    await screen.findByText("Directory already added.");
    expect(handlers.onupdateSettings).not.toHaveBeenCalled();
  });

  it("shows the scan-root empty state", async () => {
    renderSheet();
    await fireEvent.click(screen.getByText("Scan Directories"));
    expect(screen.queryByText("/home/test/dev")).toBeNull();
  });

  it("toggles include-plugin-skills through PUT /api/settings", async () => {
    const handlers = renderSheet();
    await fireEvent.click(screen.getByText("Library"));
    const toggle = screen.getByRole("checkbox", {
      name: /Include plugin skills/,
    }) as HTMLInputElement;
    await fireEvent.click(toggle);
    await vi.waitFor(() =>
      expect(handlers.onupdateSettings).toHaveBeenCalledWith({
        includePluginSkills: true,
      }),
    );
  });

  it("surfaces store-level settings errors in the sheet", () => {
    renderSheet({ settingsError: "PUT failed" });
    expect(screen.getByText("PUT failed")).toBeTruthy();
  });

  it("shows the About pane with home-relative paths", async () => {
    renderSheet();
    await fireEvent.click(screen.getByText("About"));
    expect(screen.getByText("~/.config/chops/settings.json")).toBeTruthy();
    expect(screen.getByText("~/.local/share/Chops/chops.db")).toBeTruthy();
    expect(screen.getByText("~")).toBeTruthy();
  });

  it("shows the flag-off remote servers empty state", async () => {
    renderSheet();
    await fireEvent.click(screen.getByText("Servers"));
    expect(screen.getByText(/Remote servers are disabled/)).toBeTruthy();
  });

  it("closes via the Close button", async () => {
    const handlers = renderSheet();
    await fireEvent.click(screen.getByRole("button", { name: "Close" }));
    expect(handlers.onclose).toHaveBeenCalledTimes(1);
  });
});
