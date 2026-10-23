<script lang="ts">
  import type { ConnectionState, ThemeMode } from "$lib/api";

  let {
    connection,
    total,
    visible,
    unsaved,
    theme,
    settingsError,
    ontheme,
  }: {
    connection: ConnectionState;
    total: number;
    visible: number;
    unsaved: boolean;
    theme: ThemeMode;
    settingsError: string | null;
    ontheme: (theme: ThemeMode) => void;
  } = $props();

  const connectionLabel = $derived(
    connection === "connected"
      ? "chopsd connected"
      : connection === "connecting"
        ? "connecting to chopsd…"
        : "chopsd disconnected",
  );

  const countLabel = $derived(
    visible === total ? `${total} items` : `${visible} of ${total} items`,
  );

  const themes: { id: ThemeMode; label: string }[] = [
    { id: "system", label: "System" },
    { id: "light", label: "Light" },
    { id: "dark", label: "Dark" },
  ];
</script>

<footer class="status-bar">
  <span class="connection" data-state={connection} role="status" aria-live="polite">
    <span class="dot" aria-hidden="true"></span>
    {connectionLabel}
  </span>

  <span class="count">{countLabel}</span>

  <span class="spacer"></span>

  {#if unsaved}
    <span class="unsaved-chip" role="status" aria-live="polite">Unsaved changes</span>
  {/if}

  {#if settingsError}
    <span class="settings-error" role="alert" title={settingsError}>Settings not saved</span>
  {/if}

  <span class="theme-group" role="group" aria-label="Theme">
    {#each themes as option (option.id)}
      <button
        type="button"
        class="theme-button"
        class:active={theme === option.id}
        aria-pressed={theme === option.id}
        onclick={() => ontheme(option.id)}>{option.label}</button
      >
    {/each}
  </span>
</footer>

<style>
  .status-bar {
    display: flex;
    align-items: center;
    gap: 12px;
    min-width: 0;
    padding: 0 10px;
    border-top: 1px solid var(--border);
    background: var(--status-bg);
    color: var(--muted);
    font-size: 11px;
    line-height: 1;
    white-space: nowrap;
  }

  .connection {
    display: inline-flex;
    align-items: center;
    gap: 5px;
  }

  .dot {
    width: 7px;
    height: 7px;
    border-radius: 50%;
    background: var(--muted);
  }

  .connection[data-state="connected"] .dot {
    background: var(--ok);
  }

  .connection[data-state="connecting"] .dot {
    background: var(--warn);
  }

  .connection[data-state="disconnected"] .dot {
    background: var(--danger);
  }

  .count {
    font-variant-numeric: tabular-nums;
  }

  .spacer {
    flex: 1;
  }

  .unsaved-chip {
    padding: 1px 6px;
    border-radius: 3px;
    background: var(--warn-bg);
    color: var(--warn-text);
    font-weight: 600;
  }

  .settings-error {
    max-width: 180px;
    overflow: hidden;
    text-overflow: ellipsis;
    color: var(--danger);
  }

  .theme-group {
    display: inline-flex;
    gap: 1px;
    padding: 1px;
    border: 1px solid var(--border);
    border-radius: 5px;
  }

  .theme-button {
    padding: 1px 6px;
    border: 0;
    border-radius: 4px;
    background: transparent;
    color: var(--muted);
    font: inherit;
    font-size: 10px;
    line-height: 15px;
  }

  .theme-button:hover {
    background: var(--hover);
  }

  .theme-button.active {
    background: var(--selected);
    color: var(--accent-strong);
  }

  .theme-button:focus-visible {
    outline: 2px solid var(--accent);
  }
</style>
