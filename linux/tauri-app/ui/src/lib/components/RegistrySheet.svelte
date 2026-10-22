<script lang="ts">
  // Port of the frozen macOS `Chops/Views/Shared/RegistrySheet.swift`:
  // trending browse -> search (>= 2 chars, 300 ms debounce) -> click/double-click a
  // row -> install confirmation sheet (select targets -> Install). Traffic goes
  // through chopsd (`/api/registry/*`), never the public network.
  import type { RegistryInstallRequest, RegistrySkill, Tool } from "$lib/api";
  import {
    isBrowsing,
    formattedInstalls,
    installTargetTools,
    registrySkillId,
    SEARCH_DEBOUNCE_MS,
    SEARCH_MIN_LENGTH,
    visibleRegistrySkills,
  } from "$lib/registry";

  let {
    open,
    tools,
    fetchTrending,
    searchSkills,
    oninstall,
    onclose,
  }: {
    open: boolean;
    tools: Tool[];
    /** `GET /api/registry/trending` through chopsd (injected from the route). */
    fetchTrending: () => Promise<RegistrySkill[]>;
    /** `GET /api/registry/search?q=…` through chopsd (injected from the route). */
    searchSkills: (q: string) => Promise<RegistrySkill[]>;
    oninstall: (
      request: RegistryInstallRequest,
    ) => Promise<{ installed: boolean; skillName: string }>;
    onclose: () => void;
  } = $props();

  let searchText = $state("");
  let officialOnly = $state(false);
  let trending = $state<RegistrySkill[]>([]);
  let trendingLoading = $state(false);
  let trendingError = $state<string | null>(null);

  let results = $state<RegistrySkill[]>([]);
  let isSearching = $state(false);
  let searchError = $state<string | null>(null);

  let selectedSkill = $state<RegistrySkill | null>(null);
  let selectedTargets = $state<Set<string>>(new Set());
  let isInstalling = $state(false);
  let installError = $state<string | null>(null);
  let installSuccess = $state(false);

  let wasOpen = false;
  let searchTimer: ReturnType<typeof setTimeout> | null = null;
  let searchToken = 0;
  let dismissTimer: ReturnType<typeof setTimeout> | null = null;

  const targetTools = $derived(installTargetTools(tools));
  const browsing = $derived(isBrowsing(searchText));
  const visibleSkills = $derived(
    visibleRegistrySkills({ trending, results, searchText, officialOnly }),
  );
  const sectionLabel = $derived(browsing ? "Trending" : "Results");
  const canInstall = $derived(
    selectedSkill !== null && selectedTargets.size > 0 && !isInstalling && !installSuccess,
  );

  $effect(() => {
    if (open && !wasOpen) {
      resetSheet();
      loadTrending();
    } else if (!open && wasOpen) {
      cancelSearchTimer();
    }
    wasOpen = open;
  });

  function resetSheet(): void {
    searchText = "";
    officialOnly = false;
    results = [];
    isSearching = false;
    searchError = null;
    trendingError = null;
    selectedSkill = null;
    isInstalling = false;
    installError = null;
    installSuccess = false;
    selectedTargets = new Set(targetTools.map((tool) => tool.id));
  }

  function cancelSearchTimer(): void {
    if (searchTimer !== null) {
      clearTimeout(searchTimer);
      searchTimer = null;
    }
    searchToken += 1;
    isSearching = false;
  }

  function cancelDismissTimer(): void {
    if (dismissTimer !== null) {
      clearTimeout(dismissTimer);
      dismissTimer = null;
    }
  }

  async function loadTrending(): Promise<void> {
    if (trending.length > 0) return;
    trendingLoading = true;
    trendingError = null;
    try {
      trending = await fetchTrending();
    } catch (error) {
      trendingError = error instanceof Error ? error.message : String(error);
    } finally {
      trendingLoading = false;
    }
  }

  // `ScrollView "Search skills…"`: debounce 300 ms, ignore queries < 2 chars.
  function scheduleSearch(query: string): void {
    cancelSearchTimer();
    searchError = null;
    if (query.length < SEARCH_MIN_LENGTH) {
      results = [];
      return;
    }
    isSearching = true;
    const token = ++searchToken;
    searchTimer = setTimeout(() => {
      searchTimer = null;
      runSearch(query, token);
    }, SEARCH_DEBOUNCE_MS);
  }

  async function runSearch(query: string, token: number): Promise<void> {
    try {
      const skills = await searchSkills(query);
      if (token !== searchToken) return;
      results = skills;
      isSearching = false;
    } catch (error) {
      if (token !== searchToken) return;
      searchError = error instanceof Error ? error.message : String(error);
      isSearching = false;
    }
  }

  /** macOS `selectSkill`: click opens the install phase; double-click does too. */
  function selectSkill(skill: RegistrySkill): void {
    cancelDismissTimer();
    selectedSkill = skill;
    installError = null;
    installSuccess = false;
    isInstalling = false;
    selectedTargets = new Set(targetTools.map((tool) => tool.id));
  }

  function backToList(): void {
    cancelDismissTimer();
    selectedSkill = null;
    installError = null;
    installSuccess = false;
  }

  function toggleTarget(id: string): void {
    const next = new Set(selectedTargets);
    if (next.has(id)) {
      next.delete(id);
    } else {
      next.add(id);
    }
    selectedTargets = next;
  }

  function selectAllTargets(): void {
    selectedTargets = new Set(targetTools.map((tool) => tool.id));
  }

  function deselectAllTargets(): void {
    selectedTargets = new Set();
  }

  async function performInstall(): Promise<void> {
    const skill = selectedSkill;
    if (!skill || !canInstall) return;
    isInstalling = true;
    installError = null;
    try {
      await oninstall({
        skillId: skill.skillId,
        name: skill.name,
        source: skill.source,
        installs: skill.installs,
        isOfficial: skill.isOfficial,
        targets: [...selectedTargets],
      });
      installSuccess = true;
      isInstalling = false;
      // macOS parity: brief success flash, then the sheet dismisses itself.
      cancelDismissTimer();
      dismissTimer = setTimeout(() => {
        dismissTimer = null;
        cancelSheet();
      }, 800);
    } catch (error) {
      installError = error instanceof Error ? error.message : String(error);
      isInstalling = false;
    }
  }

  function cancelSheet(): void {
    cancelSearchTimer();
    cancelDismissTimer();
    onclose();
  }

  function handleKeydown(event: KeyboardEvent): void {
    if (!open) return;
    if (event.key === "Escape") {
      event.preventDefault();
      cancelSheet();
    }
  }

  function targetDisplayName(id: string): string {
    return targetTools.find((tool) => tool.id === id)?.displayName ?? id;
  }
</script>

<svelte:window onkeydown={handleKeydown} />

{#if open}
  <div class="backdrop" role="presentation"></div>
  <div class="sheet-overlay">
    <div
      class="sheet"
      role="dialog"
      aria-modal="true"
      aria-labelledby="registry-title"
      tabindex="-1"
    >
      <header class="registry-header">
        <button
          type="button"
          class="registry-button"
          disabled={selectedSkill === null}
          onclick={backToList}
        >
          Back
        </button>
        <h2 id="registry-title">
          {selectedSkill ? "Install Skill" : "Browse Skills"}
        </h2>
        <button type="button" class="registry-button" onclick={cancelSheet}>
          Cancel
        </button>
      </header>

      <div class="registry-body">
        {#if selectedSkill}
          <section class="install-view" aria-label="Install confirmation">
            <div class="selected-meta">
              <h3>{selectedSkill.name}</h3>
              <p class="selected-source">{selectedSkill.source}</p>
              <p class="selected-installs">
                {formattedInstalls(selectedSkill.installs)} installs
              </p>
            </div>

            <div class="targets">
              {#if targetTools.length === 0}
                <p class="no-agents">
                  No supported agents detected on this machine.
                </p>
              {:else}
                <div class="targets-heading">
                  <span class="targets-label">Install to:</span>
                  <button
                    type="button"
                    class="registry-button small"
                    onclick={selectedTargets.size === targetTools.length
                      ? deselectAllTargets
                      : selectAllTargets}
                  >
                    {selectedTargets.size === targetTools.length
                      ? "Deselect All"
                      : "Select All"}
                  </button>
                </div>
                <ul class="target-list">
                  {#each targetTools as tool (tool.id)}
                    <li>
                      <label class="target-row">
                        <input
                          type="checkbox"
                          checked={selectedTargets.has(tool.id)}
                          onchange={() => toggleTarget(tool.id)}
                        />
                        <span>{tool.displayName}</span>
                      </label>
                    </li>
                  {/each}
                </ul>
              {/if}
            </div>

            <footer class="install-footer">
              <span class="install-error" role="alert">{installError}</span>
              {#if installSuccess}
                <span class="install-success">Installed!</span>
              {/if}
              <span class="footer-spacer"></span>
              <button
                type="button"
                class="install-button"
                disabled={!canInstall}
                onclick={() => void performInstall()}
              >
                {isInstalling ? "Installing…" : "Install"}
              </button>
            </footer>
          </section>
        {:else}
          <section class="browse-view" aria-label="Skill registry">
            <div class="search-row">
              <svg class="search-icon" width="14" height="14" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" aria-hidden="true">
                <circle cx="7" cy="7" r="4.5" />
                <path d="M10.5 10.5L14 14" />
              </svg>
              <input
                type="search"
                class="search-input"
                placeholder="Search skills (e.g. react, testing, deploy)…"
                aria-label="Search registry"
                bind:value={searchText}
                oninput={() => scheduleSearch(searchText)}
              />
              {#if isSearching}
                <span class="spinner" role="status">Searching…</span>
              {/if}
            </div>

            <div class="browse-heading">
              <span class="section-label">{sectionLabel}</span>
              {#if browsing}
                <label class="official-toggle">
                  <input
                    type="checkbox"
                    checked={officialOnly}
                    onchange={(event) =>
                      (officialOnly = event.currentTarget.checked)}
                  />
                  Official only
                </label>
              {/if}
            </div>

            {#if trendingLoading && browsing}
              <p class="registry-status">Loading trending skills…</p>
            {:else if browsing && trending.length === 0 && trendingError}
              <div class="registry-empty" role="alert">
                <p>Trending unavailable</p>
                <p class="registry-empty-detail">{trendingError}</p>
                <button
                  type="button"
                  class="registry-button"
                  onclick={() => void loadTrending()}
                >
                  Retry
                </button>
              </div>
            {:else if visibleSkills.length === 0 && !isSearching}
              <p class="registry-status">
                {browsing ? "No trending skills." : "No results."}
              </p>
            {:else}
              <ul class="registry-list">
                {#each visibleSkills as skill (registrySkillId(skill))}
                  <li>
                    <button
                      type="button"
                      class="registry-row"
                      onclick={() => selectSkill(skill)}
                      ondblclick={() => selectSkill(skill)}
                    >
                      <span class="row-main">
                        <span class="row-name">
                          {skill.name}
                          {#if skill.isOfficial === true}
                            <span class="official" title="Official">✔</span>
                          {/if}
                        </span>
                        <span class="row-source">{skill.source}</span>
                      </span>
                      <span class="row-installs">
                        {formattedInstalls(skill.installs)} installs
                      </span>
                    </button>
                  </li>
                {/each}
              </ul>
            {/if}

            {#if searchError}
              <p class="search-error" role="alert">{searchError}</p>
            {/if}
          </section>
        {/if}
      </div>
    </div>
  </div>
{/if}

<style>
  .backdrop {
    position: fixed;
    inset: 0;
    z-index: 50;
    background: rgb(0 0 0 / 0.4);
  }

  .sheet-overlay {
    position: fixed;
    inset: 0;
    z-index: 51;
    display: flex;
    align-items: center;
    justify-content: center;
    pointer-events: none;
  }

  .sheet {
    pointer-events: auto;
    display: flex;
    flex-direction: column;
    width: 560px;
    max-width: calc(100vw - 40px);
    height: 500px;
    max-height: calc(100vh - 60px);
    border: 1px solid var(--border);
    border-radius: 10px;
    background: var(--panel);
    box-shadow: 0 12px 32px rgb(0 0 0 / 0.35);
    overflow: hidden;
  }

  .registry-header {
    display: grid;
    grid-template-columns: auto 1fr auto;
    align-items: center;
    gap: 12px;
    padding: 16px 20px 12px;
    border-bottom: 1px solid var(--border);
  }

  .registry-header h2 {
    margin: 0;
    font-size: 16px;
    text-align: center;
  }

  .registry-body {
    display: flex;
    flex-direction: column;
    min-height: 0;
    flex: 1;
  }

  .browse-view {
    display: flex;
    flex-direction: column;
    min-height: 0;
    flex: 1;
  }

  .search-row {
    display: flex;
    align-items: center;
    gap: 8px;
    margin: 12px 20px;
    padding: 8px 10px;
    border: 1px solid var(--border);
    border-radius: 8px;
    background: var(--bg);
  }

  .search-icon {
    color: var(--muted);
  }

  .search-input {
    flex: 1;
    min-width: 0;
    border: 0;
    background: transparent;
    color: var(--text);
    font: inherit;
    font-size: 13px;
    outline: none;
  }

  .spinner {
    font-size: 11px;
    color: var(--muted);
  }

  .browse-heading {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 0 20px 8px;
  }

  .section-label {
    font-size: 11px;
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.04em;
    color: var(--muted);
  }

  .official-toggle {
    display: inline-flex;
    align-items: center;
    gap: 5px;
    font-size: 12px;
    color: var(--text);
  }

  .registry-status {
    margin: 24px 20px;
    text-align: center;
    color: var(--muted);
    font-size: 13px;
  }

  .registry-empty {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 6px;
    margin: 24px 20px;
    text-align: center;
  }

  .registry-empty p {
    margin: 0;
    font-size: 13px;
  }

  .registry-empty-detail {
    color: var(--muted);
    max-width: 420px;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .registry-list {
    margin: 0 20px 12px;
    padding: 0;
    overflow-y: auto;
    list-style: none;
  }

  .registry-list li {
    list-style: none;
  }

  .registry-row {
    display: flex;
    align-items: center;
    gap: 12px;
    width: 100%;
    padding: 8px 10px;
    border: 0;
    border-bottom: 1px solid var(--border);
    background: transparent;
    color: var(--text);
    font: inherit;
    font-size: 13px;
    text-align: left;
    cursor: default;
  }

  .registry-row:hover {
    background: var(--hover);
  }

  .registry-row:focus-visible {
    outline: 2px solid var(--accent);
    outline-offset: -2px;
  }

  .row-main {
    display: flex;
    flex-direction: column;
    gap: 2px;
    min-width: 0;
    flex: 1;
  }

  .row-name {
    font-weight: 550;
  }

  .official {
    color: var(--accent-strong, #2f6fde);
    font-size: 11px;
  }

  .row-source {
    font-size: 11px;
    color: var(--muted);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .row-installs {
    flex: 0 0 auto;
    font-size: 11px;
    color: var(--muted);
    font-variant-numeric: tabular-nums;
  }

  .search-error {
    margin: 0 20px 8px;
    font-size: 11px;
    color: var(--danger, #d33);
  }

  .install-view {
    display: flex;
    flex-direction: column;
    min-height: 0;
    flex: 1;
  }

  .selected-meta {
    padding: 14px 20px 10px;
    border-bottom: 1px solid var(--border);
  }

  .selected-meta h3 {
    margin: 0 0 2px;
    font-size: 15px;
  }

  .selected-source {
    margin: 0;
    font-size: 12px;
    color: var(--muted);
  }

  .selected-installs {
    margin: 2px 0 0;
    font-size: 11px;
    color: var(--muted);
  }

  .targets {
    display: flex;
    flex-direction: column;
    padding: 10px 20px;
    min-height: 0;
    flex: 1;
  }

  .targets-heading {
    display: flex;
    align-items: center;
    justify-content: space-between;
    margin-bottom: 4px;
  }

  .targets-label {
    font-size: 13px;
    font-weight: 600;
  }

  .target-list {
    margin: 0;
    padding: 0;
    overflow-y: auto;
    list-style: none;
  }

  .target-row {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 5px 4px;
    font-size: 12px;
  }

  .no-agents {
    font-size: 12px;
    color: var(--muted);
  }

  .install-footer {
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 12px 20px;
    border-top: 1px solid var(--border);
  }

  .footer-spacer {
    flex: 1;
  }

  .install-error {
    font-size: 11px;
    color: var(--danger, #d33);
    max-width: 320px;
  }

  .install-success {
    font-size: 12px;
    color: var(--ok, #2e8b57);
  }

  .registry-button {
    padding: 4px 10px;
    border: 1px solid var(--border);
    border-radius: 6px;
    background: transparent;
    color: var(--text);
    font: inherit;
    font-size: 12px;
    cursor: default;
  }

  .registry-button:disabled {
    opacity: 0.4;
  }

  .registry-button:focus-visible {
    outline: 2px solid var(--accent);
    outline-offset: -2px;
  }

  .registry-button.small {
    font-size: 11px;
    padding: 2px 8px;
  }

  .install-button {
    padding: 6px 16px;
    border: 0;
    border-radius: 6px;
    background: var(--accent);
    color: var(--accent-contrast);
    font: inherit;
    font-size: 13px;
    font-weight: 550;
    cursor: default;
  }

  .install-button:disabled {
    opacity: 0.5;
  }

  .install-button:focus-visible {
    outline: 2px solid var(--accent-strong);
    outline-offset: 1px;
  }
</style>
