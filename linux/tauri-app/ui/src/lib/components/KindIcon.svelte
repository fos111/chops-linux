<script lang="ts">
  let {
    kind,
    size = 16,
  }: {
    kind: "skill" | "agent" | "rule" | "favorite" | "tool" | string;
    size?: number;
  } = $props();
</script>

<svg
  width={size}
  height={size}
  viewBox="0 0 16 16"
  fill="none"
  stroke="currentColor"
  stroke-width="1.5"
  stroke-linecap="round"
  stroke-linejoin="round"
  aria-hidden="true"
>
  {#if kind === "agent"}
    <circle cx="8" cy="5" r="3" />
    <path d="M2.5 14c0-3 2.5-4.5 5.5-4.5s5.5 1.5 5.5 4.5" />
  {:else if kind === "rule"}
    <path d="M5.5 4h8M5.5 8h8M5.5 12h8" />
    <circle cx="2.5" cy="4" r="0.75" fill="currentColor" stroke="none" />
    <circle cx="2.5" cy="8" r="0.75" fill="currentColor" stroke="none" />
    <circle cx="2.5" cy="12" r="0.75" fill="currentColor" stroke="none" />
  {:else if kind === "favorite"}
    <path d="M8 1.8l1.9 3.9 4.3.6-3.1 3 .7 4.3L8 11.6l-3.8 2 .7-4.3-3.1-3 4.3-.6z" />
  {:else if kind === "tool"}
    <path d="M6 2.5h4v3H6zM3 7h10v6.5H3z" />
    <path d="M6.5 10.5h3" />
  {:else}
    <rect x="3" y="1.5" width="10" height="13" rx="1.5" />
    <path d="M5.5 5h5M5.5 8h5M5.5 11h3" />
  {/if}
</svg>
