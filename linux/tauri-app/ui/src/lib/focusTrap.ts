// Keyboard containment for modal surfaces (plan T17).
//
// The action is attached to a dialog root that is only mounted while open. It
// keeps Tab/Shift+Tab inside the dialog and restores focus to the element that
// opened it when the dialog unmounts. Escape handling stays with each dialog
// because owners differ (palette closes, sheets cancel, etc.).

const FOCUSABLE_SELECTOR = [
  "a[href]",
  "button:not([disabled])",
  "input:not([disabled])",
  "select:not([disabled])",
  "textarea:not([disabled])",
  "[tabindex]:not([tabindex=\"-1\"])",
].join(",");

function focusableElements(root: HTMLElement): HTMLElement[] {
  return Array.from(root.querySelectorAll<HTMLElement>(FOCUSABLE_SELECTOR)).filter(
    (element) =>
      element.getAttribute("aria-hidden") !== "true" &&
      (element.offsetWidth > 0 || element.offsetHeight > 0 || element === document.activeElement),
  );
}

export function focusTrap(node: HTMLElement) {
  const previouslyFocused = document.activeElement as HTMLElement | null;

  function handleKeydown(event: KeyboardEvent): void {
    if (event.key !== "Tab") return;
    const focusable = focusableElements(node);
    if (focusable.length === 0) {
      event.preventDefault();
      node.focus();
      return;
    }

    const first = focusable[0];
    const last = focusable[focusable.length - 1];
    const active = document.activeElement as HTMLElement | null;
    const outside = active === null || !node.contains(active);

    if (event.shiftKey && (outside || active === first)) {
      event.preventDefault();
      last.focus();
    } else if (!event.shiftKey && (outside || active === last)) {
      event.preventDefault();
      first.focus();
    }
  }

  queueMicrotask(() => {
    if (!node.contains(document.activeElement)) {
      const [first] = focusableElements(node);
      (first ?? node).focus();
    }
  });

  document.addEventListener("keydown", handleKeydown, true);

  return {
    destroy() {
      document.removeEventListener("keydown", handleKeydown, true);
      if (previouslyFocused && typeof previouslyFocused.focus === "function") {
        previouslyFocused.focus();
      }
    },
  };
}
