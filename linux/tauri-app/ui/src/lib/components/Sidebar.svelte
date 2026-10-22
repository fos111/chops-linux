<script lang="ts">
  import type { CollectionSummary, Skill, Tool } from "$lib/api";
  import {
    COLLECTION_ICONS,
    DEFAULT_COLLECTION_ICON,
    normalizeCollectionName,
    validateCollectionName,
  } from "$lib/collections";
  import {
    countByKind,
    filterKey,
    installedTools,
    toolCount,
    type SidebarFilter,
  } from "$lib/filters";
  import CollectionIcon from "./CollectionIcon.svelte";
  import KindIcon from "./KindIcon.svelte";
  import ToolLogo from "./ToolLogo.svelte";

  let {
    tools,
    skills,
    collections = [],
    filter,
    onselect,
    oncreateCollection,
    ondeleteCollection,
    onopenRegistry,
    onopenSettings,
  }: {
    tools: Tool[];
    skills: Skill[];
    collections?: CollectionSummary[];
    filter: SidebarFilter;
    onselect: (filter: SidebarFilter) => void;
    oncreateCollection?: (request: {
      name: string;
      icon: string;
    }) => Promise<unknown>;
    ondeleteCollection?: (collection: CollectionSummary) => void;
    /** Discovery row (macOS `appState.showingRegistrySheet`). */
    onopenRegistry?: () => void;
    onopenSettings?: () => void;
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

  // New-collection popover (macOS `CollectionListView` create popover).
  let createOpen = $state(false);
  let newName = $state("");
  let newIcon = $state<string>(DEFAULT_COLLECTION_ICON);
  let createError = $state<string | null>(null);
  let createNameInput = $state<HTMLInputElement | null>(null);
  let wasCreateOpen = false;

  let createBusy = $state(false);

  function openCreate(): void {
    createOpen = true;
  }

  function closeCreate(): void {
    createOpen = false;
    createError = null;
    createNameInput = null;
  }

  // Fresh popover on every open, mirroring the macOS sheet reset.
  $effect(() => {
    if (createOpen && !wasCreateOpen) {
      newName = "";
      newIcon = DEFAULT_COLLECTION_ICON;
      createError = null;
      queueMicrotask(() => createNameInput?.focus());
    }
    wasCreateOpen = createOpen;
  });

  function pickDuplicateError(name: string): string | null {
    const error = validateCollectionName(name, collections);
    return error ? error.message : null;
  }

  async function createCollection(event: Event): Promise<void> {
    event.preventDefault();
    const trimmed = normalizeCollectionName(newName);
    if (createBusy || !trimmed) {
      createError = trimmed ? createError : "Collection name can't be empty";
      return;
    }
    const localError = pickDuplicateError(trimmed);
    if (localError) {
      createError = localError;
      return;
    }
    createError = null;
    createBusy = true;
    try {
      await oncreateCollection?.({ name: trimmed, icon: newIcon });
      closeCreate();
    } catch (error) {
      // chopsd enforces the same uniqueness rule; surface its message instead of
      // silently failing (the macOS popover shows `error.localizedDescription`).
      createError =
        error instanceof Error ? error.message : String(error);
    } finally {
      createBusy = false;
    }
  }

  function deleteCollection(collection: CollectionSummary): void {
    ondeleteCollection?.(collection);
  }
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
    {#if onopenRegistry}
      <button
        type="button"
        class="nav-row discovery-row"
        title="Browse and install skills from the registry"
        onclick={onopenRegistry}
      >
        <KindIcon kind="tool" />
        <span class="nav-label">Discovery</span>
      </button>
    {/if}
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

  <section class="sidebar-section">
    <h2>Collections</h2>
    {#each collections as collection (collection.id)}
      <div class="nav-row collection-row" class:active={activeKey === filterKey({ type: "collection", name: collection.name })}>
        <button
          type="button"
          class="collection-item"
          aria-pressed={activeKey === filterKey({ type: "collection", name: collection.name })}
          title={`Filter by ${collection.name}`}
          onclick={() =>
            onselect({ type: "collection", name: collection.name })}
        >
          <CollectionIcon icon={collection.icon} />
          <span class="nav-label">{collection.name}</span>
          <span class="nav-count">{collection.skillCount}</span>
        </button>
        {#if ondeleteCollection}
          <button
            type="button"
            class="collection-delete"
            aria-label={`Delete collection ${collection.name}`}
            title={`Delete ${collection.name}`}
            onclick={() => deleteCollection(collection)}
          >
            ×
          </button>
        {/if}
      </div>
    {/each}
    {#if collections.length === 0}
      <p class="sidebar-empty">No collections yet.</p>
    {/if}
    {#if oncreateCollection}
      <button
        type="button"
        class="create-collection"
        aria-expanded={createOpen}
        onclick={openCreate}
      >
        <KindIcon kind="skill" size={12} />
        <span>New Collection</span>
      </button>
    {/if}

    {#if createOpen}
      <form class="create-popover" onsubmit={createCollection}>

        <label class="create-label" for="new-collection-name">
          Collection name
        </label>
        <input
          id="new-collection-name"
          type="text"
          bind:this={createNameInput}
          bind:value={newName}
          placeholder="Collection name"
          aria-label="Collection name"
        />
        {#if createError}
          <p class="create-error" role="alert">{createError}</p>
        {/if}
        <div class="icon-grid" aria-label="Collection icon">
          {#each COLLECTION_ICONS as iconName (iconName)}
            <button
              type="button"
              class="icon-option"
              class:selected={newIcon === iconName}
              aria-pressed={newIcon === iconName}
              title={iconName}
              onclick={() => (newIcon = iconName)}
            >
              <CollectionIcon icon={iconName} size={16} />
            </button>
          {/each}
        </div>
        <div class="create-actions">
          <button type="button" onclick={closeCreate}>Cancel</button>
          <button type="submit" disabled={!normalizeCollectionName(newName)}>
            Create
          </button>
        </div>
      </form>
    {/if}
  </section>

  {#if onopenSettings}
    <button
      type="button"
      class="nav-row settings-row"
      title="Settings"
      onclick={onopenSettings}
    >
      <KindIcon kind="rule" />
      <span class="nav-label">Settings</span>
    </button>
  {/if}
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

  .collection-row {
    display: flex;
    align-items: center;
    padding: 0;
    border-radius: 6px;
  }

  .collection-item {
    display: flex;
    align-items: center;
    gap: 8px;
    flex: 1;
    min-width: 0;
    padding: 6px 8px;
    border: 0;
    background: transparent;
    color: var(--text);
    font: inherit;
    font-size: 13px;
    text-align: left;
    cursor: default;
  }

  .collection-row:hover,
  .collection-row.active {
    background: var(--hover);
  }

  .collection-row.active {
    background: var(--selected);
    color: var(--accent-strong);
  }

  .collection-row.active .collection-item {
    color: inherit;
  }

  .collection-delete {
    flex: 0 0 auto;
    width: 18px;
    height: 18px;
    margin-right: 4px;
    padding: 0;
    border: 0;
    border-radius: 4px;
    background: transparent;
    color: var(--muted);
    font-size: 13px;
    line-height: 1;
    cursor: default;
    visibility: hidden;
  }

  .collection-row:hover .collection-delete,
  .collection-delete:focus-visible {
    visibility: visible;
  }

  .collection-delete:hover {
    color: var(--danger, #d33);
  }

  .collection-delete:focus-visible {
    outline: 2px solid var(--accent);
    outline-offset: -2px;
    visibility: visible;
  }

  .create-collection {
    display: flex;
    align-items: center;
    gap: 6px;
    margin: 2px 8px 0;
    padding: 5px 0;
    border: 0;
    background: transparent;
    color: var(--muted);
    font: inherit;
    font-size: 12px;
    cursor: default;
  }

  .discovery-row,
  .settings-row {
    margin: 2px 8px 0;
    color: var(--muted);
  }

  .discovery-row:hover,
  .settings-row:hover {
    color: var(--text);
  }

  .create-collection:hover {
    color: var(--text);
  }

  .create-collection:focus-visible {
    outline: 2px solid var(--accent);
    outline-offset: -2px;
  }

  .create-popover {
    display: flex;
    flex-direction: column;
    gap: 8px;
    margin: 6px 8px 0;
    padding: 10px;
    border: 1px solid var(--border);
    border-radius: 8px;
    background: var(--panel);
    box-shadow: 0 4px 14px rgb(0 0 0 / 0.15);
  }

  .create-label {
    font-size: 11px;
    color: var(--muted);
  }

  .create-popover input[type="text"] {
    width: 100%;
    padding: 5px 8px;
    border: 1px solid var(--border);
    border-radius: 6px;
    background: var(--bg);
    color: var(--text);
    font: inherit;
    font-size: 13px;
  }

  .create-error {
    margin: 0;
    font-size: 11px;
    color: var(--danger, #d33);
  }

  .icon-grid {
    display: grid;
    grid-template-columns: repeat(6, 24px);
    gap: 4px;
  }

  .icon-option {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    width: 24px;
    height: 24px;
    padding: 0;
    border: 0;
    border-radius: 4px;
    background: transparent;
    cursor: default;
  }

  .icon-option:hover {
    background: var(--hover);
  }

  .icon-option.selected {
    background: var(--accent, #4b7bec);
    color: var(--accent-contrast, #fff);
  }

  .icon-option:focus-visible {
    outline: 2px solid var(--accent);
    outline-offset: -2px;
  }

  .create-actions {
    display: flex;
    justify-content: flex-end;
    gap: 6px;
  }

  .create-actions button {
    padding: 4px 10px;
    border: 1px solid var(--border);
    border-radius: 6px;
    background: transparent;
    color: var(--text);
    font: inherit;
    font-size: 12px;
    cursor: default;
  }

  .create-actions button[type="submit"]:disabled {
    opacity: 0.5;
  }
</style>
