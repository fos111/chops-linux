import { afterEach, describe, expect, it } from "vitest";
import {
  remoteServersEnabled,
  setRemoteServersEnabledForTests,
} from "./remoteFlag";

afterEach(() => {
  setRemoteServersEnabledForTests(null);
});

describe("remote server feature flag", () => {
  it("defaults off when VITE_ENABLE_REMOTE_SERVERS is unset", () => {
    setRemoteServersEnabledForTests(null);
    expect(remoteServersEnabled()).toBe(false);
  });

  it("honors the explicit test override in both directions", () => {
    setRemoteServersEnabledForTests(true);
    expect(remoteServersEnabled()).toBe(true);
    setRemoteServersEnabledForTests(false);
    expect(remoteServersEnabled()).toBe(false);
  });
});
