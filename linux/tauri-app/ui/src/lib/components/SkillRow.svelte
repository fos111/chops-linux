<script lang="ts">
  import type { Skill } from "$lib/api";
  import { duplicateCount, kindLabel, projectName, skillKind } from "$lib/filters";
  import KindIcon from "./KindIcon.svelte";
  import ToolLogo from "./ToolLogo.svelte";

  let {
    skill,
    showTypeBadge = false,
    selected = false,
    onselect,
  }: {
    skill: Skill;
    showTypeBadge?: boolean;
    selected?: boolean;
    onselect: (id: number) => void;
  } = $props();

  const kind = $derived(skillKind(skill));
  const project = $derived(projectName(skill));
  const duplicates = $derived(duplicateCount(skill));
  const label = $derived(skill.name || "Untitled");
</script>

<li class="skill-row-item">
  <button
    type="button"
    class="skill-row"
    class:selected
    title={skill.filePath}
    aria-current={selected ? "true" : undefined}
    onclick={() => onselect(skill.id)}
  >
    {#if showTypeBadge}
      <span class="type-icon" title={kindLabel(kind)}>
        <KindIcon kind={kind} size={13} />
      </span>
    {/if}

    <span class="skill-name">{label}</span>

    {#if skill.isFavorite}
      <span class="favorite" aria-label="Favorite">★</span>
    {/if}

    <span class="spacer"></span>

    {#if project}
      <span class="project">{project}</span>
    {/if}

    {#if duplicates > 1}
      <span
        class="dup-badge"
        title={`Installed in ${duplicates} locations`}
        aria-label={`Installed in ${duplicates} locations`}>×{duplicates}</span
      >
    {/if}

    <span class="tool-icons">
      {#each skill.toolSources as toolId (toolId)}
        <ToolLogo toolId={toolId} size={13} />
      {/each}
    </span>
  </button>
</li>

<style>
  .skill-row-item {
    list-style: none;
  }

  .skill-row {
    display: flex;
    align-items: center;
    gap: 6px;
    width: 100%;
    padding: 6px 10px;
    border: 0;
    border-radius: 6px;
    background: transparent;
    color: var(--text);
    font: inherit;
    font-size: 13px;
    text-align: left;
    cursor: default;
  }

  .skill-row:hover {
    background: var(--hover);
  }

  .skill-row.selected {
    background: var(--selected);
    color: var(--accent-strong);
  }

  .skill-row:focus-visible {
    outline: 2px solid var(--accent);
    outline-offset: -2px;
  }

  .type-icon {
    display: inline-flex;
    flex: 0 0 auto;
    color: var(--muted);
  }

  .skill-name {
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .favorite {
    flex: 0 0 auto;
    color: var(--star);
    font-size: 10px;
  }

  .spacer {
    flex: 1;
    min-width: 4px;
  }

  .project {
    max-width: 96px;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    font-size: 11px;
    color: var(--muted);
  }

  .dup-badge {
    flex: 0 0 auto;
    padding: 0 4px;
    border-radius: 3px;
    background: var(--badge-bg);
    color: var(--badge-text);
    font-size: 10px;
    font-weight: 600;
    line-height: 15px;
    font-variant-numeric: tabular-nums;
  }

  .tool-icons {
    display: inline-flex;
    flex: 0 0 auto;
    align-items: center;
    gap: 3px;
    opacity: 0.65;
  }
</style>
