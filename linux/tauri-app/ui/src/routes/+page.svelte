<script lang="ts">
  import { onMount } from "svelte";
  import type { SkillCreateRequest } from "$lib/api";
  import { app } from "$lib/app.svelte.js";
  import { filterTitle } from "$lib/filters";
  import { buildPaletteCommands, isPaletteShortcut, isSidebarShortcut, type PaletteCommand } from "$lib/palette";
  import CommandPalette from "$lib/components/CommandPalette.svelte";
  import ConfirmDiscardDialog from "$lib/components/ConfirmDiscardDialog.svelte";
  import NewSkillSheet from "$lib/components/NewSkillSheet.svelte";
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

  let sheetOpen = $state(false);

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
      filter={app.filter}
      onselect={(filter) => app.requestSetFilter(filter)}
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
      error={app.loadError}
      onselect={(id) => app.requestSelectSkill(id)}
      onsearch={(text) => app.setSearchText(text)}
      onretry={() => app.retry()}
      ontoggleSidebar={() => app.toggleSidebar()}
      onnew={() => (sheetOpen = true)}
    />
  </div>

  <div class="shell-detail">
    <SkillEditor
      skill={app.selectedSkill}
      tools={app.tools}
      homeDirectory={app.settings?.homeDirectory ?? null}
      onsave={saveCurrent}
      onunsaved={(dirty) => app.setUnsaved(dirty)}
      onnew={() => (sheetOpen = true)}
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
