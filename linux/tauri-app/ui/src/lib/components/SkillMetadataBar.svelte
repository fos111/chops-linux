<script lang="ts">
  import type { Skill, Tool } from "$lib/api";
  import { abbreviatePath, formatByteCount, installedPathsFor } from "$lib/editor";
  import ToolLogo from "./ToolLogo.svelte";

  let {
    skill,
    tools,
    homeDirectory = null,
  }: {
    skill: Skill;
    tools: Tool[];
    homeDirectory?: string | null;
  } = $props();

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
