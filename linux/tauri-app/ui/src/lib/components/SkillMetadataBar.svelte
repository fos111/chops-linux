<script lang="ts">
  import type { CollectionSummary, Skill, Tool } from "$lib/api";
  import { abbreviatePath, formatByteCount, installedPathsFor } from "$lib/editor";
  import CollectionIcon from "./CollectionIcon.svelte";
  import ToolLogo from "./ToolLogo.svelte";

  let {
    skill,
    tools,
    homeDirectory = null,
    collections = null,
    ontoggleCollection,
  }: {
    skill: Skill;
    tools: Tool[];
    homeDirectory?: string | null;
    /** Fat list of every collection; enables the macOS tray-button picker when set. */
    collections?: CollectionSummary[] | null;
    ontoggleCollection?: (collection: CollectionSummary) => void;
  } = $props();

  let pickerOpen = $state(false);

  const toolRows = $derived(
    skill.toolSources.map((id) => ({
      id,
      displayName: tools.find((tool) => tool.id === id)?.displayName ?? id,
    })),
  );

  const installedPaths = $derived(
    skill.remotePath ? [skill.remotePath] : installedPathsFor(skill),
  );
  const additionalCount = $derived(Math.max(0, installedPaths.length - 1));
  const primaryPath = $derived(
    abbreviatePath(skill.remotePath ?? skill.filePath, homeDirectory),
  );
  const installedSummary = $derived(
    installedPaths.map((path) => abbreviatePath(path, homeDirectory)).join("\n"),
  );
  const modifiedLabel = $derived(
    Number.isNaN(Date.parse(skill.fileModifiedDate))
      ? ""
      : new Date(skill.fileModifiedDate).toISOString().slice(0, 10),
  );
</script>

<footer class="metadata-bar" aria-label="Skill metadata">
  {#if toolRows.length > 0}
    <ul class="tool-badges" aria-label="Tool sources">
      {#each toolRows as row (row.id)}
        <li title={row.displayName}>
          <ToolLogo toolId={row.id} displayName={row.displayName} size={13} />
          <span>{row.displayName}</span>
        </li>
      {/each}
    </ul>
  {/if}

  <span class="divider" aria-hidden="true"></span>

  <span class="path" title={skill.remotePath ?? skill.filePath}>{primaryPath}</span>

  <span class="divider" aria-hidden="true"></span>

  <span class="installed" title={installedSummary}>
    <span class="label">Installed in</span>
    <span class="installed-path">{installedSummary.split("\n")[0]}</span>
    {#if additionalCount > 0}
      <span class="extra">+{additionalCount}</span>
    {/if}
  </span>

  <span class="spacer"></span>

  {#if collections && ontoggleCollection}
    <div class="collections-picker-wrap">
      <button
        type="button"
        class="collections-button"
        aria-label="Collections"
        title="Collections"
        aria-expanded={pickerOpen}
        onclick={() => (pickerOpen = !pickerOpen)}
      >
        <svg width="12" height="12" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
          <path d="M2 6h4l1 2h2l1-2h4" />
          <path d="M2 6l1.2 7h9.6L14 6l-1-3H3z" />
        </svg>
      </button>
      {#if pickerOpen}
        <div class="collections-popover" role="menu" aria-label="Collections">
          <p class="collections-heading">Collections</p>
          {#each collections as collection (collection.id)}
            {@const assigned = skill.collections.some((ref) => ref.name === collection.name)}
            <button
              type="button"
              class="collections-row"
              role="menuitem"
              onclick={() => ontoggleCollection(collection)}
            >
              <CollectionIcon icon={collection.icon} size={12} />
              <span class="collection-name">{collection.name}</span>
              <span class="check" aria-hidden="true">{assigned ? "✓" : ""}</span>
            </button>
          {/each}
          {#if collections.length === 0}
            <p class="collections-empty">No collections yet</p>
          {/if}
        </div>
      {/if}
    </div>
  {/if}

  {#if skill.remoteServerID}
    <span class="remote" title={skill.remoteServerID}>Remote</span>
  {/if}

  <span class="size">{formatByteCount(skill.fileSize)}</span>

  {#if modifiedLabel}
    <span class="modified" title={skill.fileModifiedDate}>{modifiedLabel}</span>
  {/if}
</footer>

<style>
  .metadata-bar {
    display: flex;
    align-items: center;
    gap: 8px;
    min-width: 0;
    padding: 6px 12px;
    border-top: 1px solid var(--border);
    background: var(--status-bg);
    color: var(--muted);
    font-size: 11px;
    line-height: 16px;
    white-space: nowrap;
  }

  .tool-badges {
    display: flex;
    align-items: center;
    gap: 5px;
    margin: 0;
    padding: 0;
    list-style: none;
  }

  .tool-badges li {
    display: inline-flex;
    align-items: center;
    gap: 3px;
  }

  .divider {
    flex: 0 0 auto;
    width: 1px;
    height: 13px;
    background: var(--border);
  }

  .path,
  .installed-path {
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .path {
    max-width: 38%;
    font-family: var(--mono);
  }

  .installed {
    display: inline-flex;
    align-items: center;
    gap: 4px;
    min-width: 0;
  }

  .label {
    color: var(--muted);
  }

  .installed-path {
    font-family: var(--mono);
  }

  .extra {
    flex: 0 0 auto;
  }

  .spacer {
    flex: 1;
  }

  .collections-picker-wrap {
    position: relative;
    display: inline-flex;
  }

  .collections-button {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    width: 20px;
    height: 16px;
    padding: 0;
    border: 0;
    border-radius: 4px;
    background: transparent;
    color: var(--muted);
    cursor: default;
  }

  .collections-button:hover,
  .collections-button[aria-expanded="true"] {
    color: var(--text);
    background: var(--hover);
  }

  .collections-popover {
    position: absolute;
    right: 0;
    bottom: 18px;
    z-index: 20;
    display: flex;
    flex-direction: column;
    min-width: 170px;
    max-height: 220px;
    overflow-y: auto;
    padding: 6px 0;
    border: 1px solid var(--border);
    border-radius: 8px;
    background: var(--panel);
    box-shadow: 0 4px 14px rgb(0 0 0 / 0.18);
  }

  .collections-heading {
    margin: 0 10px 4px;
    font-size: 11px;
    font-weight: 600;
    color: var(--muted);
  }

  .collections-row {
    display: flex;
    align-items: center;
    gap: 6px;
    padding: 4px 10px;
    border: 0;
    background: transparent;
    color: var(--text);
    font: inherit;
    font-size: 12px;
    cursor: default;
  }

  .collections-row:hover {
    background: var(--hover);
  }

  .collection-name {
    flex: 1;
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .check {
    width: 12px;
    text-align: right;
    color: var(--accent-strong);
  }

  .collections-empty {
    margin: 0 10px;
    font-size: 11px;
    color: var(--muted);
  }

  .remote {
    padding: 0 5px;
    border: 1px solid var(--border);
    border-radius: 3px;
  }

  .size,
  .modified {
    font-variant-numeric: tabular-nums;
  }
</style>
