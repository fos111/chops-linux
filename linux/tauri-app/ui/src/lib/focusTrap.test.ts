import { afterEach, describe, expect, it } from "vitest";
import { focusTrap } from "./focusTrap";

function makeVisible(element: HTMLElement): void {
  Object.defineProperty(element, "offsetWidth", { configurable: true, value: 10 });
  Object.defineProperty(element, "offsetHeight", { configurable: true, value: 10 });
}

function pressTab(shiftKey = false): void {
  const event = new KeyboardEvent("keydown", {
    key: "Tab",
    shiftKey,
    bubbles: true,
    cancelable: true,
  });
  document.activeElement?.dispatchEvent(event);
}

afterEach(() => {
  document.body.innerHTML = "";
});

describe("focusTrap", () => {
  it("focuses the first control, cycles Tab, and restores focus on destroy", async () => {
    document.body.innerHTML = `
      <button id="opener">Open</button>
      <div id="dialog" tabindex="-1">
        <button id="first">First</button>
        <button id="last">Last</button>
      </div>
    `;
    const opener = document.querySelector<HTMLButtonElement>("#opener")!;
    const dialog = document.querySelector<HTMLElement>("#dialog")!;
    const first = document.querySelector<HTMLButtonElement>("#first")!;
    const last = document.querySelector<HTMLButtonElement>("#last")!;
    for (const element of [opener, first, last, dialog]) makeVisible(element);

    opener.focus();
    const action = focusTrap(dialog);
    await Promise.resolve();

    expect(document.activeElement).toBe(first);

    last.focus();
    pressTab();
    expect(document.activeElement).toBe(first);

    first.focus();
    pressTab(true);
    expect(document.activeElement).toBe(last);

    action.destroy();
    expect(document.activeElement).toBe(opener);
  });
});
