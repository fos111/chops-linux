<script lang="ts">
  import { onMount } from "svelte";
  import type {
    AssistRequest,
    CollectionSummary,
    RemoteInstallRequest,
    RemoteServerRequest,
    SettingsPatch,
    SkillCreateRequest,
    ThemeMode,
  } from "$lib/api";
  import { app } from "$lib/app.svelte.js";
  import { filterTitle } from "$lib/filters";
  import { buildPaletteCommands, isPaletteShortcut, isSidebarShortcut, type PaletteCommand } from "$lib/palette";
  import CommandPalette from "$lib/components/CommandPalette.svelte";
  import ConfirmDiscardDialog from "$lib/components/ConfirmDiscardDialog.svelte";
  import NewSkillSheet from "$lib/components/NewSkillSheet.svelte";
  import RegistrySheet from "$lib/components/RegistrySheet.svelte";
  import SettingsSheet from "$lib/components/SettingsSheet.svelte";
  import Sidebar from "$lib/components/Sidebar.svelte";
  import SkillEditor from "$lib/components/SkillEditor.svelte";
  import SkillList from "$lib/components/SkillList.svelte";
  import StatusBar from "$lib/components/StatusBar.svelte";

  const title = $derived(filterTitle(app.filter, app.tools));
  const commands = $derived(buildPaletteCommands(app.tools));
  const showTypeBadge = $derived(
    app.filter.type === "tool" ||
      app.filter.type === "favorites" ||
      app.filter.type === "collection" ||
      app.filter.type === "server",
  );
  const collectionMode = $derived(app.filter.type === "collection");
  const listError = $derived(app.loadError ?? app.collectionDetailError);

  let sheetOpen = $state(false);
  let registryOpen = $state(false);
  let settingsOpen = $state(false);

  function handleGlobalKeydown(event: KeyboardEvent): void {
    if (event.defaultPrevented) return;

    if (isPaletteShortcut(event)) {
      event.preventDefault();
      app.openPalette();
    } else if (isSidebarShortcut(event)) {
      event.preventDefault();
      app.toggleSidebar();
    }
  }

  function handleBeforeUnload(event: BeforeUnloadEvent): void {
    if (!app.unsaved) return;
    event.preventDefault();
    event.returnValue = "";
  }

  function runPaletteCommand(command: PaletteCommand): void {
    if (command.action.type === "navigate") {
      app.runPaletteAction(command.action.filter);
    }
  }

  function saveCurrent(content: string): Promise<unknown> {
    const skill = app.selectedSkill;
    if (!skill) return Promise.reject(new Error("No skill selected"));
    return app.saveSkill(skill.id, content);
  }

  async function createItem(request: SkillCreateRequest): Promise<void> {
    await app.createSkill(request);
    sheetOpen = false;
  }

  async function createCollection(request: {
    name: string;
    icon: string;
  }): Promise<unknown> {
    return app.createCollection(request.name, request.icon);
  }

  function removeMember(id: number): void {
    const collection = app.collections.find(
      (row) => app.filter.type === "collection" && row.name === app.filter.name,
    );
    if (!collection) return;
    void app.removeFromCollection(id, collection);
  }

  function toggleCollection(collection: CollectionSummary): void {
    const skill = app.selectedSkill;
    if (!skill) return;
    void app.toggleCollectionMembership(skill, collection);
  }

  function openSettingsFromSidebar(): void {
    settingsOpen = true;
  }

  function saveSettings(patch: SettingsPatch): Promise<unknown> {
    return app.saveSettings(patch);
  }

  function applyThemeSetting(theme: ThemeMode): void {
    void app.setTheme(theme);
  }

  // MARK: Assist wiring (compose panel → POST /api/assist → diff gate)

  function sendAssist(request: AssistRequest) {
    return app.assist(request);
  }

  function acceptAssist(pendingId: string) {
    return app.acceptAssist(pendingId);
  }

  function rejectAssist(pendingId: string) {
    return app.rejectAssist(pendingId);
  }

  // MARK: Remote servers wiring (pane is flag-gated inside SettingsSheet)

  function listRemoteServers() {
    return app.listRemoteServers();
  }

  function createRemoteServer(request: RemoteServerRequest) {
    return app.createRemoteServer(request);
  }

  function updateRemoteServer(id: string, request: RemoteServerRequest) {
    return app.updateRemoteServer(id, request);
  }

  function deleteRemoteServer(id: string) {
    return app.deleteRemoteServer(id);
  }

  function browseRemote(serverId: string) {
    return app.browseRemote(serverId);
  }

  function installRemote(request: RemoteInstallRequest) {
    return app.installRemote(request);
  }

  onMount(() => {
    const stop = app.start();
    window.addEventListener("keydown", handleGlobalKeydown);
    window.addEventListener("beforeunload", handleBeforeUnload);
    return () => {
      window.removeEventListener("keydown", handleGlobalKeydown);
      window.removeEventListener("beforeunload", handleBeforeUnload);
      stop();
    };
  });
</script>

<div class="shell" class:sidebar-hidden={!app.sidebarVisible}>
  <aside class="shell-sidebar">
    <Sidebar
      tools={app.tools}
      skills={app.skills}
      collections={app.collections}
      filter={app.filter}
      onselect={(filter) => app.requestSetFilter(filter)}
      oncreateCollection={createCollection}
      ondeleteCollection={(collection) => void app.deleteCollection(collection.id)}
      onopenRegistry={() => (registryOpen = true)}
      onopenSettings={openSettingsFromSidebar}
    />
  </aside>

  <div class="shell-list">
    <SkillList
      skills={app.visibleSkills}
      {title}
      searchText={app.searchText}
      selectedId={app.selectedId}
      {showTypeBadge}
      loading={app.loading}
      error={listError}
      onselect={(id) => app.requestSelectSkill(id)}
      onsearch={(text) => app.setSearchText(text)}
      onretry={() => app.retry()}
      ontoggleSidebar={() => app.toggleSidebar()}
      onnew={() => (sheetOpen = true)}
      onremoveMember={collectionMode ? removeMember : undefined}
    />
  </div>

  <div class="shell-detail">
    <SkillEditor
      skill={app.selectedSkill}
      tools={app.tools}
      homeDirectory={app.settings?.homeDirectory ?? null}
      collections={app.collections}
      onsave={saveCurrent}
      onunsaved={(dirty) => app.setUnsaved(dirty)}
      onnew={() => (sheetOpen = true)}
      ontoggleCollection={toggleCollection}
      onassist={sendAssist}
      onacceptassist={acceptAssist}
      onrejectassist={rejectAssist}
    />
  </div>

  <footer class="shell-status">
    <StatusBar
      connection={app.connection}
      total={app.skills.length}
      visible={app.visibleSkills.length}
      unsaved={app.unsaved}
      theme={app.theme}
      settingsError={app.settingsError}
      ontheme={(theme) => void app.setTheme(theme)}
    />
  </footer>
</div>

<CommandPalette
  open={app.paletteOpen}
  {commands}
  onaction={runPaletteCommand}
  onclose={() => app.closePalette()}
/>

<NewSkillSheet
  open={sheetOpen}
  tools={app.tools}
  oncreate={createItem}
  onclose={() => (sheetOpen = false)}
/>

<RegistrySheet
  open={registryOpen}
  tools={app.tools}
  fetchTrending={() => app.fetchTrending()}
  searchSkills={(q) => app.searchRegistry(q)}
  oninstall={(request) => app.installRegistrySkill(request)}
  onclose={() => (registryOpen = false)}
/>

<SettingsSheet
  open={settingsOpen}
  settings={app.settings}
  tools={app.tools}
  settingsError={app.settingsError}
  onupdateSettings={saveSettings}
  ontheme={applyThemeSetting}
  onlistRemoteServers={listRemoteServers}
  oncreateRemoteServer={createRemoteServer}
  onupdateRemoteServer={updateRemoteServer}
  ondeleteRemoteServer={deleteRemoteServer}
  onbrowseRemote={browseRemote}
  oninstallRemote={installRemote}
  onclose={() => (settingsOpen = false)}
/>

<ConfirmDiscardDialog
  open={app.pendingNavigation !== null}
  ondiscard={() => app.confirmDiscard()}
  oncancel={() => app.cancelDiscard()}
/>

<style>
  .shell {
    display: grid;
    grid-template-columns: 220px 340px minmax(0, 1fr);
    grid-template-rows: minmax(0, 1fr) 28px;
    height: 100vh;
    overflow: hidden;
    background: var(--bg);
  }

  .shell.sidebar-hidden {
    grid-template-columns: 0 340px minmax(0, 1fr);
  }

  .shell-sidebar {
    min-width: 0;
    min-height: 0;
    overflow: hidden;
  }

  .shell-list,
  .shell-detail {
    min-width: 0;
    min-height: 0;
  }

  .shell-status {
    grid-column: 1 / -1;
    min-width: 0;
  }

  @media (max-width: 1120px) {
    .shell {
      grid-template-columns: 196px 300px minmax(0, 1fr);
    }

    .shell.sidebar-hidden {
      grid-template-columns: 0 300px minmax(0, 1fr);
    }
  }
</style>
