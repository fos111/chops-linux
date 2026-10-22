<script lang="ts">
  // Settings sheet, mirroring the frozen macOS `Chops/Views/Settings/SettingsView.swift`
  // tabs that map to the fixed chopsd contract (part A: General/theme, Library/plugin
  // toggle, Scan Directories/scanRoots, Tools/installed-tool display, About/paths;
  // part B: the flag-gated Remote Servers pane).
  import type {
    RegistryInstallResponse,
    RemoteBrowseResponse,
    RemoteInstallRequest,
    RemoteServer,
    RemoteServerRequest,
    Settings,
    SettingsPatch,
    ThemeMode,
    Tool,
  } from "$lib/api";
  import { remoteServersEnabled } from "$lib/remoteFlag";
  import RemoteServersPanel from "./RemoteServersPanel.svelte";

  let {
    open,
    settings,
    tools,
    settingsError = null,
    remoteEnabled,
    onupdateSettings,
    ontheme,
    onlistRemoteServers,
    oncreateRemoteServer,
    onupdateRemoteServer,
    ondeleteRemoteServer,
    onbrowseRemote,
    oninstallRemote,
    onclose,
  }: {
    open: boolean;
    settings: Settings | null;
    tools: Tool[];
    settingsError?: string | null;
    /** Overrides VITE_ENABLE_REMOTE_SERVERS (tests use this; default follows the flag). */
    remoteEnabled?: boolean;
    /** General settings mutation through `PUT /api/settings`. Throws on failure. */
    onupdateSettings: (patch: SettingsPatch) => Promise<unknown>;
    /** Theme changes ride the store's optimistic apply + persist path. */
    ontheme: (theme: ThemeMode) => void;
    onlistRemoteServers?: () => Promise<RemoteServer[]>;
    oncreateRemoteServer?: (request: RemoteServerRequest) => Promise<RemoteServer>;
    onupdateRemoteServer?: (
      id: string,
      request: RemoteServerRequest,
    ) => Promise<RemoteServer>;
    ondeleteRemoteServer?: (id: string) => Promise<{ deleted: boolean }>;
    onbrowseRemote?: (serverId: string) => Promise<RemoteBrowseResponse>;
    oninstallRemote?: (
      request: RemoteInstallRequest,
    ) => Promise<RegistryInstallResponse>;
    onclose: () => void;
  } = $props();

  type Tab = "general" | "library" | "scanDirs" | "tools" | "servers" | "about";

  const tabs: { id: Tab; title: string }[] = [
    { id: "general", title: "General" },
    { id: "library", title: "Library" },
    { id: "scanDirs", title: "Scan Directories" },
    { id: "tools", title: "Tools" },
    { id: "servers", title: "Servers" },
    { id: "about", title: "About" },
  ];

  const liveRemote = $derived(remoteEnabled ?? remoteServersEnabled());

  function fetchServers(): Promise<RemoteServer[]> {
    return onlistRemoteServers ? onlistRemoteServers() : Promise.resolve([]);
  }

  function createServer(request: RemoteServerRequest): Promise<RemoteServer> {
    if (oncreateRemoteServer) return oncreateRemoteServer(request);
    return Promise.resolve({
      id: request.id ?? "test",
      label: request.label,
      host: request.host,
      port: request.port ?? 22,
      username: request.username,
      skillsBasePath: request.skillsBasePath,
      sshKeyPath: request.sshKeyPath ?? null,
      lastSyncDate: null,
      lastSyncError: null,
    });
  }

  function updateServer(
    id: string,
    request: RemoteServerRequest,
  ): Promise<RemoteServer> {
    if (onupdateRemoteServer) return onupdateRemoteServer(id, request);
    return Promise.resolve({
      id,
      label: request.label,
      host: request.host,
      port: request.port ?? 22,
      username: request.username,
      skillsBasePath: request.skillsBasePath,
      sshKeyPath: request.sshKeyPath ?? null,
      lastSyncDate: null,
      lastSyncError: null,
    });
  }

  function deleteServer(id: string): Promise<{ deleted: boolean }> {
    return ondeleteRemoteServer
      ? ondeleteRemoteServer(id)
      : Promise.resolve({ deleted: true });
  }

  function browseRemote(serverId: string): Promise<RemoteBrowseResponse> {
    if (onbrowseRemote) return onbrowseRemote(serverId);
    return Promise.resolve({
      serverId,
      skills: [],
      lastSyncDate: "2026-10-22T00:00:00Z",
    });
  }

  function installRemote(
    request: RemoteInstallRequest,
  ): Promise<RegistryInstallResponse> {
    if (oninstallRemote) return oninstallRemote(request);
    return Promise.resolve({
      installed: true,
      skillName: request.remotePath,
      path: request.remotePath,
      targets: [],
      skill: null,
    });
  }

  let selectedTab = $state<Tab>("general");

  // Scan Directories pane (macOS `scanSettings`).
  let newRoot = $state("");
  let rootsError = $state<string | null>(null);

  const scanRoots = $derived(settings?.scanRoots ?? []);
  const theme = $derived(settings?.theme ?? "system");
  const listableTools = $derived(tools.filter((tool) => tool.listable));

  function abbreviate(path: string): string {
    const home = settings?.homeDirectory;
    if (!home) return path;
    return path.startsWith(home) ? `~${path.slice(home.length)}` : path;
  }

  function switchTab(tab: Tab): void {
    selectedTab = tab;
    rootsError = null;
  }

  function setTheme(theme: ThemeMode): void {
    ontheme(theme);
  }

  async function addRoot(): Promise<void> {
    const path = newRoot.trim();
    if (!path) return;
    if (scanRoots.includes(path)) {
      rootsError = "Directory already added.";
      return;
    }
    rootsError = null;
    try {
      await onupdateSettings({ scanRoots: [...scanRoots, path] });
      newRoot = "";
    } catch (error) {
      rootsError = error instanceof Error ? error.message : String(error);
    }
  }

  async function removeRoot(path: string): Promise<void> {
    rootsError = null;
    try {
      await onupdateSettings({
        scanRoots: scanRoots.filter((root) => root !== path),
      });
    } catch (error) {
      rootsError = error instanceof Error ? error.message : String(error);
    }
  }

  async function togglePluginSkills(checked: boolean): Promise<void> {
    rootsError = null;
    try {
      await onupdateSettings({ includePluginSkills: checked });
    } catch (error) {
      rootsError = error instanceof Error ? error.message : String(error);
    }
  }

  function handleKeydown(event: KeyboardEvent): void {
    if (!open) return;
    if (event.key === "Escape") {
      event.preventDefault();
      onclose();
    }
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
      aria-labelledby="settings-title"
      tabindex="-1"
    >
      <header class="sheet-header">
        <h2 id="settings-title">Settings</h2>
        <button type="button" class="close-button" onclick={onclose}>
          Close
        </button>
      </header>

      <nav class="tab-bar" aria-label="Settings sections">
        {#each tabs as tab (tab.id)}
          <button
            type="button"
            class="tab-button"
            class:active={selectedTab === tab.id}
            aria-pressed={selectedTab === tab.id}
            onclick={() => switchTab(tab.id)}
          >
            {tab.title}
          </button>
        {/each}
      </nav>

      <div class="tab-content">
        {#if selectedTab === "general"}
          <section class="pane" aria-label="General settings">
            <h3>General</h3>
            <div class="field">
              <label class="field-label" for="theme-select">Theme</label>
              <div class="segmented" role="group" aria-label="Theme">
                {#each ["system", "light", "dark"] as mode (mode)}
                  <button
                    type="button"
                    class="segment"
                    class:active={theme === mode}
                    aria-pressed={theme === mode}
                    onclick={() => setTheme(mode as ThemeMode)}
                  >
                    {mode === "system" ? "System" : mode === "light" ? "Light" : "Dark"}
                  </button>
                {/each}
              </div>
            </div>
          </section>
        {:else if selectedTab === "library"}
          <section class="pane" aria-label="Library settings">
            <h3>Library</h3>
            <div class="field">
              <label class="check-field">
                <input
                  type="checkbox"
                  checked={settings?.includePluginSkills ?? false}
                  onchange={(event) =>
                    void togglePluginSkills(event.currentTarget.checked)}
                />
                Include plugin skills
              </label>
              <p class="hint">
                When enabled, skills installed by Claude CLI and Claude Desktop
                plugins are listed in the library. These are read-only and managed
                by the plugin.
              </p>
            </div>
            <div class="field">
              <span class="field-label">Source of truth</span>
              <span class="mono">{abbreviate(settings?.sotDir ?? "—")}</span>
            </div>
          </section>
        {:else if selectedTab === "scanDirs"}
          <section class="pane" aria-label="Scan directories">
            <h3>Custom Scan Directories</h3>
            <p class="hint">
              Add a parent directory (e.g. ~/Development) and Chops scans each
              project inside it for tool-specific skills and agents.
            </p>
            {#if scanRoots.length === 0}
              <p class="empty">No custom directories added.</p>
            {:else}
              <ul class="roots-list">
                {#each scanRoots as path (path)}
                  <li>
                    <span class="mono root-path" title={path}>{abbreviate(path)}</span>
                    <button
                      type="button"
                      class="remove-root"
                      aria-label={`Remove ${path}`}
                      onclick={() => void removeRoot(path)}
                    >
                      −
                    </button>
                  </li>
                {/each}
              </ul>
            {/if}
            <form
              class="add-root"
              onsubmit={(event) => {
                event.preventDefault();
                void addRoot();
              }}
            >
              <input
                type="text"
                placeholder="/home/user/Development"
                aria-label="Add directory"
                bind:value={newRoot}
              />
              <button type="submit" disabled={!newRoot.trim()}>Add Directory</button>
            </form>
            {#if rootsError}
              <p class="sheet-error" role="alert">{rootsError}</p>
            {/if}
          </section>
        {:else if selectedTab === "tools"}
          <section class="pane" aria-label="Tools">
            <h3>Tools</h3>
            <p class="hint">
              Installed tools receive skills and agents. Tools that are not
              installed are listed but inactive, matching macOS.
            </p>
            <ul class="tools-list">
              {#each listableTools as tool (tool.id)}
                <li>
                  <span class="tool-name">{tool.displayName}</span>
                  <span
                    class="tool-status"
                    class:installed={tool.isInstalled}
                    title={tool.isInstalled ? "Installed" : "Not installed"}
                  >
                    {tool.isInstalled ? "Installed" : "Not installed"}
                  </span>
                </li>
              {/each}
            </ul>
          </section>
        {:else if selectedTab === "servers"}
          <RemoteServersPanel
            enabled={liveRemote}
            fetchServers={fetchServers}
            createServer={createServer}
            updateServer={updateServer}
            deleteServer={deleteServer}
            browseRemote={browseRemote}
            installRemote={installRemote}
          />
        {:else}
          <section class="pane" aria-label="About">
            <h3>About</h3>
            <p class="_about-name">Chops</p>
            <p class="hint">Your AI skills and agents, finally organized.</p>
            <dl class="paths">
              <dt>Home</dt>
              <dd class="mono">{abbreviate(settings?.homeDirectory ?? "—")}</dd>
              <dt>Settings</dt>
              <dd class="mono">{abbreviate(settings?.settingsPath ?? "—")}</dd>
              <dt>Database</dt>
              <dd class="mono">{abbreviate(settings?.databasePath ?? "—")}</dd>
            </dl>
          </section>
        {/if}

        {#if settingsError}
          <p class="sheet-error" role="alert">{settingsError}</p>
        {/if}
      </div>
    </div>
  </div>
{/if}

<style>
  .backdrop {
    position: fixed;
    inset: 0;
    z-index: 60;
    background: rgb(0 0 0 / 0.4);
  }

  .sheet-overlay {
    position: fixed;
    inset: 0;
    z-index: 61;
    display: flex;
    align-items: center;
    justify-content: center;
    pointer-events: none;
  }

  .sheet {
    pointer-events: auto;
    display: flex;
    flex-direction: column;
    width: 520px;
    max-width: calc(100vw - 40px);
    max-height: calc(100vh - 80px);
    border: 1px solid var(--border);
    border-radius: 10px;
    background: var(--panel);
    box-shadow: 0 12px 32px rgb(0 0 0 / 0.35);
    overflow: hidden;
  }

  .sheet-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 12px 16px;
    border-bottom: 1px solid var(--border);
  }

  .sheet-header h2 {
    margin: 0;
    font-size: 14px;
  }

  .close-button {
    padding: 3px 10px;
    border: 1px solid var(--border);
    border-radius: 6px;
    background: transparent;
    color: var(--text);
    font: inherit;
    font-size: 12px;
    cursor: default;
  }

  .tab-bar {
    display: flex;
    gap: 4px;
    padding: 8px 12px;
    border-bottom: 1px solid var(--border);
  }

  .tab-button {
    flex: 1;
    padding: 5px 4px;
    border: 0;
    border-radius: 6px;
    background: transparent;
    color: var(--muted);
    font: inherit;
    font-size: 12px;
    cursor: default;
  }

  .tab-button.active {
    background: var(--selected);
    color: var(--accent-strong);
  }

  .tab-button:focus-visible {
    outline: 2px solid var(--accent);
    outline-offset: -2px;
  }

  .tab-content {
    padding: 14px 16px;
    overflow-y: auto;
  }

  .pane {
    display: flex;
    flex-direction: column;
    gap: 10px;
  }

  .pane h3 {
    margin: 0;
    font-size: 13px;
  }

  .field {
    display: flex;
    flex-direction: column;
    gap: 6px;
  }

  .field-label {
    font-size: 13px;
  }

  .check-field {
    display: inline-flex;
    align-items: center;
    gap: 8px;
    font-size: 13px;
  }

  .segmented {
    display: inline-flex;
    border: 1px solid var(--border);
    border-radius: 7px;
    overflow: hidden;
    align-self: flex-start;
  }

  .segment {
    padding: 4px 12px;
    border: 0;
    background: transparent;
    color: var(--muted);
    font: inherit;
    font-size: 12px;
    cursor: default;
  }

  .segment.active {
    background: var(--selected);
    color: var(--accent-strong);
  }

  .check-field {
    display: inline-flex;
    align-items: center;
    gap: 8px;
    font-size: 13px;
  }

  .hint {
    margin: 0;
    font-size: 11px;
    color: var(--muted);
  }

  .mono {
    font-family: var(--mono);
    font-size: 12px;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .empty {
    margin: 0;
    font-size: 12px;
    color: var(--muted);
  }

  .roots-list {
    display: flex;
    flex-direction: column;
    margin: 0;
    padding: 0;
    border: 1px solid var(--border);
    border-radius: 6px;
    list-style: none;
  }

  .roots-list li {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 6px 8px;
  }

  .roots-list li + li {
    border-top: 1px solid var(--border);
  }

  .root-path {
    flex: 1;
    min-width: 0;
  }

  .remove-root {
    flex: 0 0 auto;
    width: 20px;
    height: 20px;
    padding: 0;
    border: 0;
    border-radius: 4px;
    background: transparent;
    color: var(--danger, #d33);
    font-size: 14px;
    line-height: 1;
    cursor: default;
  }

  .remove-root:hover {
    background: var(--hover);
  }

  .add-root {
    display: flex;
    gap: 8px;
  }

  .add-root input[type="text"] {
    flex: 1;
    min-width: 0;
    padding: 5px 8px;
    border: 1px solid var(--border);
    border-radius: 6px;
    background: var(--bg);
    color: var(--text);
    font: inherit;
    font-size: 12px;
    font-family: var(--mono);
  }

  .add-root button {
    flex: 0 0 auto;
    padding: 5px 10px;
    border: 1px solid var(--border);
    border-radius: 6px;
    background: transparent;
    color: var(--text);
    font: inherit;
    font-size: 12px;
    cursor: default;
  }

  .add-root button:disabled {
    opacity: 0.5;
  }

  .tools-list {
    display: flex;
    flex-direction: column;
    margin: 0;
    padding: 0;
    border: 1px solid var(--border);
    border-radius: 6px;
    list-style: none;
  }

  .tools-list li {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 6px 8px;
  }

  .tools-list li + li {
    border-top: 1px solid var(--border);
  }

  .tool-name {
    font-size: 13px;
  }

  .tool-status {
    font-size: 11px;
    color: var(--muted);
  }

  .tool-status.installed {
    color: var(--ok, #2e8b57);
  }

  .paths {
    display: grid;
    grid-template-columns: auto 1fr;
    gap: 4px 12px;
    margin: 0;
  }

  .paths dt {
    font-size: 12px;
    color: var(--muted);
  }

  .paths dd {
    margin: 0;
    min-width: 0;
  }

  .sheet-error {
    margin: 8px 0 0;
    font-size: 11px;
    color: var(--danger, #d33);
  }
</style>
