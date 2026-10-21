<script lang="ts">
  import type { Skill, Tool } from "$lib/api";
  import {
    countByKind,
    filterKey,
    installedTools,
    toolCount,
    type SidebarFilter,
  } from "$lib/filters";
  import KindIcon from "./KindIcon.svelte";
  import ToolLogo from "./ToolLogo.svelte";

  let {
    tools,
    skills,
    filter,
    onselect,
  }: {
    tools: Tool[];
    skills: Skill[];
    filter: SidebarFilter;
    onselect: (filter: SidebarFilter) => void;
  } = $props();

  const counts = $derived(countByKind(skills));
  const installedToolRows = $derived(installedTools(tools));
  const activeKey = $derived(filterKey(filter));

  const libraryRows = $derived([
    { filter: { type: "allSkills" } as SidebarFilter, label: "Skills", kind: "skill", count: counts.skill },
    { filter: { type: "allAgents" } as SidebarFilter, label: "Agents", kind: "agent", count: counts.agent },
    { filter: { type: "allRules" } as SidebarFilter, label: "Rules", kind: "rule", count: counts.rule },
    { filter: { type: "favorites" } as SidebarFilter, label: "Favorites", kind: "favorite", count: counts.favorite },
  ]);
</script>

<nav class="sidebar" aria-label="Library">
  <div class="brand">
    <span class="brand-mark" aria-hidden="true">C</span>
    <span class="brand-name">Chops</span>
  </div>

  <section class="sidebar-section">
    <h2>Library</h2>
    {#each libraryRows as row (row.label)}
      <button
        type="button"
        class="nav-row"
        class:active={activeKey === filterKey(row.filter)}
        aria-pressed={activeKey === filterKey(row.filter)}
        onclick={() => onselect(row.filter)}
      >
        <KindIcon kind={row.kind} />
        <span class="nav-label">{row.label}</span>
        <span class="nav-count">{row.count}</span>
      </button>
    {/each}
  </section>

  <section class="sidebar-section">
    <h2>Tools</h2>
    {#each installedToolRows as tool (tool.id)}
      <button
        type="button"
        class="nav-row"
        class:active={activeKey === `tool:${tool.id}`}
        aria-pressed={activeKey === `tool:${tool.id}`}
        title={`Filter by ${tool.displayName}`}
        onclick={() => onselect({ type: "tool", tool: tool.id })}
      >
        <ToolLogo toolId={tool.id} displayName={tool.displayName} />
        <span class="nav-label">{tool.displayName}</span>
        <span class="nav-count">{toolCount(skills, tool.id)}</span>
      </button>
    {/each}
    {#if installedToolRows.length === 0}
      <p class="sidebar-empty">No installed tools detected.</p>
    {/if}
  </section>
</nav>

<style>
  .sidebar {
    display: flex;
    flex-direction: column;
    height: 100%;
    padding: 12px 8px;
    gap: 18px;
    overflow-y: auto;
    background: var(--sidebar-bg);
    border-right: 1px solid var(--border);
  }

  .brand {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 0 8px 4px;
  }

  .brand-mark {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    width: 22px;
    height: 22px;
    border-radius: 6px;
    background: var(--accent);
    color: var(--accent-contrast);
    font-size: 13px;
    font-weight: 700;
  }

  .brand-name {
    font-size: 14px;
    font-weight: 650;
    color: var(--text);
  }

  .sidebar-section {
    display: flex;
    flex-direction: column;
    gap: 1px;
  }

  h2 {
    margin: 0;
    padding: 0 8px 4px;
    font-size: 11px;
    font-weight: 600;
    letter-spacing: 0.04em;
    text-transform: uppercase;
    color: var(--muted);
  }

  .nav-row {
    display: flex;
    align-items: center;
    gap: 8px;
    width: 100%;
    padding: 6px 8px;
    border: 0;
    border-radius: 6px;
    background: transparent;
    color: var(--text);
    font: inherit;
    font-size: 13px;
    text-align: left;
    cursor: default;
  }

  .nav-row:hover {
    background: var(--hover);
  }

  .nav-row.active {
    background: var(--selected);
    color: var(--accent-strong);
  }

  .nav-row:focus-visible {
    outline: 2px solid var(--accent);
    outline-offset: -2px;
  }

  .nav-label {
    flex: 1;
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .nav-count {
    font-size: 11px;
    font-variant-numeric: tabular-nums;
    color: var(--muted);
  }

  .nav-row.active .nav-count {
    color: var(--accent-strong);
  }

  .sidebar-empty {
    margin: 2px 8px;
    font-size: 12px;
    color: var(--muted);
  }
</style>
