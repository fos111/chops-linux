<script lang="ts">
  import type {
    AgentID,
    AssistAcceptResponse,
    AssistRejectResponse,
    AssistRequest,
    AssistResponse,
  } from "$lib/api";
  import { ASSIST_AGENTS, assistAgent } from "$lib/assist";
  import DiffReview from "./DiffReview.svelte";

  // Compose panel: one explicit user click sends `POST /api/assist`. Nothing here
  // runs on open, on agent switch, or on a timer — the QA suites assert that.
  let {
    skillId,
    skillName,
    content,
    onsend,
    onaccept,
    onreject,
    onaccepted,
    onclose,
  }: {
    skillId: number;
    skillName: string;
    /** Current editor buffer, captured at send time for the diff base. */
    content: string;
    onsend: (request: AssistRequest) => Promise<AssistResponse>;
    onaccept: (pendingId: string) => Promise<AssistAcceptResponse>;
    onreject: (pendingId: string) => Promise<AssistRejectResponse>;
    /** Lets the detail editor apply the accepted file back into its buffer. */
    onaccepted?: (response: AssistAcceptResponse, fullFile: string) => void;
    onclose: () => void;
  } = $props();

  type ReviewOutcome = "pending" | "accepted" | "rejected" | null;

  let agent = $state<AgentID>("claude");
  let prompt = $state("");
  let sending = $state(false);
  let sendError = $state<string | null>(null);
  let result = $state<AssistResponse | null>(null);
  let baseContent = $state("");
  let outcome = $state<ReviewOutcome>(null);
  let applying = $state(false);
  let actionError = $state<string | null>(null);

  const selectedAgent = $derived(assistAgent(agent));
  const hasProposal = $derived(
    result !== null && result.pendingId !== null && result.fullFile !== null,
  );
  const reviewOpen = $derived(hasProposal && outcome === "pending");
  const proseOnly = $derived(result !== null && !hasProposal);
  const canSend = $derived(
    prompt.trim().length > 0 && !sending && !reviewOpen,
  );

  function messageOf(error: unknown): string {
    return error instanceof Error ? error.message : String(error);
  }

  async function send(): Promise<void> {
    const text = prompt.trim();
    if (!text || sending || reviewOpen) return;
    sending = true;
    sendError = null;
    result = null;
    outcome = null;
    actionError = null;
    baseContent = content;
    try {
      const response = await onsend({
        skillId,
        prompt: text,
        agent,
        content: baseContent,
      });
      result = response;
      outcome =
        response.pendingId !== null && response.fullFile !== null
          ? "pending"
          : null;
      prompt = "";
    } catch (error) {
      sendError = messageOf(error);
    } finally {
      sending = false;
    }
  }

  async function accept(): Promise<void> {
    if (!result?.pendingId || applying) return;
    applying = true;
    actionError = null;
    try {
      const accepted = await onaccept(result.pendingId);
      outcome = "accepted";
      onaccepted?.(accepted, result.fullFile ?? "");
    } catch (error) {
      actionError = messageOf(error);
    } finally {
      applying = false;
    }
  }

  async function reject(): Promise<void> {
    if (!result?.pendingId || applying) return;
    applying = true;
    actionError = null;
    try {
      await onreject(result.pendingId);
      outcome = "rejected";
    } catch (error) {
      actionError = messageOf(error);
    } finally {
      applying = false;
    }
  }
</script>

<section class="compose-panel" aria-label="Compose panel">
  <header class="compose-header">
    <h3>Compose with AI</h3>
    <span class="compose-skill" title={skillName}>{skillName}</span>
    <span class="spacer"></span>
    <button type="button" class="close-button" onclick={onclose}>Close</button>
  </header>

  <div class="compose-controls">
    <label class="agent-field">
      <span>Agent</span>
      <select aria-label="Agent" bind:value={agent}>
        {#each ASSIST_AGENTS as option (option.id)}
          <option value={option.id}>{option.label}</option>
        {/each}
      </select>
    </label>
    <p class="model-line">
      Model: <span class="model-value" aria-label="Default model"
        >{selectedAgent.defaultModel}</span
      >
      <span class="model-hint">read-only · chosen by the CLI</span>
    </p>
  </div>

  <textarea
    class="prompt"
    aria-label="Compose prompt"
    placeholder="Describe what you'd like to change…"
    spellcheck="false"
    bind:value={prompt}
  ></textarea>

  <div class="compose-actions">
    <span class="privacy-hint">Runs locally through chopsd only when you press Send.</span>
    <span class="spacer"></span>
    <button
      type="button"
      class="send-button"
      disabled={!canSend}
      onclick={() => void send()}
    >
      {sending ? "Sending…" : "Send"}
    </button>
  </div>

  {#if sending}
    <p class="compose-status" role="status">
      Waiting for {selectedAgent.label}…
    </p>
  {/if}

  {#if sendError}
    <p class="compose-error" role="alert">{sendError}</p>
  {/if}

  {#if actionError}
    <p class="compose-error" role="alert">{actionError}</p>
  {/if}

  {#if reviewOpen && result?.fullFile}
    <DiffReview
      summary={result.summary}
      original={baseContent}
      proposed={result.fullFile}
      path={result.path}
      {applying}
      onaccept={() => void accept()}
      onreject={() => void reject()}
    />
  {:else if outcome === "accepted"}
    <p class="compose-outcome accepted" role="status">
      Changes accepted{result?.path ? ` · ${result.path}` : ""}.
    </p>
  {:else if outcome === "rejected"}
    <p class="compose-outcome rejected" role="status">Changes rejected.</p>
  {:else if proseOnly}
    <div class="assistant-prose" aria-label="Agent response">
      <p>{result?.summary?.trim() || "The agent replied without a file proposal."}</p>
      <p class="prose-hint">No file changes to review.</p>
    </div>
  {/if}
</section>

<style>
  .compose-panel {
    display: flex;
    flex: 0 1 auto;
    flex-direction: column;
    gap: 8px;
    max-height: 46%;
    overflow: auto;
    padding: 10px 12px 12px;
    border-top: 1px solid var(--border);
    background: var(--panel-alt);
  }

  .compose-header {
    display: flex;
    align-items: center;
    gap: 8px;
  }

  .compose-header h3 {
    margin: 0;
    font-size: 12px;
    text-transform: uppercase;
    letter-spacing: 0.04em;
    color: var(--muted);
  }

  .compose-skill {
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    font-family: var(--mono);
    font-size: 11px;
    color: var(--muted);
  }

  .spacer {
    flex: 1;
  }

  .close-button {
    padding: 2px 8px;
    border: 1px solid var(--border);
    border-radius: 5px;
    background: transparent;
    color: var(--text);
    font: inherit;
    font-size: 11px;
  }

  .compose-controls {
    display: flex;
    align-items: center;
    gap: 12px;
  }

  .agent-field {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    font-size: 11.5px;
  }

  .agent-field select {
    padding: 3px 6px;
    border: 1px solid var(--border);
    border-radius: 5px;
    background: var(--bg);
    color: var(--text);
    font: inherit;
    font-size: 12px;
  }

  .model-line {
    margin: 0;
    font-size: 11px;
    color: var(--muted);
  }

  .model-value {
    font-family: var(--mono);
    color: var(--text);
  }

  .model-hint {
    margin-left: 2px;
  }

  .prompt {
    min-height: 64px;
    resize: vertical;
    padding: 7px 9px;
    border: 1px solid var(--border);
    border-radius: 6px;
    background: var(--bg);
    color: var(--text);
    font-family: var(--mono);
    font-size: 12px;
    line-height: 1.5;
  }

  .prompt:focus-visible {
    outline: 2px solid var(--accent);
    outline-offset: -1px;
  }

  .compose-actions {
    display: flex;
    align-items: center;
    gap: 8px;
  }

  .privacy-hint {
    font-size: 10.5px;
    color: var(--muted);
  }

  .send-button {
    padding: 4px 14px;
    border: 1px solid var(--border-strong);
    border-radius: 6px;
    background: var(--selected);
    color: var(--accent-strong);
    font: inherit;
    font-size: 12px;
  }

  .send-button:disabled {
    opacity: 0.5;
  }

  .compose-status {
    margin: 0;
    font-size: 11.5px;
    color: var(--muted);
  }

  .compose-error {
    margin: 0;
    color: var(--danger, #d33);
    font-size: 11.5px;
    overflow-wrap: anywhere;
  }

  .compose-outcome {
    margin: 0;
    font-size: 11.5px;
  }

  .compose-outcome.accepted {
    color: var(--ok, #2e8b57);
  }

  .compose-outcome.rejected {
    color: var(--muted);
  }

  .assistant-prose {
    padding: 8px 10px;
    border: 1px solid var(--border);
    border-radius: 6px;
    background: var(--panel);
  }

  .assistant-prose p {
    margin: 0;
    font-size: 12px;
    white-space: pre-wrap;
  }

  .assistant-prose .prose-hint {
    margin-top: 6px;
    color: var(--muted);
    font-size: 10.5px;
  }
</style>
