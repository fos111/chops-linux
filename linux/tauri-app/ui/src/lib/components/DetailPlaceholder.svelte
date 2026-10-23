<script lang="ts">
  import type { Skill, Tool } from "$lib/api";
  import { kindLabel, skillKind } from "$lib/filters";
  import KindIcon from "./KindIcon.svelte";
  import ToolLogo from "./ToolLogo.svelte";

  let {
    skill,
    tools,
  }: {
    skill: Skill | null;
    tools: Tool[];
  } = $props();

  const kind = $derived(skill ? skillKind(skill) : "skill");
  const toolRows = $derived(
    skill
      ? skill.toolSources.map((id) => ({
          id,
          displayName: tools.find((tool) => tool.id === id)?.displayName ?? id,
        }))
      : [],
  );
</script>

<section class="detail-column" aria-label="Skill detail">
  {#if !skill}
    <div class="detail-empty">
      <KindIcon kind="skill" size={30} />
      <p class="empty-title">Select a Skill</p>
      <p class="empty-detail">Choose a skill from the sidebar to view and edit it.</p>
    </div>
  {:else}
    <header class="detail-header">
      <div class="detail-title-row">
        <KindIcon kind={kind} size={15} />
        <h2>{skill.name || "Untitled"}</h2>
        <span class="kind-badge">{kindLabel(kind)}</span>
        {#if skill.isFavorite}
          <span class="favorite" aria-label="Favorite">★</span>
        {/if}
      </div>
      <p class="detail-path" title={skill.filePath}>{skill.filePath}</p>
      {#if toolRows.length > 0}
        <ul class="tool-badges" aria-label="Installed for">
          {#each toolRows as row (row.id)}
            <li title={row.displayName}>
              <ToolLogo toolId={row.id} displayName={row.displayName} size={14} />
              <span>{row.displayName}</span>
            </li>
          {/each}
        </ul>
      {/if}
    </header>

    {#if skill.description}
      <p class="detail-description">{skill.description}</p>
    {/if}

    <div class="detail-preview" aria-label="Read-only content preview">
      <pre>{skill.content}</pre>
    </div>
  {/if}
</section>

<style>
  .detail-column {
    display: flex;
    flex-direction: column;
    min-width: 0;
    min-height: 0;
    height: 100%;
    background: var(--panel);
  }

  .detail-empty {
    display: flex;
    flex: 1;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 4px;
    padding: 32px;
    color: var(--muted);
    text-align: center;
  }

  .empty-title {
    margin: 8px 0 0;
    font-size: 15px;
    font-weight: 600;
    color: var(--text);
  }

  .empty-detail {
    margin: 0;
    font-size: 12.5px;
  }

  .detail-header {
    padding: 18px 20px 12px;
    border-bottom: 1px solid var(--border);
  }

  .detail-title-row {
    display: flex;
    align-items: center;
    gap: 8px;
  }

  h2 {
    min-width: 0;
    margin: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    font-size: 17px;
    font-weight: 650;
  }

  .kind-badge {
    flex: 0 0 auto;
    padding: 1px 6px;
    border-radius: 4px;
    background: var(--badge-bg);
    color: var(--badge-text);
    font-size: 10px;
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.03em;
  }

  .favorite {
    color: var(--star);
  }

  .detail-path {
    margin: 6px 0 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    font-family: var(--mono);
    font-size: 11px;
    color: var(--muted);
  }

  .tool-badges {
    display: flex;
    flex-wrap: wrap;
    gap: 6px;
    margin: 10px 0 0;
    padding: 0;
    list-style: none;
  }

  .tool-badges li {
    display: inline-flex;
    align-items: center;
    gap: 4px;
    padding: 2px 6px;
    border: 1px solid var(--border);
    border-radius: 4px;
    font-size: 11px;
    color: var(--muted);
  }

  .detail-description {
    margin: 0;
    padding: 12px 20px;
    border-bottom: 1px solid var(--border);
    font-size: 13px;
    color: var(--text);
  }

  .detail-preview {
    flex: 1;
    min-height: 0;
    overflow: auto;
    padding: 16px 20px 24px;
  }

  pre {
    margin: 0;
    font-family: var(--mono);
    font-size: 12px;
    line-height: 1.55;
    color: var(--text);
    white-space: pre-wrap;
    overflow-wrap: anywhere;
  }
</style>
