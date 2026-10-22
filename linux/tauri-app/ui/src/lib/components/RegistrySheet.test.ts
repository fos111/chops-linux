import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen } from "@testing-library/svelte";
import RegistrySheet from "./RegistrySheet.svelte";
import { makeTool } from "$lib/test-fixtures";
import type { RegistryInstallRequest, RegistrySkill } from "$lib/api";

function makeRegistrySkill(
  overrides: Partial<RegistrySkill> = {},
): RegistrySkill {
  return {
    skillId: overrides.skillId ?? "demo-skill",
    name: overrides.name ?? "Demo Skill",
    installs: overrides.installs ?? 12_300,
    source: overrides.source ?? "demo/repo",
    isOfficial: overrides.isOfficial ?? null,
  };
}

interface Harness {
  fetchTrending: () => Promise<RegistrySkill[]>;
  searchSkills: (q: string) => Promise<RegistrySkill[]>;
  oninstall: (
    request: RegistryInstallRequest,
  ) => Promise<{ installed: boolean; skillName: string }>;
  onclose: () => void;
}

interface HarnessOverrides {
  trending?: RegistrySkill[];
  search?: RegistrySkill[];
  trendingError?: Error;
  searchError?: Error;
  installError?: Error;
}

function makeHarness(overrides: HarnessOverrides = {}): Harness {
  return {
    fetchTrending: vi.fn(async () => {
      if (overrides.trendingError) throw overrides.trendingError;
      return (
        overrides.trending ?? [
          makeRegistrySkill(),
          makeRegistrySkill({
            skillId: "official-one",
            name: "Official Skill",
            source: "chops/core",
            isOfficial: true,
          }),
        ]
      );
    }),
    searchSkills: vi.fn(async (q: string) => {
      if (overrides.searchError) throw overrides.searchError;
      if (q.length < 2) return [];
      return (
        overrides.search ?? [
          makeRegistrySkill({
            skillId: "search-hit",
            name: "Long Tail",
            source: "deep/repo",
            installs: 45,
          }),
        ]
      );
    }),
    oninstall: vi.fn(async () => {
      if (overrides.installError) throw overrides.installError;
      return { installed: true, skillName: "demo-skill" };
    }),
    onclose: vi.fn(),
  };
}

function renderSheet(harness: Harness, open = true) {
  return render(RegistrySheet, {
    props: {
      open,
      tools: [
        makeTool({ id: "claude", displayName: "Claude Code" }),
        makeTool({ id: "codex", displayName: "Codex" }),
        makeTool({
          id: "windsurf",
          displayName: "Windsurf",
          supportsSkills: false,
        }),
      ],
      fetchTrending: harness.fetchTrending,
      searchSkills: harness.searchSkills,
      oninstall: harness.oninstall,
      onclose: harness.onclose,
    },
  });
}

async function openSheet(harness = makeHarness()) {
  renderSheet(harness);
  await vi.waitFor(() => expect(screen.getByText("Demo Skill")).toBeTruthy());
  return harness;
}

describe("RegistrySheet (T16 part A)", () => {
  beforeEach(() => {
    vi.useFakeTimers({ shouldAdvanceTime: true });
  });

  afterEach(() => {
    cleanup();
    vi.useRealTimers();
  });

  it("loads trending rows with formatted installs when opened", async () => {
    await openSheet();
    expect(screen.getAllByText("12.3K installs")).toBeTruthy();
    expect(screen.getByText("Browse Skills")).toBeTruthy();
    expect(screen.queryByText("Install Skill")).toBeNull();
  });

  it("shows the macOS trending failure state with retry", async () => {
    renderSheet(
      makeHarness({ trendingError: new Error("registry down") }),
    );
    await screen.findByText("Trending unavailable");
    expect(screen.getByRole("button", { name: "Retry" })).toBeTruthy();
  });

  it("local-filters trending while browsing without any API call", async () => {
    await openSheet();
    const searchInput = screen.getByLabelText("Search registry");
    await fireEvent.input(searchInput, { target: { value: "official" } });
    await vi.advanceTimersByTimeAsync(350);
    expect(screen.queryByText("Demo Skill")).toBeNull();
    expect(screen.getByText(/Official Skill/)).toBeTruthy();
  });

  it("debounces the API search once the query reaches 2 characters", async () => {
    const harness = await openSheet();
    const searchInput = screen.getByLabelText("Search registry");
    await fireEvent.input(searchInput, { target: { value: "de" } });
    await vi.advanceTimersByTimeAsync(350);
    expect(harness.searchSkills).toHaveBeenCalledWith("de");
    await screen.findByText(/Long Tail/);
  });

  it("clears search results below 2 characters without a request", async () => {
    const harness = await openSheet();
    const searchInput = screen.getByLabelText("Search registry");
    await fireEvent.input(searchInput, { target: { value: "a" } });
    await vi.advanceTimersByTimeAsync(350);
    expect(harness.searchSkills).not.toHaveBeenCalled();
  });

  it("surfaces search failures", async () => {
    renderSheet(makeHarness({ searchError: new Error("search 502") }));
    await vi.waitFor(() => expect(screen.getByText("Demo Skill")).toBeTruthy());
    await fireEvent.input(screen.getByLabelText("Search registry"), {
      target: { value: "react" },
    });
    await vi.advanceTimersByTimeAsync(350);
    await screen.findByText("search 502");
  });

  it("selects a row into the install confirmation sheet with all targets", async () => {
    await openSheet();
    await fireEvent.click(screen.getByRole("button", { name: /Demo Skill/ }));

    expect(screen.getByText("Install Skill")).toBeTruthy();
    const claudeBox = screen.getByRole("checkbox", {
      name: "Claude Code",
    }) as HTMLInputElement;
    const codexBox = screen.getByRole("checkbox", {
      name: "Codex",
    }) as HTMLInputElement;
    expect(claudeBox.checked).toBe(true);
    expect(codexBox.checked).toBe(true);
    expect(
      // Windsurf cannot receive skills, so it never appears as a target.
      screen.queryByText("Windsurf"),
    ).toBeNull();
    expect(screen.getByRole("button", { name: /Install/ })).toBeTruthy();
  });

  it("opens the confirmation on double-click too", async () => {
    await openSheet();
    const row = screen.getByRole("button", { name: /Demo Skill/ });
    fireEvent(row, new MouseEvent("dblclick", { bubbles: true, detail: 2 }));
    await vi.waitFor(() => expect(screen.getByText("Install Skill")).toBeTruthy());
  });

  it("deselect-all disables the install button", async () => {
    await openSheet();
    await fireEvent.click(screen.getByRole("button", { name: /Demo Skill/ }));
    await fireEvent.click(
      screen.getByRole("button", { name: "Deselect All" }),
    );
    const install = screen.getByRole("button", { name: /^Install$/ });
    expect((install as HTMLButtonElement).disabled).toBe(true);
  });

  it("installs with the selected targets and shows the success flash", async () => {
    const harness = await openSheet();
    await fireEvent.click(screen.getByRole("button", { name: /Demo Skill/ }));
    await fireEvent.click(
      screen.getByRole("checkbox", { name: "Codex" }),
    );
    await fireEvent.click(screen.getByRole("button", { name: "Install" }));

    await vi.waitFor(() =>
      expect(harness.oninstall).toHaveBeenCalledWith({
        skillId: "demo-skill",
        name: "Demo Skill",
        source: "demo/repo",
        installs: 12_300,
        isOfficial: null,
        targets: ["claude"],
      }),
    );
    await screen.findByText("Installed!");
  });

  it("retries nothing and shows persistence errors verbatim", async () => {
    renderSheet(makeHarness({ installError: new Error("409 already installed") }));
    await vi.waitFor(() => expect(screen.getByText("Demo Skill")).toBeTruthy());
    await fireEvent.click(screen.getByRole("button", { name: /Demo Skill/ }));
    await fireEvent.click(screen.getByRole("button", { name: "Install" }));
    await screen.findByText("409 already installed");
  });

  it("closes with the Cancel button", async () => {
    const harness = await openSheet();
    await fireEvent.click(screen.getByRole("button", { name: "Cancel" }));
    expect(harness.onclose).toHaveBeenCalledTimes(1);
  });

  it("returns to the list via Back", async () => {
    await openSheet();
    await fireEvent.click(screen.getByRole("button", { name: /Demo Skill/ }));
    expect(screen.getByText("Install Skill")).toBeTruthy();
    await fireEvent.click(screen.getByRole("button", { name: "Back" }));
    expect(screen.getByText("Browse Skills")).toBeTruthy();
  });

  it("respects the official-only toggle while browsing", async () => {
    await openSheet();
    const toggle = screen.getByRole("checkbox", {
      name: "Official only",
    }) as HTMLInputElement;
    await fireEvent.click(toggle);
    expect(screen.queryByText("Demo Skill")).toBeNull();
    expect(screen.getByText(/Official Skill/)).toBeTruthy();
  });
});
