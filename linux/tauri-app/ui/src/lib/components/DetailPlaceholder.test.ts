import { afterEach, describe, expect, it } from "vitest";
import { cleanup, render, screen } from "@testing-library/svelte";
import DetailPlaceholder from "./DetailPlaceholder.svelte";
import { makeSkill, makeTool } from "$lib/test-fixtures";

afterEach(cleanup);

const tools = [
  makeTool({ id: "claude", displayName: "Claude Code" }),
  makeTool({ id: "codex", displayName: "Codex" }),
];

describe("DetailPlaceholder", () => {
  it("shows the macOS select-a-skill empty state", () => {
    render(DetailPlaceholder, { props: { skill: null, tools } });
    expect(screen.getByText("Select a Skill")).toBeTruthy();
    expect(
      screen.getByText("Choose a skill from the sidebar to view and edit it."),
    ).toBeTruthy();
  });

  it("shows the selected skill metadata and raw content", () => {
    const skill = makeSkill({
      id: 7,
      name: "a-one",
      description: "skill a",
      content: "# a-one\nbody text",
      toolSources: ["claude", "codex"],
    });
    render(DetailPlaceholder, { props: { skill, tools } });

    expect(screen.getByRole("heading", { name: "a-one" })).toBeTruthy();
    expect(screen.getByText("skill a")).toBeTruthy();
    expect(screen.getByText(skill.filePath)).toBeTruthy();
    expect(screen.getByText(/body text/)).toBeTruthy();
    expect(screen.getByText("Claude Code")).toBeTruthy();
    expect(screen.getByText("Codex")).toBeTruthy();
  });
});
