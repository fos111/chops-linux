<script lang="ts">
  import { computeDiff, diffPrefix, diffStats } from "$lib/diff";

  // Diff-review gate for one assist proposal: summary + unified diff against the
  // editor buffer + the fenced full file. Accept/Reject call back into chopsd;
  // this component never writes files.
  let {
    summary,
    original,
    proposed,
    path = null,
    applying = false,
    onaccept,
    onreject,
  }: {
    summary: string;
    original: string;
    proposed: string;
    path?: string | null;
    applying?: boolean;
    onaccept: () => void;
    onreject: () => void;
  } = $props();

  const lines = $derived(computeDiff(original, proposed));
  const stats = $derived(diffStats(lines));
</script>

<section class="diff-review" aria-label="Diff review">
  <header class="diff-header">
    <span class="diff-title">Review Changes</span>
    {#if path}
      <span class="diff-path" title={path}>{path}</span>
    {/if}
    <span class="diff-stats" aria-label="Diff stats">
      <span class="added">+{stats.added}</span>
      <span class="removed">−{stats.removed}</span>
    </span>
    <span class="spacer"></span>
    <button
      type="button"
      class="reject-button"
      disabled={applying}
      onclick={onreject}>Reject</button
    >
    <button
      type="button"
      class="accept-button"
      disabled={applying}
      onclick={onaccept}
    >
      {applying ? "Applying…" : "Accept"}
    </button>
  </header>

  {#if summary.trim()}
    <p class="diff-summary" aria-label="Agent summary">{summary}</p>
  {/if}

  <div class="unified-diff" aria-label="Unified diff" role="list">
    {#each lines as line, index (index)}
      <div class="diff-line {line.kind}" role="listitem">
        <span class="prefix" aria-hidden="true">{diffPrefix(line.kind)}</span>
        <span class="code">{line.text.length > 0 ? line.text : " "}</span>
      </div>
    {/each}
  </div>

  <div class="full-file">
    <p class="full-file-label">Proposed full file</p>
    <pre aria-label="Proposed full file"><code>{proposed}</code></pre>
  </div>
</section>

<style>
  .diff-review {
    display: flex;
    flex-direction: column;
    min-height: 0;
    border: 1px solid var(--border);
    border-radius: 8px;
    overflow: hidden;
    background: var(--panel);
  }

  .diff-header {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 6px 10px;
    border-bottom: 1px solid var(--border);
    background: var(--panel-alt);
  }

  .diff-title {
    font-size: 12px;
    font-weight: 600;
  }

  .diff-path {
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    font-family: var(--mono);
    font-size: 10.5px;
    color: var(--muted);
  }

  .diff-stats {
    display: inline-flex;
    gap: 6px;
    font-family: var(--mono);
    font-size: 11px;
  }

  .diff-stats .added {
    color: var(--ok, #2e8b57);
  }

  .diff-stats .removed {
    color: var(--danger, #d33);
  }

  .spacer {
    flex: 1;
  }

  .diff-header button {
    padding: 3px 10px;
    border: 1px solid var(--border);
    border-radius: 5px;
    background: transparent;
    color: var(--text);
    font: inherit;
    font-size: 11px;
  }

  .diff-header button:disabled {
    opacity: 0.5;
  }

  .accept-button {
    background: var(--selected);
    color: var(--accent-strong);
  }

  .diff-summary {
    margin: 0;
    padding: 8px 10px;
    border-bottom: 1px solid var(--border);
    font-size: 12px;
    white-space: pre-wrap;
  }

  .unified-diff {
    max-height: 200px;
    overflow: auto;
    padding: 4px 0;
    border-bottom: 1px solid var(--border);
    background: var(--bg);
    font-family: var(--mono);
    font-size: 11px;
    line-height: 1.5;
  }

  .diff-line {
    display: flex;
    gap: 4px;
    padding: 0 8px;
    white-space: pre;
  }

  .diff-line.added {
    background: rgb(46 139 87 / 0.12);
  }

  .diff-line.removed {
    background: rgb(211 51 51 / 0.12);
  }

  .prefix {
    width: 10px;
    flex: 0 0 auto;
    text-align: center;
    color: var(--muted);
  }

  .added .prefix,
  .added .code {
    color: var(--ok, #2e8b57);
  }

  .removed .prefix,
  .removed .code {
    color: var(--danger, #d33);
  }

  .full-file {
    display: flex;
    flex: 1;
    flex-direction: column;
    min-height: 0;
  }

  .full-file-label {
    margin: 0;
    padding: 4px 10px;
    color: var(--muted);
    font-size: 10.5px;
    text-transform: uppercase;
    letter-spacing: 0.04em;
  }

  .full-file pre {
    flex: 1;
    min-height: 80px;
    max-height: 220px;
    margin: 0;
    overflow: auto;
    padding: 8px 10px;
    background: var(--panel-alt);
    font-family: var(--mono);
    font-size: 11.5px;
    line-height: 1.55;
    white-space: pre;
  }
</style>
