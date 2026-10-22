// Application store for the three-column shell.
//
// Svelte 5 runes live in a `.svelte.ts` module so the components stay presentational
// and the tests can drive the store with a fake `ChopsApi`. All product state
// (filter, search, selection, theme) lives here; nothing is persisted to
// localStorage — theme persistence is chopsd's `settings.json` via `PUT /api/settings`.

import {
  createApiClient,
  type AssistAcceptResponse,
  type AssistRejectResponse,
  type AssistRequest,
  type AssistResponse,
  type ChopsApi,
  type CollectionDetail,
  type CollectionSummary,
  type ConnectionState,
  type EventConnection,
  type RegistryInstallRequest,
  type RegistryInstallResponse,
  type RegistrySkill,
  type RemoteBrowseResponse,
  type RemoteInstallRequest,
  type RemoteServer,
  type RemoteServerRequest,
  type Settings,
  type SettingsPatch,
  type Skill,
  type SkillCreateRequest,
  type ThemeMode,
  type Tool,
  type WsEvent,
} from "./api";
import {
  filterKey,
  filterSkills,
  reconcileSelection,
  sortSkills,
  type SidebarFilter,
} from "./filters";
import { filterCollectionDetail, sortCollections } from "./collections";
import { applyTheme, resolveTheme, systemPrefersDark, watchSystemTheme } from "./theme";

function toMessage(error: unknown): string {
  if (error instanceof Error) return error.message;
  return String(error);
}

/** Deferred navigation while the editor has unsaved changes. */
export type PendingNavigation =
  | { type: "select"; id: number }
  | { type: "filter"; filter: SidebarFilter };

export interface ChopsAppOptions {
  /** Debounce for `file-changed` bursts; 150 ms matches a single editor write. */
  refreshDebounceMs?: number;
  /** Injectable for tests; defaults to the real browser media query. */
  prefersDark?: () => boolean;
  watchSystem?: (listener: (prefersDark: boolean) => void) => () => void;
}

export class ChopsApp {
  ready: Promise<void>;

  tools = $state<Tool[]>([]);
  skills = $state<Skill[]>([]);
  settings = $state<Settings | null>(null);
  /** Sidebar collections (`GET /api/collections`, sorted by sortOrder). */
  collections = $state<CollectionSummary[]>([]);
  /**
   * Server-authoritative members of the collection filter currently active
   * (`GET /api/collections/{id}`); null while loading, with its own error lane.
   */
  collectionDetail = $state<CollectionDetail | null>(null);
  collectionsError = $state<string | null>(null);

  filter = $state<SidebarFilter>({ type: "allSkills" });
  searchText = $state("");
  selectedId = $state<number | null>(null);

  theme = $state<ThemeMode>("system");
  systemDark = $state(false);
  connection = $state<ConnectionState>("disconnected");
  loading = $state(false);
  loadError = $state<string | null>(null);
  settingsError = $state<string | null>(null);
  /** T15 sets this from the editor; the status bar renders the chip. */
  unsaved = $state(false);

  paletteOpen = $state(false);
  sidebarVisible = $state(true);
  /** Non-null while a dirty editor is blocking a selection/filter change. */
  pendingNavigation = $state<PendingNavigation | null>(null);
  collectionDetailError = $state<string | null>(null);

  /** Skills actually shown in the list column for the active filter. */
  visibleSkills = $derived.by(() => {
    if (this.filter.type === "collection" && this.collectionDetail) {
      return sortSkills(
        filterCollectionDetail(
          this.collectionDetail.skills,
          this.searchText,
        ),
      );
    }
    return filterSkills(this.skills, this.filter, this.searchText);
  });
  selectedSkill = $derived(
    this.skills.find((skill) => skill.id === this.selectedId) ?? null,
  );
  resolvedTheme = $derived(resolveTheme(this.theme, this.systemDark));

  #client: ChopsApi;
  #events: EventConnection | null = null;
  #refreshTimer: ReturnType<typeof setTimeout> | null = null;
  #unsubscribeTheme: () => void = () => {};
  #refreshDebounceMs: number;
  #prefersDark: () => boolean;
  #watchSystem: (listener: (prefersDark: boolean) => void) => () => void;
  #themeRequestId = 0;
  #started = false;

  constructor(client: ChopsApi = createApiClient(), options: ChopsAppOptions = {}) {
    this.#client = client;
    this.#refreshDebounceMs = options.refreshDebounceMs ?? 150;
    this.#prefersDark = options.prefersDark ?? (() => systemPrefersDark());
    this.#watchSystem =
      options.watchSystem ??
      ((listener) => watchSystemTheme((dark) => listener(dark)));
    this.ready = Promise.resolve();
  }

  /** Wires live updates and returns the cleanup for `onMount`. */
  start(): () => void {
    if (this.#started) return () => this.stop();
    this.#started = true;
    this.connection = "connecting";
    this.systemDark = this.#prefersDark();
    applyTheme(this.theme);
    // In `system` mode the CSS media query follows the OS on its own; the state is
    // kept for the status bar and tests.
    this.#unsubscribeTheme = this.#watchSystem((prefersDark) => {
      this.systemDark = prefersDark;
    });
    this.ready = this.#bootstrap();
    return () => this.stop();
  }

  async #bootstrap(): Promise<void> {
    const [settingsResult, toolsResult, skillsResult, collectionsResult] =
      await Promise.allSettled([
        this.#client.getSettings(),
        this.#client.listTools(),
        this.#client.listSkills(),
        this.#client.listCollections(),
      ]);

    if (settingsResult.status === "fulfilled") {
      this.settings = settingsResult.value;
      this.theme = settingsResult.value.theme;
      applyTheme(this.theme);
    } else {
      this.settingsError = toMessage(settingsResult.reason);
    }

    if (toolsResult.status === "fulfilled") {
      this.tools = toolsResult.value;
    }

    if (skillsResult.status === "fulfilled") {
      this.skills = sortSkills(skillsResult.value);
      this.selectedId = reconcileSelection(this.visibleSkills, this.selectedId);
    }

    if (collectionsResult.status === "fulfilled") {
      this.collections = sortCollections(collectionsResult.value);
    } else {
      this.collectionsError = toMessage(collectionsResult.reason);
    }

    const failure =
      toolsResult.status === "rejected"
        ? toolsResult.reason
        : skillsResult.status === "rejected"
          ? skillsResult.reason
          : null;
    this.loadError = failure ? toMessage(failure) : null;

    this.#connect();
  }

  #connect(): void {
    if (this.#events) return;
    this.#events = this.#client.connectEvents({
      onEvent: (event) => this.handleEvent(event),
      onStatus: (state) => {
        this.connection = state;
        if (state === "connected") {
          // A first connection (or a reconnect after chopsd restarts) catches the
          // list up on anything missed while the socket was down.
          void this.refresh();
        }
      },
    });
  }

  handleEvent(event: WsEvent): void {
    if (event.type !== "rescan" && event.type !== "file-changed") return;
    if (this.#refreshTimer !== null) clearTimeout(this.#refreshTimer);
    this.#refreshTimer = setTimeout(() => {
      this.#refreshTimer = null;
      void this.refresh();
    }, this.#refreshDebounceMs);
  }

  async refresh(): Promise<void> {
    this.loading = true;
    try {
      const [tools, skills] = await Promise.all([
        this.#client.listTools(),
        this.#client.listSkills(),
      ]);
      this.tools = tools;
      this.skills = sortSkills(skills);
      this.selectedId = reconcileSelection(this.visibleSkills, this.selectedId);
      this.loadError = null;
    } catch (error) {
      this.loadError = toMessage(error);
    } finally {
      this.loading = false;
    }
  }

  /** Retry from the error banner: reloads settings and the library. */
  retry(): void {
    void this.#reloadSettings();
    void this.refresh();
  }

  async #reloadSettings(): Promise<void> {
    try {
      const settings = await this.#client.getSettings();
      this.settings = settings;
      this.theme = settings.theme;
      applyTheme(this.theme);
      this.settingsError = null;
    } catch (error) {
      this.settingsError = toMessage(error);
    }
  }

  setFilter(filter: SidebarFilter): void {
    this.filter = filter;
    this.selectedId = reconcileSelection(this.visibleSkills, this.selectedId);
    this.#syncCollectionDetail(filter);
  }

  /**
   * Collection filters render the server-authoritative member list
   * (`GET /api/collections/{id}`); every other filter clears it.
   */
  #syncCollectionDetail(filter: SidebarFilter): void {
    if (filter.type !== "collection") {
      this.collectionDetail = null;
      this.collectionDetailError = null;
      return;
    }
    const collection = this.collections.find((row) => row.name === filter.name);
    const key = filterKey(filter);
    void this.#loadCollectionDetail(collection?.id ?? null, key);
  }

  async #loadCollectionDetail(
    id: number | null,
    filterKeyValue: string,
  ): Promise<void> {
    if (id === null) {
      // The filter points at a collection that vanished from the sidebar list
      // (e.g. deleted): no members to show, so the list falls back to the local
      // name filter and the detail lane records why.
      this.collectionDetail = null;
      this.collectionDetailError = null;
      return;
    }
    this.collectionDetail = null;
    try {
      const detail = await this.#client.getCollection(id);
      if (filterKey(this.filter) !== filterKeyValue) return; // stale response
      this.collectionDetail = detail;
      this.selectedId = reconcileSelection(this.visibleSkills, this.selectedId);
    } catch (error) {
      if (filterKey(this.filter) !== filterKeyValue) return;
      this.collectionDetailError = toMessage(error);
    }
  }

  /**
   * User-initiated navigation (list click, sidebar filter, palette). Mirrors the
   * macOS guard behavior: if the editor is dirty the change is parked until the
   * user chooses Discard or Cancel in `pendingNavigation`.
   */
  requestSelectSkill(id: number): void {
    if (id === this.selectedId) return;
    if (this.unsaved) {
      this.pendingNavigation = { type: "select", id };
      return;
    }
    this.selectSkill(id);
  }

  requestSetFilter(filter: SidebarFilter): void {
    if (filterKey(filter) === filterKey(this.filter)) {
      this.setFilter(filter);
      return;
    }
    if (this.unsaved) {
      this.pendingNavigation = { type: "filter", filter };
      return;
    }
    this.setFilter(filter);
  }

  /** Applies the parked navigation (the editor drops its draft on load). */
  confirmDiscard(): void {
    const pending = this.pendingNavigation;
    this.pendingNavigation = null;
    if (!pending) return;
    this.unsaved = false;
    if (pending.type === "select") {
      this.selectSkill(pending.id);
    } else {
      this.setFilter(pending.filter);
    }
  }

  cancelDiscard(): void {
    this.pendingNavigation = null;
  }

  setSearchText(text: string): void {
    this.searchText = text;
  }

  selectSkill(id: number): void {
    this.selectedId = id;
  }

  toggleSidebar(): void {
    this.sidebarVisible = !this.sidebarVisible;
  }

  openPalette(): void {
    this.paletteOpen = true;
  }

  closePalette(): void {
    this.paletteOpen = false;
  }

  runPaletteAction(filter: SidebarFilter): void {
    this.paletteOpen = false;
    this.requestSetFilter(filter);
  }

  /** Saves the complete Markdown file through chopsd and refreshes the list row. */
  async saveSkill(id: number, content: string): Promise<Skill> {
    const saved = await this.#client.updateSkill(id, content);
    this.#replaceSkill(saved);
    this.unsaved = false;
    return saved;
  }

  /** Creates a template file in chopsd, then selects it like the macOS sheet. */
  async createSkill(request: SkillCreateRequest): Promise<Skill> {
    const created = await this.#client.createSkill(request);
    this.#replaceSkill(created);
    this.unsaved = false;
    switch (created.kind) {
      case "agent":
        this.setFilter({ type: "allAgents" });
        break;
      case "rule":
        this.setFilter({ type: "allRules" });
        break;
      default:
        this.setFilter({ type: "allSkills" });
        break;
    }
    this.selectSkill(created.id);
    return created;
  }

  #replaceSkill(skill: Skill): void {
    const index = this.skills.findIndex((row) => row.id === skill.id);
    const next = [...this.skills];
    if (index >= 0) {
      next[index] = skill;
    } else {
      next.push(skill);
    }
    this.skills = sortSkills(next);
  }

  // MARK: Assist (one compose turn + the diff-review gate)

  /** `POST /api/assist`: the only compose path, called from an explicit Send click. */
  assist(request: AssistRequest): Promise<AssistResponse> {
    return this.#client.assist(request);
  }

  /**
   * `POST /api/assist/{id}/accept`: chopsd writes the pending file (local or over
   * SSH) and returns the re-scanned skill row.
   */
  async acceptAssist(pendingId: string): Promise<AssistAcceptResponse> {
    const response = await this.#client.acceptAssist(pendingId);
    if (response.skill) {
      this.#replaceSkill(response.skill);
      if (this.selectedId === response.skill.id) this.unsaved = false;
    }
    return response;
  }

  /** `POST /api/assist/{id}/reject`: chopsd discards the pending write. */
  rejectAssist(pendingId: string): Promise<AssistRejectResponse> {
    return this.#client.rejectAssist(pendingId);
  }

  // MARK: Collections (chopsd join-table CRUD + membership helpers)

  async refreshCollections(): Promise<void> {
    try {
      this.collections = sortCollections(await this.#client.listCollections());
      this.collectionsError = null;
    } catch (error) {
      this.collectionsError = toMessage(error);
    }
  }

  /** Creates through chopsd, then reconciles the sidebar list. */
  async createCollection(name: string, icon: string): Promise<CollectionSummary> {
    const created = await this.#client.createCollection({ name, icon });
    await this.refreshCollections();
    return created;
  }

  /**
   * Deletes through chopsd and slides the sidebar off the vanished filter
   * (chopsd cascades the membership rows in the store).
   */
  async deleteCollection(id: number): Promise<void> {
    await this.#client.deleteCollection(id);
    const deleted = this.collections.find((row) => row.id === id);
    const index = this.collections.findIndex((row) => row.id === id);
    if (index >= 0) {
      this.collections = [
        ...this.collections.slice(0, index),
        ...this.collections.slice(index + 1),
      ];
    }
    if (
      deleted &&
      this.filter.type === "collection" &&
      this.filter.name === deleted.name
    ) {
      this.setFilter({ type: "allSkills" });
    } else {
      // Unrelated delete: the visible member list stays correct, but refresh the
      // detail anyway so the sidebar count can't drift.
      this.#syncCollectionDetail(this.filter);
    }
    await this.refreshCollections();
  }

  /** Adds a skill to a collection (`POST …/collections/{id}/skills`). */
  async addToCollection(
    skillId: number,
    collection: CollectionSummary,
  ): Promise<boolean> {
    const response = await this.#client.addCollectionSkill(
      collection.id,
      skillId,
    );
    await this.#afterMembershipChange();
    return response.added ?? false;
  }

  /** Removes a skill from a collection (`DELETE …/collections/{id}/skills/{skillId}`). */
  async removeFromCollection(
    skillId: number,
    collection: CollectionSummary,
  ): Promise<boolean> {
    const response = await this.#client.removeCollectionSkill(
      collection.id,
      skillId,
    );
    await this.#afterMembershipChange();
    return response.removed ?? false;
  }

  /** Toggles membership from the metadata-bar picker, macOS tray-button parity. */
  async toggleCollectionMembership(
    skill: Skill,
    collection: CollectionSummary,
  ): Promise<boolean> {
    const assigned = skill.collections.some((ref) => ref.name === collection.name);
    return assigned
      ? this.removeFromCollection(skill.id, collection)
      : this.addToCollection(skill.id, collection);
  }

  async #afterMembershipChange(): Promise<void> {
    await Promise.allSettled([
      this.refresh(),
      this.refreshCollections(),
      this.#syncCollectionDetail(this.filter),
    ]);
  }

  // MARK: Registry (chopsd mirrors skills.sh; install may fire a rescan event too)

  /** `GET /api/registry/trending` read for the registry sheet. */
  fetchTrending(): Promise<RegistrySkill[]> {
    return this.#client.listTrending();
  }

  /** `GET /api/registry/search?q=…` read for the registry sheet. */
  searchRegistry(q: string): Promise<RegistrySkill[]> {
    return this.#client.searchRegistry(q);
  }


  /** Installs through chopsd and refreshes so the new skill row appears. */
  async installRegistrySkill(
    request: RegistryInstallRequest,
  ): Promise<RegistryInstallResponse> {
    const response = await this.#client.installRegistry(request);
    await Promise.allSettled([this.refresh(), this.refreshCollections()]);
    return response;
  }

  // MARK: Remote servers (SSH CRUD + browse/install; UI gated by the feature flag)

  listRemoteServers(): Promise<RemoteServer[]> {
    return this.#client.listRemoteServers();
  }

  createRemoteServer(request: RemoteServerRequest): Promise<RemoteServer> {
    return this.#client.createRemoteServer(request);
  }

  updateRemoteServer(
    id: string,
    request: RemoteServerRequest,
  ): Promise<RemoteServer> {
    return this.#client.updateRemoteServer(id, request);
  }

  deleteRemoteServer(id: string): Promise<{ deleted: boolean }> {
    return this.#client.deleteRemoteServer(id);
  }

  browseRemote(serverId: string): Promise<RemoteBrowseResponse> {
    return this.#client.browseRemote(serverId);
  }

  /** Installs a remote SKILL.md into the selected local tool roots, then rescans. */
  async installRemote(
    request: RemoteInstallRequest,
  ): Promise<RegistryInstallResponse> {
    const response = await this.#client.installRemote(request);
    await Promise.allSettled([this.refresh(), this.refreshCollections()]);
    return response;
  }

  // MARK: Settings (scan roots / plugin flag / theme through GET/PUT /api/settings)
  setUnsaved(unsaved: boolean): void {
    this.unsaved = unsaved;
  }

  /**
   * Generic settings persistence (scan roots, plugin flag, `sotDir`) through
   * `PUT /api/settings`; the response is the server-normalized settings row.
   * Optimistic applied fields stay until the response replaces them — matching
   * `setTheme` behavior — while failures surface as `settingsError`.
   */
  async saveSettings(patch: SettingsPatch): Promise<Settings> {
    this.settingsError = null;
    const requestId = ++this.#themeRequestId;
    try {
      const saved = await this.#client.updateSettings(patch);
      if (requestId !== this.#themeRequestId) return saved;
      this.settings = saved;
      this.theme = saved.theme;
      applyTheme(this.theme);
      return saved;
    } catch (error) {
      if (requestId !== this.#themeRequestId) return this.settings as Settings;
      this.settingsError = toMessage(error);
      throw error;
    }
  }

  /**
   * Optimistically applies the theme, then persists the mode through chopsd. If the
   * PUT fails the in-memory mode stays (the UI never silently reverts) and the
   * status bar surfaces `settingsError`.
   */
  async setTheme(theme: ThemeMode): Promise<void> {
    this.theme = theme;
    applyTheme(theme);
    this.settingsError = null;
    const requestId = ++this.#themeRequestId;
    try {
      const saved = await this.#client.updateSettings({ theme });
      if (requestId !== this.#themeRequestId) return;
      this.settings = saved;
      this.theme = saved.theme;
      applyTheme(saved.theme);
    } catch (error) {
      if (requestId !== this.#themeRequestId) return;
      this.settingsError = toMessage(error);
    }
  }

  stop(): void {
    this.#events?.close();
    this.#events = null;
    if (this.#refreshTimer !== null) {
      clearTimeout(this.#refreshTimer);
      this.#refreshTimer = null;
    }
    this.#unsubscribeTheme();
    this.#started = false;
    this.connection = "disconnected";
  }
}

/** Shared instance used by the route; tests construct `new ChopsApp(fakeClient)`. */
export const app = new ChopsApp();
