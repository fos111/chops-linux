<script lang="ts">
  import { onMount } from "svelte";
  import { app } from "$lib/app.svelte.js";
  import { filterTitle } from "$lib/filters";
  import { buildPaletteCommands, isPaletteShortcut, isSidebarShortcut, type PaletteCommand } from "$lib/palette";
  import CommandPalette from "$lib/components/CommandPalette.svelte";
  import DetailPlaceholder from "$lib/components/DetailPlaceholder.svelte";
  import Sidebar from "$lib/components/Sidebar.svelte";
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

  function runPaletteCommand(command: PaletteCommand): void {
    if (command.action.type === "navigate") {
      app.runPaletteAction(command.action.filter);
    }
  }

  onMount(() => {
    const stop = app.start();
    window.addEventListener("keydown", handleGlobalKeydown);
    return () => {
      window.removeEventListener("keydown", handleGlobalKeydown);
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
      onselect={(filter) => app.setFilter(filter)}
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
      onselect={(id) => app.selectSkill(id)}
      onsearch={(text) => app.setSearchText(text)}
      onretry={() => app.retry()}
      ontoggleSidebar={() => app.toggleSidebar()}
    />
  </div>

  <div class="shell-detail">
    <DetailPlaceholder skill={app.selectedSkill} tools={app.tools} />
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
