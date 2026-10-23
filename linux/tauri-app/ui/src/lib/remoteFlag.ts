// VITE_ENABLE_REMOTE_SERVERS gate for the live remote-server UI.
//
// Default off: the Chops Linux QA harness runs without a reachable SSH target,
// so the Servers pane must render its disabled empty state and issue no calls.
// Tests (and a real desktop build) enable it with the env var or the explicit
// test override below.

const TRUTHY = new Set(["1", "true", "yes", "on"]);

let override: boolean | null = null;

/** Test-only override; pass null to fall back to the Vite env var. */
export function setRemoteServersEnabledForTests(value: boolean | null): void {
  override = value;
}

/** True when `VITE_ENABLE_REMOTE_SERVERS` is set to a truthy value (default off). */
export function remoteServersEnabled(): boolean {
  if (override !== null) return override;
  const raw = import.meta.env?.VITE_ENABLE_REMOTE_SERVERS;
  return typeof raw === "string" && TRUTHY.has(raw.trim().toLowerCase());
}
