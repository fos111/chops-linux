<script lang="ts">
  import type { SkillCreateRequest, Tool } from "$lib/api";
  import { focusTrap } from "$lib/focusTrap";
  import {
    buildBoilerplate,
    creatableTools,
    ITEM_KIND_OPTIONS,
    sanitizeItemName,
    singularKind,
  } from "$lib/editor";
  import type { ItemKind } from "$lib/filters";

  let {
    open,
    tools,
    oncreate,
    onclose,
  }: {
    open: boolean;
    tools: Tool[];
    oncreate: (request: SkillCreateRequest) => Promise<unknown>;
    onclose: () => void;
  } = $props();

  let kind = $state<ItemKind>("skill");
  let name = $state("");
  let selectedTool = $state("");
  let creating = $state(false);
  let error = $state<string | null>(null);
  let nameInput = $state<HTMLInputElement | null>(null);
  let wasOpen = false;

  const toolOptions = $derived(creatableTools(tools, kind));
  const sanitized = $derived(sanitizeItemName(name));
  const canCreate = $derived(
    name.trim().length > 0 && sanitized.length > 0 && selectedTool.length > 0,
  );
  const preview = $derived(
    canCreate ? buildBoilerplate(kind, name, selectedTool) : "",
  );

  // Fresh sheet on every open, and keep the tool valid for the chosen kind.
  $effect(() => {
    if (open && !wasOpen) {
      kind = "skill";
      name = "";
      selectedTool = "";
      error = null;
      creating = false;
      queueMicrotask(() => nameInput?.focus());
    }
    wasOpen = open;
  });

  $effect(() => {
    if (!open) return;
    const available = toolOptions;
    if (available.length > 0 && !available.some((tool) => tool.id === selectedTool)) {
      selectedTool = available[0].id;
    }
  });

  async function create(): Promise<void> {
    if (!canCreate || creating) return;
    creating = true;
    error = null;
    try {
      await oncreate({ name, tool: selectedTool, kind });
    } catch (createError) {
      error = createError instanceof Error ? createError.message : String(createError);
      creating = false;
    }
  }

  function handleKeydown(event: KeyboardEvent): void {
    if (open && event.key === "Escape") {
      event.preventDefault();
      onclose();
    }
  }
</script>

<svelte:window onkeydown={handleKeydown} />

{#if open}
  <div class="backdrop" role="presentation">
    <div
      class="sheet"
      role="dialog"
      aria-modal="true"
      aria-labelledby="new-item-title"
      tabindex="-1"
      use:focusTrap
    >
      <form
        onsubmit={(event) => {
          event.preventDefault();
          void create();
        }}
      >
        <h2 id="new-item-title">New {singularKind(kind)}</h2>

        <div class="fields">
          <label>
            <span>Kind</span>
            <select
              value={kind}
              onchange={(event) => (kind = event.currentTarget.value as ItemKind)}
            >
              {#each ITEM_KIND_OPTIONS as option (option.id)}
                <option value={option.id}>{option.label}</option>
              {/each}
            </select>
          </label>

          <label>
            <span>Tool</span>
            <select
              aria-label="Tool"
              bind:value={selectedTool}
              disabled={toolOptions.length === 0}
            >
              {#each toolOptions as tool (tool.id)}
                <option value={tool.id}>{tool.displayName}</option>
              {/each}
            </select>
          </label>

          <label>
            <span>{singularKind(kind)} name</span>
            <input
              bind:this={nameInput}
              bind:value={name}
              aria-label={`${singularKind(kind)} name`}
              placeholder="my-new-skill"
              autocomplete="off"
            />
          </label>
        </div>

        <div class="preview-block">
          <span class="preview-label">Template preview</span>
          <pre aria-label="Template preview">{preview || "Enter a name to preview the boilerplate."}</pre>
        </div>

        {#if toolOptions.length === 0}
          <p class="error" role="alert">No installed tool supports this item kind.</p>
        {/if}

        {#if error}
          <p class="error" role="alert">{error}</p>
        {/if}

        <footer>
          <button type="button" class="cancel" onclick={onclose}>Cancel</button>
          <span class="spacer"></span>
          <button type="submit" class="create" disabled={!canCreate || creating}>
            {creating ? "Creating…" : "Create"}
          </button>
        </footer>
      </form>
    </div>
  </div>
{/if}

<style>
  .backdrop {
    position: fixed;
    inset: 0;
    z-index: 60;
    display: flex;
    align-items: flex-start;
    justify-content: center;
    padding-top: 9vh;
    background: rgba(0, 0, 0, 0.32);
  }

  .sheet {
    width: 460px;
    max-width: calc(100vw - 48px);
    max-height: 82vh;
    overflow: auto;
    padding: 20px 22px;
    border: 1px solid var(--border);
    border-radius: 10px;
    background: var(--panel);
    box-shadow: var(--palette-shadow);
  }

  h2 {
    margin: 0 0 16px;
    font-size: 16px;
  }

  .fields {
    display: flex;
    flex-direction: column;
    gap: 10px;
  }

  label {
    display: flex;
    flex-direction: column;
    gap: 4px;
    font-size: 11px;
    color: var(--muted);
  }

  select,
  input {
    height: 28px;
    padding: 0 8px;
    border: 1px solid var(--border-strong);
    border-radius: 5px;
    background: var(--panel);
    color: var(--text);
    font-size: 12.5px;
  }

  .preview-block {
    margin-top: 16px;
  }

  .preview-label {
    display: block;
    margin-bottom: 4px;
    color: var(--muted);
    font-size: 11px;
  }

  pre {
    max-height: 210px;
    margin: 0;
    overflow: auto;
    padding: 10px 12px;
    border: 1px solid var(--border);
    border-radius: 6px;
    background: var(--panel-alt);
    color: var(--text);
    font-family: var(--mono);
    font-size: 11.5px;
    line-height: 1.55;
    white-space: pre-wrap;
  }

  .error {
    margin: 10px 0 0;
    color: var(--danger);
    font-size: 11.5px;
  }

  footer {
    display: flex;
    align-items: center;
    margin-top: 18px;
  }

  .spacer {
    flex: 1;
  }

  footer button {
    padding: 5px 12px;
    border: 1px solid var(--border-strong);
    border-radius: 6px;
    font-size: 12px;
  }

  .cancel {
    background: var(--panel);
    color: var(--text);
  }

  .create {
    border-color: var(--accent);
    background: var(--accent);
    color: var(--accent-contrast);
  }

  .create:disabled {
    opacity: 0.5;
  }

  footer button:not(:disabled):hover {
    filter: brightness(0.96);
  }
</style>
