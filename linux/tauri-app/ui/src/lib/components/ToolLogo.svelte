<script lang="ts">
  // Tool logos copied by T13 from Chops/Resources/Assets.xcassets/tool-* into
  // `ui/public/tool-logos/`. Tools without a custom logo get the macOS
  // `ToolSource.shortLabel` fallback badge.
  const LOGO_TOOLS = new Set([
    "amp",
    "antigravity",
    "augment",
    "claude",
    "codex",
    "copilot",
    "cursor",
    "openclaw",
    "opencode",
    "windsurf",
  ]);

  const SHORT_LABELS: Record<string, string> = {
    augment: "AU",
    claude: "CC",
    cursor: "CU",
    windsurf: "WS",
    codex: "CX",
    copilot: "CP",
    aider: "AI",
    amp: "AM",
    hermes: "HE",
    openclaw: "OC",
    opencode: "OP",
    pi: "PI",
    agents: "AG",
    antigravity: "AV",
    claudeDesktop: "CD",
    custom: "?",
  };

  // Mirrors `ToolSource.color` (SwiftUI) for the fallback badge.
  const TOOL_COLORS: Record<string, string> = {
    augment: "#32ade6",
    claude: "#ff9500",
    cursor: "#007aff",
    windsurf: "#30b0c7",
    codex: "#34c759",
    copilot: "#af52de",
    aider: "#ffcc00",
    amp: "#ff2d55",
    hermes: "#a2845e",
    openclaw: "#5856d6",
    opencode: "#ff3b30",
    pi: "#32ade6",
    agents: "#00c7be",
    antigravity: "#ff3b30",
    claudeDesktop: "#ff9500",
    custom: "#8e8e93",
  };

  let {
    toolId,
    displayName = toolId,
    size = 16,
  }: { toolId: string; displayName?: string; size?: number } = $props();

  const hasLogo = $derived(LOGO_TOOLS.has(toolId));
  const shortLabel = $derived(
    SHORT_LABELS[toolId] ?? displayName.slice(0, 2).toUpperCase(),
  );
  const color = $derived(TOOL_COLORS[toolId] ?? TOOL_COLORS.custom);
</script>

{#if hasLogo}
  <img
    class="tool-logo"
    src={`/tool-logos/tool-${toolId}.svg`}
    alt={displayName}
    title={displayName}
    width={size}
    height={size}
  />
{:else}
  <span
    class="tool-logo tool-logo-fallback"
    style:--tool-color={color}
    style:width={`${size}px`}
    style:height={`${size}px`}
    style:font-size={`${Math.max(7, size * 0.42)}px`}
    role="img"
    aria-label={displayName}
    title={displayName}>{shortLabel}</span
  >
{/if}

<style>
  .tool-logo {
    display: inline-block;
    flex: 0 0 auto;
    object-fit: contain;
    vertical-align: middle;
  }

  /* The copied assets are mostly `currentColor`/black glyphs. In dark mode invert
     them (with a hue rotation so any colored logo keeps its approximate hue). */
  :global(:root[data-theme="dark"]) img.tool-logo {
    filter: invert(1) hue-rotate(180deg);
  }

  @media (prefers-color-scheme: dark) {
    :global(:root:not([data-theme="light"])) img.tool-logo {
      filter: invert(1) hue-rotate(180deg);
    }
  }

  .tool-logo-fallback {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    border-radius: 4px;
    color: #fff;
    font-weight: 700;
    letter-spacing: 0.02em;
    line-height: 1;
    background: var(--tool-color);
  }
</style>
