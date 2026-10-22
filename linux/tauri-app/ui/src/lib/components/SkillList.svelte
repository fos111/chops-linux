<script lang="ts">
  import type { Skill } from "$lib/api";
  import SkillRow from "./SkillRow.svelte";

  let {
    skills,
    title,
    searchText,
    selectedId,
    showTypeBadge,
    loading,
    error,
    onselect,
    onsearch,
    onretry,
    ontoggleSidebar,
    onnew,
  }: {
    skills: Skill[];
    title: string;
    searchText: string;
    selectedId: number | null;
    showTypeBadge: boolean;
    loading: boolean;
    error: string | null;
    onselect: (id: number) => void;
    onsearch: (text: string) => void;
    onretry: () => void;
    ontoggleSidebar: () => void;
    onnew?: () => void;
  } = $props();

  const emptyTitle = $derived(
    title === "Skills" || title === "Agents" || title === "Rules"
      ? `No ${title}`
      : "No Skills",
  );
</script>

<section class="list-column" aria-label={`${title} list`}>
  <header class="list-header">
    <button
      type="button"
      class="icon-button"
      aria-label="Toggle sidebar"
      title="Toggle sidebar (Ctrl+B)"
      onclick={ontoggleSidebar}
    >
      <svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" aria-hidden="true">
        <path d="M2 4h12M2 8h12M2 12h12" />
      </svg>
    </button>
    <h1>{title}</h1>
    <span class="result-count" aria-label={`${skills.length} items`}>{skills.length}</span>
    {#if loading}
      <span class="refreshing" role="status">Refreshing…</span>
    {/if}
    {#if onnew}
      <button
        type="button"
        class="icon-button"
        aria-label="New item"
        title="New item"
        onclick={onnew}
      >
        <svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" aria-hidden="true">
          <path d="M8 3v10M3 8h10" />
        </svg>
      </button>
    {/if}
  </header>

  <div class="search-row">
    <svg class="search-icon" width="14" height="14" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" aria-hidden="true">
      <circle cx="7" cy="7" r="4.5" />
      <path d="M10.5 10.5L14 14" />
    </svg>
    <input
      type="search"
      class="search-input"
      aria-label="Search skills"
      placeholder="Search skills…"
      value={searchText}
      oninput={(event) => onsearch(event.currentTarget.value)}
    />
  </div>

  {#if error}
    <div class="error-banner" role="alert">
      <span class="error-text">{error}</span>
      <button type="button" class="retry-button" onclick={onretry}>Retry</button>
    </div>
  {/if}

  {#if skills.length === 0}
    <div class="empty-state">
      <svg width="28" height="28" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.2" stroke-linecap="round" aria-hidden="true">
        <rect x="3" y="1.8" width="10" height="12.4" rx="1.5" />
        <path d="M5.5 5.2h5M5.5 8h5M5.5 10.8h3" />
      </svg>
      <p class="empty-title">{emptyTitle}</p>
      <p class="empty-detail">
        {searchText.trim()
          ? "No items match the current search."
          : "No items match the current filter."}
      </p>
    </div>
  {:else}
    <ul class="skill-list" aria-label={title}>
      {#each skills as skill (skill.id)}
        <SkillRow
          {skill}
          {showTypeBadge}
          selected={skill.id === selectedId}
          {onselect}
        />
      {/each}
    </ul>
  {/if}
</section>

<style>
  .list-column {
    display: flex;
    flex-direction: column;
    min-height: 0;
    height: 100%;
    background: var(--panel);
    border-right: 1px solid var(--border);
  }

  .list-header {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 12px 12px 8px;
  }

  .icon-button {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    width: 26px;
    height: 26px;
    padding: 0;
    border: 0;
    border-radius: 5px;
    background: transparent;
    color: var(--muted);
  }

  .icon-button:hover {
    background: var(--hover);
    color: var(--text);
  }

  .icon-button:focus-visible {
    outline: 2px solid var(--accent);
  }

  h1 {
    flex: 1;
    min-width: 0;
    margin: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    font-size: 15px;
    font-weight: 650;
  }

  .result-count {
    font-size: 11px;
    color: var(--muted);
    font-variant-numeric: tabular-nums;
  }

  .refreshing {
    font-size: 11px;
    color: var(--muted);
  }

  .search-row {
    position: relative;
    display: flex;
    align-items: center;
    margin: 0 12px 8px;
  }

  .search-icon {
    position: absolute;
    left: 8px;
    color: var(--muted);
    pointer-events: none;
  }

  .search-input {
    width: 100%;
    padding: 6px 9px 6px 27px;
    border: 1px solid var(--border);
    border-radius: 6px;
    background: var(--panel-alt);
    color: var(--text);
    font: inherit;
    font-size: 12px;
  }

  .search-input:focus {
    outline: none;
    border-color: var(--accent);
    box-shadow: 0 0 0 2px var(--focus-ring);
  }

  .error-banner {
    display: flex;
    align-items: flex-start;
    gap: 8px;
    margin: 0 12px 8px;
    padding: 7px 9px;
    border-radius: 6px;
    background: var(--error-bg);
    color: var(--error-text);
    font-size: 11.5px;
  }

  .error-text {
    flex: 1;
    min-width: 0;
    overflow-wrap: anywhere;
  }

  .retry-button {
    flex: 0 0 auto;
    padding: 2px 7px;
    border: 1px solid currentColor;
    border-radius: 4px;
    background: transparent;
    color: inherit;
    font: inherit;
    font-size: 11px;
  }

  .skill-list {
    flex: 1;
    min-height: 0;
    margin: 0;
    padding: 0 6px 10px;
    overflow-y: auto;
    list-style: none;
  }

  .empty-state {
    display: flex;
    flex: 1;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 4px;
    padding: 24px;
    color: var(--muted);
    text-align: center;
  }

  .empty-title {
    margin: 4px 0 0;
    font-size: 13px;
    font-weight: 600;
    color: var(--text);
  }

  .empty-detail {
    margin: 0;
    font-size: 12px;
  }
</style>
