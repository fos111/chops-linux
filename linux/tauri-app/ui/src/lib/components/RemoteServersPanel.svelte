<script lang="ts">
  import { untrack } from "svelte";
  import type {
    RegistryInstallResponse,
    RemoteBrowseResponse,
    RemoteInstallRequest,
    RemoteServer,
    RemoteServerRequest,
    RemoteSkill,
  } from "$lib/api";

  // Remote servers pane (macOS `RemoteServersSettingsView` parity, flag-gated).
  // The live pane only renders when `enabled` is true; otherwise it is a static
  // disabled state so QA can assert that no SSH/API call happens.
  let {
    enabled,
    fetchServers,
    createServer,
    updateServer,
    deleteServer,
    browseRemote,
    installRemote,
  }: {
    enabled: boolean;
    fetchServers: () => Promise<RemoteServer[]>;
    createServer: (request: RemoteServerRequest) => Promise<RemoteServer>;
    updateServer: (
      id: string,
      request: RemoteServerRequest,
    ) => Promise<RemoteServer>;
    deleteServer: (id: string) => Promise<{ deleted: boolean }>;
    browseRemote: (serverId: string) => Promise<RemoteBrowseResponse>;
    installRemote: (
      request: RemoteInstallRequest,
    ) => Promise<RegistryInstallResponse>;
  } = $props();

  interface ServerForm {
    label: string;
    host: string;
    port: string;
    username: string;
    skillsBasePath: string;
    sshKeyPath: string;
  }

  function blankForm(): ServerForm {
    return {
      label: "",
      host: "",
      port: "22",
      username: "",
      skillsBasePath: "",
      sshKeyPath: "",
    };
  }

  let servers = $state<RemoteServer[]>([]);
  let loading = $state(false);
  let error = $state<string | null>(null);
  let notice = $state<string | null>(null);

  let adding = $state(false);
  let creating = $state(false);
  let addForm = $state<ServerForm>(blankForm());

  let editingId = $state<string | null>(null);
  let editForm = $state<ServerForm>(blankForm());
  let saving = $state(false);

  let deletingId = $state<string | null>(null);
  let browsingId = $state<string | null>(null);
  let browseResults = $state<Record<string, RemoteSkill[]>>({});
  let installingKey = $state<string | null>(null);
  let installedNotice = $state<string | null>(null);

  const addDisabled = $derived(
    toRequest(addForm) === null || creating,
  );

  function messageOf(value: unknown): string {
    return value instanceof Error ? value.message : String(value);
  }

  function sortServers(rows: RemoteServer[]): RemoteServer[] {
    return [...rows].sort((a, b) => a.label.localeCompare(b.label));
  }

  function toRequest(form: ServerForm): RemoteServerRequest | null {
    const label = form.label.trim();
    const host = form.host.trim();
    const username = form.username.trim();
    const skillsBasePath = form.skillsBasePath.trim();
    const port = Number(form.port);
    if (
      !label ||
      !host ||
      !username ||
      !skillsBasePath ||
      !Number.isInteger(port) ||
      port < 1 ||
      port > 65535
    ) {
      return null;
    }
    return {
      label,
      host,
      port,
      username,
      skillsBasePath,
      sshKeyPath: form.sshKeyPath.trim() || null,
    };
  }

  async function loadServers(): Promise<void> {
    loading = true;
    error = null;
    try {
      servers = sortServers(await fetchServers());
    } catch (loadError) {
      error = messageOf(loadError);
    } finally {
      loading = false;
    }
  }

  // Fetch once when the pane becomes live. Untracked so parent inline callbacks
  // do not retrigger the effect on unrelated store updates.
  $effect(() => {
    if (!enabled) return;
    untrack(() => {
      void loadServers();
    });
  });

  function toggleAdd(): void {
    adding = !adding;
    editingId = null;
    error = null;
  }

  async function addServer(): Promise<void> {
    const request = toRequest(addForm);
    if (!request || creating) return;
    creating = true;
    error = null;
    notice = null;
    try {
      const created = await createServer(request);
      servers = sortServers([
        ...servers.filter((row) => row.id !== created.id),
        created,
      ]);
      addForm = blankForm();
      adding = false;
      notice = `Added ${created.label}.`;
    } catch (createError) {
      error = messageOf(createError);
    } finally {
      creating = false;
    }
  }

  function startEdit(server: RemoteServer): void {
    adding = false;
    editingId = server.id;
    editForm = {
      label: server.label,
      host: server.host,
      port: String(server.port),
      username: server.username,
      skillsBasePath: server.skillsBasePath,
      sshKeyPath: server.sshKeyPath ?? "",
    };
    error = null;
  }

  function cancelEdit(): void {
    editingId = null;
    editForm = blankForm();
  }

  async function saveEdit(): Promise<void> {
    if (!editingId || saving) return;
    const request = toRequest(editForm);
    if (!request) return;
    saving = true;
    error = null;
    notice = null;
    try {
      const updated = await updateServer(editingId, request);
      servers = sortServers(
        servers.map((row) => (row.id === updated.id ? updated : row)),
      );
      editingId = null;
      notice = `Saved ${updated.label}.`;
    } catch (saveError) {
      error = messageOf(saveError);
    } finally {
      saving = false;
    }
  }

  async function removeServer(server: RemoteServer): Promise<void> {
    deletingId = server.id;
    error = null;
    notice = null;
    try {
      await deleteServer(server.id);
      servers = servers.filter((row) => row.id !== server.id);
      const remaining = { ...browseResults };
      delete remaining[server.id];
      browseResults = remaining;
      if (editingId === server.id) cancelEdit();
      notice = `Deleted ${server.label}.`;
    } catch (deleteError) {
      error = messageOf(deleteError);
    } finally {
      deletingId = null;
    }
  }

  async function browse(server: RemoteServer): Promise<void> {
    browsingId = server.id;
    error = null;
    installedNotice = null;
    try {
      const response = await browseRemote(server.id);
      browseResults = { ...browseResults, [server.id]: response.skills };
      servers = servers.map((row) =>
        row.id === server.id
          ? {
              ...row,
              lastSyncDate: response.lastSyncDate,
              lastSyncError: null,
            }
          : row,
      );
      notice = `Found ${response.skills.length} remote skill${
        response.skills.length === 1 ? "" : "s"
      } on ${server.label}.`;
    } catch (browseError) {
      error = messageOf(browseError);
    } finally {
      browsingId = null;
    }
  }

  async function install(server: RemoteServer, skill: RemoteSkill): Promise<void> {
    const key = `${server.id}:${skill.path}`;
    installingKey = key;
    error = null;
    installedNotice = null;
    try {
      const response = await installRemote({
        serverId: server.id,
        remotePath: skill.path,
      });
      installedNotice = `Installed ${response.skillName}.`;
    } catch (installError) {
      error = messageOf(installError);
    } finally {
      installingKey = null;
    }
  }
</script>

<section class="remote-pane" aria-label="Remote servers">
  <h3>Remote Servers</h3>

  {#if !enabled}
    <p class="empty" role="status">
      Remote servers are disabled. Set <code>VITE_ENABLE_REMOTE_SERVERS=1</code> to
      enable SSH browsing and installs.
    </p>
  {:else}
    <p class="hint">
      Connect to remote servers to browse and edit skills via SSH. Requires
      key-based authentication.
    </p>

    {#if loading}
      <p class="status" role="status">Loading remote servers…</p>
    {/if}
    {#if error}
      <p class="sheet-error" role="alert">{error}</p>
    {/if}
    {#if notice}
      <p class="status" role="status">{notice}</p>
    {/if}
    {#if installedNotice}
      <p class="status installed" role="status">{installedNotice}</p>
    {/if}

    {#if !loading && servers.length === 0}
      <p class="empty">No remote servers configured.</p>
    {/if}

    <ul class="server-list">
      {#each servers as server (server.id)}
        <li>
          {#if editingId === server.id}
            <div class="server-form" aria-label={`Edit ${server.label}`}>
              <div class="form-grid">
                <label for="remote-edit-label">Label</label>
                <input id="remote-edit-label" bind:value={editForm.label} />
                <label for="remote-edit-host">Host</label>
                <input id="remote-edit-host" bind:value={editForm.host} />
                <label for="remote-edit-port">Port</label>
                <input
                  id="remote-edit-port"
                  inputmode="numeric"
                  bind:value={editForm.port}
                />
                <label for="remote-edit-username">Username</label>
                <input id="remote-edit-username" bind:value={editForm.username} />
                <label for="remote-edit-base">Skills base path</label>
                <input id="remote-edit-base" bind:value={editForm.skillsBasePath} />
                <label for="remote-edit-key">SSH key path</label>
                <input id="remote-edit-key" bind:value={editForm.sshKeyPath} />
              </div>
              <div class="form-actions">
                <button type="button" onclick={cancelEdit}>Cancel</button>
                <button
                  type="button"
                  class="primary"
                  disabled={toRequest(editForm) === null || saving}
                  onclick={() => void saveEdit()}
                >
                  {saving ? "Saving…" : "Save Server"}
                </button>
              </div>
            </div>
          {:else}
            <div class="server-row">
              <div class="server-info">
                <span class="server-label">{server.label}</span>
                <span class="mono"
                  >{server.username}@{server.host}:{server.port}</span
                >
                <span class="mono path" title={server.skillsBasePath}
                  >Path: {server.skillsBasePath}</span
                >
                {#if server.lastSyncDate}
                  <span class="sync">Synced {server.lastSyncDate}</span>
                {/if}
                {#if server.lastSyncError}
                  <span class="server-error" role="alert">{server.lastSyncError}</span>
                {/if}
              </div>
              <div class="server-actions">
                <button
                  type="button"
                  aria-label={`Browse ${server.label}`}
                  disabled={browsingId === server.id}
                  onclick={() => void browse(server)}
                >
                  {browsingId === server.id ? "Browsing…" : "Browse"}
                </button>
                <button
                  type="button"
                  aria-label={`Edit ${server.label}`}
                  onclick={() => startEdit(server)}
                >
                  Edit
                </button>
                <button
                  type="button"
                  class="danger"
                  aria-label={`Delete ${server.label}`}
                  disabled={deletingId === server.id}
                  onclick={() => void removeServer(server)}
                >
                  {deletingId === server.id ? "Deleting…" : "Delete"}
                </button>
              </div>
            </div>
          {/if}

          {#if browseResults[server.id] !== undefined}
            <div class="remote-skills" aria-label={`Remote skills on ${server.label}`}>
              {#if browseResults[server.id].length === 0}
                <p class="empty">No skills found.</p>
              {:else}
                <ul>
                  {#each browseResults[server.id] as skill (skill.path)}
                    <li>
                      <div class="remote-skill-info">
                        <span class="remote-skill-name">{skill.name}</span>
                        <span class="mono path" title={skill.path}>{skill.path}</span>
                        {#if skill.description}
                          <span class="hint">{skill.description}</span>
                        {/if}
                      </div>
                      <button
                        type="button"
                        aria-label={`Install ${skill.name}`}
                        disabled={installingKey === `${server.id}:${skill.path}`}
                        onclick={() => void install(server, skill)}
                      >
                        {installingKey === `${server.id}:${skill.path}`
                          ? "Installing…"
                          : "Install"}
                      </button>
                    </li>
                  {/each}
                </ul>
              {/if}
            </div>
          {/if}
        </li>
      {/each}
    </ul>

    {#if adding}
      <form
        class="server-form"
        aria-label="Add remote server"
        onsubmit={(event) => {
          event.preventDefault();
          void addServer();
        }}
      >
        <div class="form-grid">
          <label for="remote-add-label">Label</label>
          <input
            id="remote-add-label"
            placeholder="Production Server"
            bind:value={addForm.label}
          />
          <label for="remote-add-host">Host</label>
          <input
            id="remote-add-host"
            placeholder="192.168.1.100"
            bind:value={addForm.host}
          />
          <label for="remote-add-port">Port</label>
          <input
            id="remote-add-port"
            inputmode="numeric"
            bind:value={addForm.port}
          />
          <label for="remote-add-username">Username</label>
          <input
            id="remote-add-username"
            placeholder="root"
            bind:value={addForm.username}
          />
          <label for="remote-add-base">Skills base path</label>
          <input
            id="remote-add-base"
            placeholder="~/.hermes/skills"
            bind:value={addForm.skillsBasePath}
          />
          <label for="remote-add-key">SSH key path</label>
          <input
            id="remote-add-key"
            placeholder="Optional — ~/.ssh/id_ed25519"
            bind:value={addForm.sshKeyPath}
          />
        </div>
        <div class="form-actions">
          <button type="button" onclick={() => (adding = false)}>Cancel</button>
          <button type="submit" class="primary" disabled={addDisabled}>
            {creating ? "Adding…" : "Add Server"}
          </button>
        </div>
      </form>
    {:else}
      <button
        type="button"
        class="add-server"
        aria-label="Add remote server"
        onclick={toggleAdd}
      >
        Add Server…
      </button>
    {/if}
  {/if}
</section>

<style>
  .remote-pane {
    display: flex;
    flex-direction: column;
    gap: 10px;
  }

  .remote-pane h3 {
    margin: 0;
    font-size: 13px;
  }

  .hint {
    margin: 0;
    font-size: 11px;
    color: var(--muted);
  }

  .empty {
    margin: 0;
    font-size: 12px;
    color: var(--muted);
  }

  .empty code {
    font-family: var(--mono);
    font-size: 11px;
  }

  .status {
    margin: 0;
    font-size: 11px;
    color: var(--muted);
  }

  .status.installed {
    color: var(--ok, #2e8b57);
  }

  .sheet-error {
    margin: 0;
    font-size: 11px;
    color: var(--danger, #d33);
    overflow-wrap: anywhere;
  }

  .server-list,
  .remote-skills ul {
    display: flex;
    flex-direction: column;
    margin: 0;
    padding: 0;
    border: 1px solid var(--border);
    border-radius: 6px;
    list-style: none;
  }

  .server-list > li + li {
    border-top: 1px solid var(--border);
  }

  .server-row {
    display: flex;
    align-items: flex-start;
    gap: 8px;
    padding: 8px;
  }

  .server-info {
    display: flex;
    flex: 1;
    min-width: 0;
    flex-direction: column;
    gap: 2px;
  }

  .server-label {
    font-size: 13px;
    font-weight: 600;
  }

  .mono {
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    font-family: var(--mono);
    font-size: 11px;
  }

  .path {
    color: var(--muted);
  }

  .sync {
    font-size: 10.5px;
    color: var(--muted);
  }

  .server-error {
    font-size: 10.5px;
    color: var(--danger, #d33);
  }

  .server-actions {
    display: flex;
    flex: 0 0 auto;
    gap: 4px;
  }

  button {
    padding: 3px 9px;
    border: 1px solid var(--border);
    border-radius: 5px;
    background: transparent;
    color: var(--text);
    font: inherit;
    font-size: 11px;
  }

  button:disabled {
    opacity: 0.5;
  }

  .primary {
    background: var(--selected);
    color: var(--accent-strong);
  }

  .danger {
    color: var(--danger, #d33);
  }

  .remote-skills {
    padding: 0 8px 8px;
  }

  .remote-skills ul {
    margin-top: 4px;
  }

  .remote-skills li {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 6px 8px;
  }

  .remote-skills li + li {
    border-top: 1px solid var(--border);
  }

  .remote-skill-info {
    display: flex;
    flex: 1;
    min-width: 0;
    flex-direction: column;
    gap: 1px;
  }

  .remote-skill-name {
    font-size: 12px;
    font-weight: 600;
  }

  .server-form {
    display: flex;
    flex-direction: column;
    gap: 8px;
    padding: 8px;
    border: 1px solid var(--border);
    border-radius: 6px;
    background: var(--panel-alt);
  }

  .form-grid {
    display: grid;
    grid-template-columns: 110px 1fr;
    gap: 6px 8px;
    align-items: center;
  }

  .form-grid label {
    font-size: 11.5px;
  }

  .form-grid input {
    min-width: 0;
    padding: 4px 7px;
    border: 1px solid var(--border);
    border-radius: 5px;
    background: var(--bg);
    color: var(--text);
    font: inherit;
    font-family: var(--mono);
    font-size: 11.5px;
  }

  .form-actions {
    display: flex;
    justify-content: flex-end;
    gap: 6px;
  }

  .add-server {
    align-self: flex-start;
  }
</style>
