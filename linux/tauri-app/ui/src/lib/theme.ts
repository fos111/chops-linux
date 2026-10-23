// Theme resolution and application. The mode (`system`/`light`/`dark`) is product
// state owned by chopsd's `settings.json`; this module only maps it onto the DOM.
// No localStorage is involved.

import type { ThemeMode } from "./api";

export function resolveTheme(mode: ThemeMode, systemPrefersDark: boolean): "light" | "dark" {
  if (mode === "system") return systemPrefersDark ? "dark" : "light";
  return mode;
}

/** Segmented toggle order: System -> Light -> Dark -> System. */
export function nextTheme(mode: ThemeMode): ThemeMode {
  switch (mode) {
    case "system":
      return "light";
    case "light":
      return "dark";
    default:
      return "system";
  }
}

/**
 * Explicit choices set `data-theme`; `system` removes it so the
 * `prefers-color-scheme` media query in `app.css` takes over.
 */
export function applyTheme(mode: ThemeMode, doc: Document | null = globalThis.document ?? null): void {
  if (!doc) return;
  const root = doc.documentElement;
  if (mode === "system") {
    root.removeAttribute("data-theme");
  } else {
    root.setAttribute("data-theme", mode);
  }
}

export interface MediaQueryLike {
  matches: boolean;
  addEventListener?: (type: "change", listener: (event: { matches: boolean }) => void) => void;
  removeEventListener?: (type: "change", listener: (event: { matches: boolean }) => void) => void;
  addListener?: (listener: (event: { matches: boolean }) => void) => void;
  removeListener?: (listener: (event: { matches: boolean }) => void) => void;
}

export function systemPrefersDark(
  win: { matchMedia?: (query: string) => MediaQueryLike } | null = globalThis.window ?? null,
): boolean {
  if (!win?.matchMedia) return false;
  return win.matchMedia("(prefers-color-scheme: dark)").matches;
}

/** Subscribe to OS appearance changes. Returns a no-op cleanup when unavailable. */
export function watchSystemTheme(
  listener: (prefersDark: boolean) => void,
  win: { matchMedia?: (query: string) => MediaQueryLike } | null = globalThis.window ?? null,
): () => void {
  if (!win?.matchMedia) return () => {};
  const media = win.matchMedia("(prefers-color-scheme: dark)");
  const handleChange = (event: { matches: boolean }) => listener(event.matches);

  if (media.addEventListener) {
    media.addEventListener("change", handleChange);
    return () => media.removeEventListener?.("change", handleChange);
  }
  if (media.addListener) {
    media.addListener(handleChange);
    return () => media.removeListener?.(handleChange);
  }
  return () => {};
}
