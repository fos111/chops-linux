<script lang="ts">
  import { untrack } from "svelte";
  import type {
    AssistAcceptResponse,
    AssistRejectResponse,
    AssistRequest,
    AssistResponse,
    CollectionSummary,
    Skill,
    Tool,
  } from "$lib/api";
  import { abbreviatePath, composeSkillMarkdown } from "$lib/editor";
  import { kindLabel, skillKind } from "$lib/filters";
  import { renderMarkdown } from "$lib/markdown";
  import ComposePanel from "./ComposePanel.svelte";
  import KindIcon from "./KindIcon.svelte";
  import SkillMetadataBar from "./SkillMetadataBar.svelte";

  let {
    skill,
    tools,
    homeDirectory = null,
    collections = null,
    onsave,
    onunsaved,
    onnew,
    ontoggleCollection,
    onassist,
    onacceptassist,
    onrejectassist,
  }: {
    skill: Skill | null;
    tools: Tool[];
    homeDirectory?: string | null;
    /** Enables the metadata-bar collection picker when provided. */
    collections?: CollectionSummary[] | null;
    onsave: (content: string) => Promise<unknown>;
    onunsaved?: (dirty: boolean) => void;
    onnew?: () => void;
    ontoggleCollection?: (collection: CollectionSummary) => void;
    /** Enables the compose panel when all three assist callbacks are provided. */
    onassist?: (request: AssistRequest) => Promise<AssistResponse>;
    onacceptassist?: (pendingId: string) => Promise<AssistAcceptResponse>;
    onrejectassist?: (pendingId: string) => Promise<AssistRejectResponse>;
  } = $props();

  type EditorMode = "edit" | "preview";

  let draft = $state("");
  let original = $state("");
  let loadedId = $state<number | null>(null);
  let mode = $state<EditorMode>("edit");
  let saving = $state(false);
  let error = $state<string | null>(null);
  let composeOpen = $state(false);

  const kind = $derived(skill ? skillKind(skill) : "skill");
  const dirty = $derived(skill !== null && draft !== original);
  const previewHtml = $derived(mode === "preview" ? renderMarkdown(draft) : "");
  const pathLabel = $derived(
    skill ? abbreviatePath(skill.remotePath ?? skill.filePath, homeDirectory) : "",
  );
  const composeAvailable = $derived(
    onassist !== undefined &&
      onacceptassist !== undefined &&
      onrejectassist !== undefined,
  );

  // Reload only when the selected row changes. Live WS refreshes replace the DTO but
  // keep the user's in-progress buffer for the same id.
  $effect(() => {
    const currentId = skill?.id ?? null;
    if (currentId === loadedId) return;
    loadedId = currentId;
    original = skill ? composeSkillMarkdown(skill) : "";
    draft = original;
    error = null;
    mode = "edit";
    composeOpen = false;
  });

  $effect(() => {
    const isDirty = dirty;
    untrack(() => onunsaved?.(isDirty));
  });

  $effect(() => () => {
    untrack(() => onunsaved?.(false));
  });

  async function save(): Promise<void> {
    if (!skill || !dirty || saving) return;
    const snapshot = draft;
    saving = true;
    error = null;
    try {
      await onsave(snapshot);
      if (loadedId === skill.id) {
        original = snapshot;
      }
    } catch (saveError) {
      error = saveError instanceof Error ? saveError.message : String(saveError);
    } finally {
      saving = false;
    }
  }

  function handleKeydown(event: KeyboardEvent): void {
    if (!(event.ctrlKey || event.metaKey) || event.key.toLowerCase() !== "s") return;
    event.preventDefault();
    void save();
  }

  async function sendAssist(request: AssistRequest): Promise<AssistResponse> {
    if (!onassist) throw new Error("Assist is unavailable");
    return onassist(request);
  }

  async function acceptAssist(pendingId: string): Promise<AssistAcceptResponse> {
    if (!onacceptassist) throw new Error("Assist is unavailable");
    return onacceptassist(pendingId);
  }

  async function rejectAssist(pendingId: string): Promise<AssistRejectResponse> {
    if (!onrejectassist) throw new Error("Assist is unavailable");
    return onrejectassist(pendingId);
  }

  /**
   * On accept chopsd has already written the file and re-scanned it. Prefer the
   * returned skill DTO (authoritative parsed frontmatter); fall back to the
   * reviewed full file when the path still belongs to the open editor and the
   * scan did not return the row.
   */
  function applyAccepted(
    response: AssistAcceptResponse,
    fullFile: string,
  ): void {
    if (!skill) return;
    if (response.skill && response.skill.id === skill.id) {
      const next = composeSkillMarkdown(response.skill);
      draft = next;
      original = next;
      error = null;
      mode = "edit";
      return;
    }
    const samePath =
      response.path === skill.filePath || response.path === skill.remotePath;
    if (samePath && fullFile) {
      draft = fullFile;
      original = fullFile;
      error = null;
      mode = "edit";
    }
  }
</script>

<svelte:window onkeydown={handleKeydown} />

<section class="detail-column" aria-label="Skill detail">
  {#if !skill}
    <div class="detail-empty">
      <KindIcon kind="skill" size={30} />
      <p class="empty-title">Select a Skill</p>
      <p class="empty-detail">Choose a skill from the sidebar to view and edit it.</p>
      {#if onnew}
        <button type="button" class="new-button" onclick={onnew}>New Skill…</button>
      {/if}
    </div>
  {:else}
    <header class="detail-header">
      <div class="detail-title-row">
        <KindIcon kind={kind} size={15} />
        <h2>{skill.name || "Untitled"}</h2>
        <span class="kind-badge">{kindLabel(kind)}</span>
        {#if skill.isFavorite}
          <span class="favorite" aria-label="Favorite">★</span>
        {/if}
        {#if dirty}
          <span class="dirty-chip" role="status" aria-live="polite">Unsaved changes</span>
        {/if}
      </div>
      <p class="detail-path" title={skill.filePath}>{pathLabel}</p>
    </header>

    <div class="editor-toolbar">
      <div class="mode-toggle" role="group" aria-label="Editor mode">
        <button
          type="button"
          class:active={mode === "edit"}
          aria-pressed={mode === "edit"}
          onclick={() => (mode = "edit")}>Edit</button
        >
        <button
          type="button"
          class:active={mode === "preview"}
          aria-pressed={mode === "preview"}
          onclick={() => (mode = "preview")}>Preview</button
        >
      </div>

      <span class="toolbar-spacer"></span>

      {#if error}
        <span class="save-error" role="alert" title={error}>Save failed</span>
      {/if}

      {#if composeAvailable}
        <button
          type="button"
          class="compose-button"
          aria-label="Compose with AI"
          aria-pressed={composeOpen}
          onclick={() => (composeOpen = !composeOpen)}
        >
          Compose
        </button>
      {/if}

      <button
        type="button"
        class="save-button"
        disabled={!dirty || saving}
        title="Save (Ctrl+S)"
        aria-label="Save skill"
        onclick={() => void save()}
      >
        {saving ? "Saving…" : "Save"}
        <kbd>Ctrl+S</kbd>
      </button>
    </div>

    {#if mode === "edit"}
      <textarea
        class="editor"
        aria-label="Skill markdown"
        spellcheck="false"
        bind:value={draft}
      ></textarea>
    {:else}
      <div class="preview markdown" aria-label="Markdown preview">
        {#if draft.trim()}
          {@html previewHtml}
        {:else}
          <p class="preview-empty">Nothing to preview yet.</p>
        {/if}
      </div>
    {/if}

    {#if composeOpen && composeAvailable}
      <ComposePanel
        skillId={skill.id}
        skillName={skill.name || "Untitled"}
        content={draft}
        onsend={sendAssist}
        onaccept={acceptAssist}
        onreject={rejectAssist}
        onaccepted={applyAccepted}
        onclose={() => (composeOpen = false)}
      />
    {/if}

    {#if error}
      <p class="save-error-detail" role="alert">{error}</p>
    {/if}

    <SkillMetadataBar {skill} {tools} {homeDirectory} {collections} {ontoggleCollection} />
  {/if}
</section>

<style>
  .detail-column {
    display: flex;
    flex-direction: column;
    min-width: 0;
    min-height: 0;
    height: 100%;
    background: var(--panel);
  }

  .detail-empty {
    display: flex;
    flex: 1;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 4px;
    padding: 32px;
    color: var(--muted);
    text-align: center;
  }

  .empty-title {
    margin: 8px 0 0;
    font-size: 15px;
    font-weight: 600;
    color: var(--text);
  }

  .empty-detail {
    margin: 0;
    font-size: 12.5px;
  }

  .new-button {
    margin-top: 12px;
    padding: 5px 12px;
    border: 1px solid var(--border-strong);
    border-radius: 6px;
    background: var(--panel-alt);
    color: var(--text);
    font-size: 12px;
  }

  .new-button:hover {
    background: var(--hover);
  }

  .detail-header {
    padding: 14px 20px 10px;
    border-bottom: 1px solid var(--border);
  }

  .detail-title-row {
    display: flex;
    align-items: center;
    gap: 8px;
  }

  h2 {
    min-width: 0;
    margin: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    font-size: 17px;
    font-weight: 650;
  }

  .kind-badge {
    flex: 0 0 auto;
    padding: 1px 6px;
    border-radius: 4px;
    background: var(--badge-bg);
    color: var(--badge-text);
    font-size: 10px;
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.03em;
  }

  .favorite {
    color: var(--star);
  }

  .dirty-chip {
    flex: 0 0 auto;
    padding: 1px 6px;
    border-radius: 3px;
    background: var(--warn-bg);
    color: var(--warn-text);
    font-size: 10px;
    font-weight: 600;
  }

  .detail-path {
    margin: 5px 0 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    font-family: var(--mono);
    font-size: 11px;
    color: var(--muted);
  }

  .editor-toolbar {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 6px 12px;
    border-bottom: 1px solid var(--border);
    background: var(--panel-alt);
  }

  .mode-toggle {
    display: inline-flex;
    gap: 1px;
    padding: 1px;
    border: 1px solid var(--border);
    border-radius: 5px;
  }

  .mode-toggle button {
    padding: 2px 9px;
    border: 0;
    border-radius: 4px;
    background: transparent;
    color: var(--muted);
    font-size: 11px;
  }

  .mode-toggle button:hover {
    background: var(--hover);
  }

  .mode-toggle button.active {
    background: var(--selected);
    color: var(--accent-strong);
  }

  .toolbar-spacer {
    flex: 1;
  }

  .save-button {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    padding: 3px 9px;
    border: 1px solid var(--border-strong);
    border-radius: 5px;
    background: var(--panel);
    color: var(--text);
    font-size: 11px;
  }

  .save-button:disabled {
    opacity: 0.5;
  }

  .save-button:not(:disabled):hover {
    background: var(--hover);
  }

  .compose-button {
    padding: 3px 9px;
    border: 1px solid var(--border-strong);
    border-radius: 5px;
    background: transparent;
    color: var(--text);
    font: inherit;
    font-size: 11px;
  }

  .compose-button:hover {
    background: var(--hover);
  }

  .compose-button[aria-pressed="true"] {
    background: var(--selected);
    color: var(--accent-strong);
  }

  kbd {
    color: var(--muted);
    font-family: var(--mono);
    font-size: 9.5px;
  }

  .save-error {
    color: var(--danger);
    font-size: 11px;
  }

  .editor {
    flex: 1;
    min-height: 0;
    width: 100%;
    resize: none;
    padding: 14px 18px 60vh;
    border: 0;
    outline: none;
    background: var(--panel);
    color: var(--text);
    font-family: var(--mono);
    font-size: 12.5px;
    line-height: 1.6;
    tab-size: 2;
    white-space: pre;
    overflow: auto;
  }

  .editor:focus-visible {
    box-shadow: inset 0 0 0 2px var(--focus-ring);
  }

  .preview {
    flex: 1;
    min-height: 0;
    overflow: auto;
    padding: 16px 20px 40px;
  }

  .preview-empty {
    margin: 0;
    color: var(--muted);
    font-size: 12.5px;
  }

  .save-error-detail {
    margin: 0;
    padding: 6px 12px;
    border-top: 1px solid var(--border);
    background: var(--error-bg);
    color: var(--error-text);
    font-size: 11px;
    overflow-wrap: anywhere;
  }

  /* Rendered Markdown (sanitized in $lib/markdown.ts). */
  .markdown :global(h1) {
    margin: 0 0 12px;
    font-size: 22px;
    line-height: 1.25;
  }

  .markdown :global(h2) {
    margin: 20px 0 8px;
    font-size: 17px;
  }

  .markdown :global(h3) {
    margin: 16px 0 6px;
    font-size: 14px;
  }

  .markdown :global(p),
  .markdown :global(li) {
    font-size: 13px;
    line-height: 1.6;
  }

  .markdown :global(ul),
  .markdown :global(ol) {
    padding-left: 22px;
  }

  .markdown :global(a) {
    color: var(--accent);
  }

  .markdown :global(hr) {
    border: 0;
    border-top: 1px solid var(--border);
  }

  .markdown :global(blockquote) {
    margin: 12px 0;
    padding: 2px 12px;
    border-left: 3px solid var(--border-strong);
    color: var(--muted);
  }

  .markdown :global(pre) {
    overflow: auto;
    padding: 10px 12px;
    border: 1px solid var(--border);
    border-radius: 6px;
    background: var(--panel-alt);
  }

  .markdown :global(code) {
    font-family: var(--mono);
    font-size: 12px;
  }

  .markdown :global(:not(pre) > code) {
    padding: 1px 4px;
    border-radius: 3px;
    background: var(--badge-bg);
  }

  .markdown :global(table) {
    border-collapse: collapse;
    font-size: 12.5px;
  }

  .markdown :global(th),
  .markdown :global(td) {
    padding: 4px 8px;
    border: 1px solid var(--border);
  }
</style>
