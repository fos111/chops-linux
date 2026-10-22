<script lang="ts">
  import { focusTrap } from "$lib/focusTrap";

  let {
    open,
    ondiscard,
    oncancel,
  }: {
    open: boolean;
    ondiscard: () => void;
    oncancel: () => void;
  } = $props();
</script>

{#if open}
  <div class="backdrop" role="presentation">
    <div
      class="dialog"
      role="alertdialog"
      aria-modal="true"
      aria-labelledby="discard-title"
      aria-describedby="discard-detail"
      tabindex="-1"
      use:focusTrap
    >
      <h2 id="discard-title">Discard unsaved changes?</h2>
      <p id="discard-detail">
        This item has changes that have not been saved. Closing it now will lose them.
      </p>
      <div class="actions">
        <button type="button" class="keep" onclick={oncancel}>Keep Editing</button>
        <button type="button" class="discard" onclick={ondiscard}>Discard Changes</button>
      </div>
    </div>
  </div>
{/if}

<style>
  .backdrop {
    position: fixed;
    inset: 0;
    z-index: 70;
    display: flex;
    align-items: flex-start;
    justify-content: center;
    padding-top: 16vh;
    background: rgba(0, 0, 0, 0.32);
  }

  .dialog {
    width: 360px;
    max-width: calc(100vw - 48px);
    padding: 20px 22px;
    border: 1px solid var(--border);
    border-radius: 10px;
    background: var(--panel);
    box-shadow: var(--palette-shadow);
  }

  h2 {
    margin: 0 0 8px;
    font-size: 15px;
  }

  p {
    margin: 0 0 18px;
    color: var(--muted);
    font-size: 12.5px;
    line-height: 1.5;
  }

  .actions {
    display: flex;
    justify-content: flex-end;
    gap: 8px;
  }

  button {
    padding: 5px 12px;
    border: 1px solid var(--border-strong);
    border-radius: 6px;
    font-size: 12px;
  }

  .keep {
    background: var(--panel);
    color: var(--text);
  }

  .discard {
    border-color: var(--danger);
    background: var(--danger);
    color: #fff;
  }

  button:hover {
    filter: brightness(0.96);
  }
</style>
