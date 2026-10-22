// Compose agent metadata.
//
// The chopsd contract (`AssistRequest` in `Core/chopsd/DTO.swift`) carries only
// the frozen `AgentID` raw value — there is no `model` field. The model shown in
// the compose panel is therefore read-only display metadata that documents what
// each one-shot transport actually runs:
//   - Claude: `claude … --model sonnet` (pinned in ClaudeCLIAgent)
//   - Codex:  `codex exec …` with no `--model` flag, so the CLI default applies.

import type { AgentID } from "./api";

export interface AssistAgent {
  id: AgentID;
  label: string;
  /** Display-only; never sent to chopsd. */
  defaultModel: string;
}

export const ASSIST_AGENTS: AssistAgent[] = [
  { id: "claude", label: "Claude Code", defaultModel: "sonnet" },
  { id: "codex", label: "Codex", defaultModel: "CLI default" },
];

export function assistAgent(id: AgentID): AssistAgent {
  return ASSIST_AGENTS.find((agent) => agent.id === id) ?? ASSIST_AGENTS[0];
}
