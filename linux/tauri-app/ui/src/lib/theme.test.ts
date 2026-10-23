import { describe, expect, it } from "vitest";
import {
  applyTheme,
  nextTheme,
  resolveTheme,
  systemPrefersDark,
  watchSystemTheme,
  type MediaQueryLike,
} from "./theme";

describe("resolveTheme", () => {
  it("follows the OS in system mode", () => {
    expect(resolveTheme("system", true)).toBe("dark");
    expect(resolveTheme("system", false)).toBe("light");
  });

  it("honors an explicit mode", () => {
    expect(resolveTheme("light", true)).toBe("light");
    expect(resolveTheme("dark", false)).toBe("dark");
  });
});

describe("nextTheme", () => {
  it("cycles system -> light -> dark -> system", () => {
    expect(nextTheme("system")).toBe("light");
    expect(nextTheme("light")).toBe("dark");
    expect(nextTheme("dark")).toBe("system");
  });
});

describe("applyTheme", () => {
  it("sets an explicit attribute for light/dark", () => {
    applyTheme("dark", document);
    expect(document.documentElement.getAttribute("data-theme")).toBe("dark");
    applyTheme("light", document);
    expect(document.documentElement.getAttribute("data-theme")).toBe("light");
  });

  it("removes the attribute in system mode so the media query applies", () => {
    applyTheme("dark", document);
    applyTheme("system", document);
    expect(document.documentElement.hasAttribute("data-theme")).toBe(false);
  });

  it("is a no-op without a document", () => {
    expect(() => applyTheme("dark", null)).not.toThrow();
  });
});

describe("system appearance", () => {
  it("reads the media query", () => {
    const win = {
      matchMedia: (query: string): MediaQueryLike => ({
        matches: query.includes("dark"),
      }),
    };
    expect(systemPrefersDark(win)).toBe(true);
    expect(systemPrefersDark(null)).toBe(false);
  });

  it("subscribes and unsubscribes with addEventListener", () => {
    const listeners: Array<(event: { matches: boolean }) => void> = [];
    const media: MediaQueryLike = {
      matches: false,
      addEventListener: (_type, listener) => listeners.push(listener),
      removeEventListener: (_type, listener) => {
        const index = listeners.indexOf(listener);
        if (index >= 0) listeners.splice(index, 1);
      },
    };
    const seen: boolean[] = [];
    const stop = watchSystemTheme((dark) => seen.push(dark), {
      matchMedia: () => media,
    });
    expect(listeners).toHaveLength(1);
    listeners[0]({ matches: true });
    expect(seen).toEqual([true]);
    stop();
    expect(listeners).toHaveLength(0);
  });
});
