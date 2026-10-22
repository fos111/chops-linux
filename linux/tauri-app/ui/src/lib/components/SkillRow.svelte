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
    onremove,
  }: {
    skill: Skill;
    showTypeBadge?: boolean;
    selected?: boolean;
    onselect: (id: number) => void;
    /** Rendered only in the collection-detail list ("remove membership"). */
    onremove?: (id: number) => void;
  } = $props();

  const kind = $derived(skillKind(skill));
  const project = $derived(projectName(skill));
  const duplicates = $derived(duplicateCount(skill));
  const label = $derived(skill.name || "Untitled");
</script>

<li class="skill-row-item">
  <div class="skill-row-wrap" class:selected>
    <button
      type="button"
      class="skill-row"
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

    {#if onremove}
      <button
        type="button"
        class="remove-member"
        aria-label={`Remove ${label} from collection`}
        title="Remove from collection"
        onclick={() => onremove(skill.id)}
      >
        ×
      </button>
    {/if}
  </div>
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

  .skill-row:focus-visible {
    outline: 2px solid var(--accent);
    outline-offset: -2px;
  }

  .skill-row-wrap {
    display: flex;
    align-items: center;
    border-radius: 6px;
  }

  .skill-row-wrap .skill-row {
    flex: 1;
    min-width: 0;
    width: auto;
    border-radius: 6px 0 0 6px;
  }

  .skill-row-wrap:hover {
    background: var(--hover);
  }

  .skill-row-wrap.selected {
    background: var(--selected);
  }

  .skill-row-wrap.selected .skill-row {
    color: var(--accent-strong);
  }

  .skill-row-wrap .remove-member {
    border-radius: 0 6px 6px 0;
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

  .remove-member {
    flex: 0 0 auto;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    width: 18px;
    height: 18px;
    margin-left: 2px;
    padding: 0;
    border: 0;
    border-radius: 0 6px 6px 0;
    background: transparent;
    color: var(--muted);
    font-size: 12px;
    line-height: 1;
    cursor: default;
  }

  .skill-row-wrap:hover .remove-member {
    visibility: visible;
    color: var(--danger, #d33);
  }

  .remove-member:not(:hover) {
    visibility: hidden;
  }

  .remove-member:hover {
    visibility: visible;
    color: var(--danger, #d33);
  }

  .remove-member:focus-visible {
    outline: 2px solid var(--accent);
    outline-offset: -2px;
    visibility: visible;
  }
</style>
