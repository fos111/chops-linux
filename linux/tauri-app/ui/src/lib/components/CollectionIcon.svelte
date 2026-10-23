<script lang="ts">
  // Collection icons carry the frozen macOS SF Symbol names (chopsd stores
  // `SkinCollection.icon` strings like "folder"); Linux renders them with inline
  // SVGs instead of SF Symbols. Unknown names fall back to the folder glyph.
  let {
    icon,
    size = 14,
  }: {
    icon: string;
    size?: number;
  } = $props();

  const px = $derived(size);
</script>

<svg
  width={px}
  height={px}
  viewBox="0 0 16 16"
  fill="none"
  stroke="currentColor"
  stroke-width="1.4"
  stroke-linecap="round"
  stroke-linejoin="round"
  aria-hidden="true"
  class="collection-icon"
>
  {#if icon === "star"}
    <path d="M8 1.8l1.9 3.9 4.3.6-3.1 3 .7 4.3L8 11.6l-3.8 2 .7-4.3-3.1-3 4.3-.6z" />
  {:else if icon === "bookmark"}
    <path d="M4.5 1.5h7V14L8 11l-3.5 3z" />
  {:else if icon === "tag"}
    <path d="M2 7V2h5l7 7-5 5z" />
    <circle cx="5" cy="5" r="0.9" fill="currentColor" stroke="none" />
  {:else if icon === "tray"}
    <path d="M2 6h4l1 2h2l1-2h4" />
    <path d="M2 6l1.2 7h9.6L14 6l-1-3H3z" />
  {:else if icon === "archivebox"}
    <rect x="2" y="3" width="12" height="3" rx="0.8" />
    <path d="M3 6v7h10V6M6.5 9h3" />
  {:else if icon === "doc.text"}
    <rect x="3" y="1.5" width="10" height="13" rx="1.5" />
    <path d="M5.5 5h5M5.5 8h5M5.5 11h3" />
  {:else if icon === "gearshape"}
    <circle cx="8" cy="8" r="2.2" />
    <path d="M8 1.8v1.8M8 12.4v1.8M1.8 8h1.8M12.4 8h1.8M3.6 3.6l1.3 1.3M11.1 11.1l1.3 1.3M12.4 3.6l-1.3 1.3M4.9 11.1l-1.3 1.3" />
  {:else if icon === "wrench"}
    <path d="M11.5 3.5L13 2l1 1-1.5 1.5-.5 2-7.2 7.2a1.4 1.4 0 01-2-2L11 4.5z" />
  {:else if icon === "hammer"}
    <path d="M4.5 2.5L7.5 2 9 3.5l-1 1L13 9.5a1.2 1.2 0 01-1.7 1.7L6.2 6.1l-1 1L3.7 5.6C3 4.9 3.4 3 4.5 2.5z" />
    <path d="M9.5 12.5L12 15" />
  {:else if icon === "paintbrush"}
    <path d="M9 2l5 5-4.2 1.2L7 5.4z" />
    <path d="M7 5.4L3.5 9.2A2 2 0 005 12.6c1.6.3 3-.6 3.3-2.2z" />
  {:else if icon === "wand.and.stars"}
    <path d="M2.5 13.5L11 5M9.5 2.5l.7 1.3 1.3.7-1.3.7-.7 1.3-.7-1.3-1.3-.7 1.3-.7z" />
    <path d="M13.3 5.5l.4.8.8.4-.8.4-.4.8-.4-.8-.8-.4.8-.4z" />
  {:else if icon === "terminal"}
    <rect x="1.5" y="2.5" width="13" height="11" rx="1.5" />
    <path d="M4 6l2.5 2L4 10M8.5 10.5h3.5" />
  {:else if icon === "network"}
    <circle cx="8" cy="3" r="1.8" />
    <circle cx="3" cy="12" r="1.8" />
    <circle cx="13" cy="12" r="1.8" />
    <path d="M8 5v3M8 8l-4 2.4M8 8l4 2.4M3 12h-1.4M13 12h1.4" />
  {:else if icon === "globe"}
    <circle cx="8" cy="8" r="6" />
    <path d="M2 8h12M8 2c-3 2.5-3 9.5 0 12M8 2c3 2.5 3 9.5 0 12" />
  {:else if icon === "bolt"}
    <path d="M9 1.5L3.5 9H7l-1 5.5L11.5 7H8z" />
  {:else if icon === "flame"}
    <path d="M8 1.5c1 2-1.5 3-1.5 5A3.5 3.5 0 008 1.5zM5 6.5C3.8 8 3.5 10 5 11.5a4.3 4.3 0 006-.1C12.2 10 12 8 11 6.5" />
    <path d="M5 11.5A4 4 0 0011 11" />
  {:else if icon === "leaf"}
    <path d="M2.5 13.5C2.5 6 7 2.5 13.5 2.5 13.5 9 10 13.5 2.5 13.5z" />
    <path d="M2.5 13.5C6 10 8 8 12 4.5" />
  {:else}
    <path d="M1.5 5.5h5l1 1.5h7v6.5a1 1 0 01-1 1h-11a1 1 0 01-1-1z" />
    <path d="M1.5 5.5v-3h4l1 1.5" />
  {/if}
</svg>

<style>
  .collection-icon {
    flex: 0 0 auto;
    color: var(--muted);
  }
</style>
