<script lang="ts">
  import { tick } from "svelte";
  import { focusTrap } from "$lib/focusTrap";
  import {
    filterPaletteCommands,
    moveSelection,
    type PaletteCommand,
  } from "$lib/palette";
  import KindIcon from "./KindIcon.svelte";
  import ToolLogo from "./ToolLogo.svelte";

  let {
    open,
    commands,
    onaction,
    onclose,
  }: {
    open: boolean;
    commands: PaletteCommand[];
    onaction: (command: PaletteCommand) => void;
    onclose: () => void;
  } = $props();

  let query = $state("");
  let selectedIndex = $state(0);
  let inputEl: HTMLInputElement | null = $state(null);

  const filtered = $derived(filterPaletteCommands(commands, query));
  const activeId = $derived(
    filtered.length > 0 ? optionId(selectedIndex) : undefined,
  );

  function optionId(index: number): string {
    return `palette-option-${index}`;
  }

  $effect(() => {
    if (!open) return;
    query = "";
    selectedIndex = 0;
    void tick().then(() => inputEl?.focus());
  });

  $effect(() => {
    if (!open) return;
    const active = selectedIndex;
    const element = document.getElementById(optionId(active));
    if (element && typeof element.scrollIntoView === "function") {
      element.scrollIntoView({ block: "nearest" });
    }
  });

  function handleInputKeydown(event: KeyboardEvent): void {
    if (event.key === "ArrowDown") {
      event.preventDefault();
      selectedIndex = moveSelection(selectedIndex, 1, filtered.length);
    } else if (event.key === "ArrowUp") {
      event.preventDefault();
      selectedIndex = moveSelection(selectedIndex, -1, filtered.length);
    } else if (event.key === "Enter") {
      event.preventDefault();
      const command = filtered[selectedIndex];
      if (command) onaction(command);
    } else if (event.key === "Escape") {
      event.preventDefault();
      onclose();
    }
  }

  function handleWindowKeydown(event: KeyboardEvent): void {
    if (open && event.key === "Escape") {
      event.preventDefault();
      onclose();
    }
  }
</script>

<svelte:window onkeydown={handleWindowKeydown} />

{#if open}
  <div
    class="palette-backdrop"
    role="presentation"
    onclick={(event) => {
      if (event.target === event.currentTarget) onclose();
    }}
  >
    <div
      class="palette"
      role="dialog"
      aria-modal="true"
      aria-label="Command palette"
      tabindex="-1"
      use:focusTrap
    >
      <div class="palette-search">
        <svg width="15" height="15" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" aria-hidden="true">
          <circle cx="7" cy="7" r="4.5" />
          <path d="M10.5 10.5L14 14" />
        </svg>
        <input
          bind:this={inputEl}
          type="text"
          aria-label="Search commands"
          aria-controls="palette-results"
          aria-activedescendant={activeId}
          placeholder="Search commands…"
          autocomplete="off"
          spellcheck="false"
          bind:value={query}
          oninput={() => (selectedIndex = 0)}
          onkeydown={handleInputKeydown}
        />
      </div>

      <div class="palette-divider"></div>

      {#if filtered.length === 0}
        <p class="palette-empty" role="status">No matching commands</p>
      {:else}
        <ul id="palette-results" class="palette-results" role="listbox" aria-label="Commands">
          {#each filtered as command, index (command.id)}
            {#if index === 0 || filtered[index - 1].category !== command.category}
              <li class="palette-category" role="presentation">
                {command.category.toUpperCase()}
              </li>
            {/if}
            <li
              id={optionId(index)}
              class="palette-option"
              class:selected={index === selectedIndex}
              role="option"
              aria-selected={index === selectedIndex}
              tabindex="-1"
              onclick={() => onaction(command)}
              onkeydown={(event) => {
                if (event.key === "Enter" || event.key === " ") {
                  event.preventDefault();
                  onaction(command);
                }
              }}
              onmouseenter={() => (selectedIndex = index)}
            >
              <span class="palette-icon">
                {#if command.toolId}
                  <ToolLogo toolId={command.toolId} size={15} />
                {:else}
                  <KindIcon kind={command.glyph} size={15} />
                {/if}
              </span>
              <span class="palette-title">{command.title}</span>
              {#if command.subtitle}
                <span class="palette-subtitle">{command.subtitle}</span>
              {/if}
            </li>
          {/each}
        </ul>
      {/if}
    </div>
  </div>
{/if}

<style>
  .palette-backdrop {
    position: fixed;
    inset: 0;
    z-index: 50;
    display: flex;
    align-items: flex-start;
    justify-content: center;
    padding: 12vh 16px 16px;
    background: rgba(0, 0, 0, 0.28);
  }

  .palette {
    width: 560px;
    max-width: 100%;
    max-height: 70vh;
    overflow: hidden;
    border: 1px solid var(--border-strong);
    border-radius: 10px;
    background: var(--panel);
    box-shadow: var(--palette-shadow);
  }

  .palette-search {
    display: flex;
    align-items: center;
    gap: 9px;
    padding: 13px 16px;
    color: var(--muted);
  }

  .palette-search input {
    flex: 1;
    min-width: 0;
    border: 0;
    outline: none;
    background: transparent;
    color: var(--text);
    font: inherit;
    font-size: 15px;
  }

  .palette-divider {
    height: 1px;
    background: var(--border);
  }

  .palette-results {
    max-height: 360px;
    margin: 0;
    padding: 6px 0 8px;
    overflow-y: auto;
    list-style: none;
  }

  .palette-category {
    padding: 10px 16px 3px;
    font-size: 10px;
    font-weight: 650;
    letter-spacing: 0.06em;
    color: var(--muted);
  }

  .palette-option {
    display: flex;
    align-items: center;
    gap: 9px;
    margin: 1px 8px;
    padding: 7px 8px;
    border-radius: 6px;
    color: var(--text);
    font-size: 13px;
  }

  .palette-option.selected {
    background: var(--accent);
    color: var(--accent-contrast);
  }

  .palette-icon {
    display: inline-flex;
    flex: 0 0 auto;
    align-items: center;
    justify-content: center;
    width: 18px;
    height: 18px;
    color: var(--muted);
  }

  .palette-option.selected .palette-icon {
    color: var(--accent-contrast);
  }

  .palette-title {
    flex: 1;
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .palette-subtitle {
    font-size: 11px;
    color: var(--muted);
  }

  .palette-option.selected .palette-subtitle {
    color: var(--accent-contrast);
    opacity: 0.85;
  }

  .palette-empty {
    margin: 0;
    padding: 26px 16px;
    color: var(--muted);
    font-size: 13px;
    text-align: center;
  }
</style>
