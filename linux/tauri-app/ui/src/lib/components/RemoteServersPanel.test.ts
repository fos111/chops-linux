import { afterEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen } from "@testing-library/svelte";
import RemoteServersPanel from "./RemoteServersPanel.svelte";
import type {
  RemoteBrowseResponse,
  RemoteInstallRequest,
  RemoteServer,
  RemoteServerRequest,
} from "$lib/api";

function makeServer(overrides: Partial<RemoteServer> = {}): RemoteServer {
  return {
    id: overrides.id ?? "srv-1",
    label: overrides.label ?? "Production",
    host: overrides.host ?? "192.168.1.100",
    port: overrides.port ?? 22,
    username: overrides.username ?? "root",
    skillsBasePath: overrides.skillsBasePath ?? "~/.hermes/skills",
    sshKeyPath: overrides.sshKeyPath ?? null,
    lastSyncDate: overrides.lastSyncDate ?? null,
    lastSyncError: overrides.lastSyncError ?? null,
  };
}

function makeBrowse(overrides: Partial<RemoteBrowseResponse> = {}): RemoteBrowseResponse {
  return {
    serverId: overrides.serverId ?? "srv-1",
    skills: overrides.skills ?? [
      {
        path: "skills/r-one/SKILL.md",
        name: "r-one",
        description: "remote fixture one",
        content: "# R One",
      },
    ],
    lastSyncDate: overrides.lastSyncDate ?? "2026-10-22T12:00:00Z",
  };
}

interface Harness {
  fetchServers: ReturnType<typeof vi.fn>;
  createServer: ReturnType<typeof vi.fn>;
  updateServer: ReturnType<typeof vi.fn>;
  deleteServer: ReturnType<typeof vi.fn>;
  browseRemote: ReturnType<typeof vi.fn>;
  installRemote: ReturnType<typeof vi.fn>;
}

function renderPanel(enabled: boolean, overrides: Partial<Harness> = {}) {
  const harness: Harness = {
    fetchServers:
      overrides.fetchServers ?? vi.fn(async () => [makeServer()]),
    createServer:
      overrides.createServer ??
      vi.fn(async (request: RemoteServerRequest) =>
        makeServer({
          id: "srv-2",
          label: request.label,
          host: request.host,
          port: request.port ?? 22,
          username: request.username,
          skillsBasePath: request.skillsBasePath,
          sshKeyPath: request.sshKeyPath ?? null,
        }),
      ),
    updateServer:
      overrides.updateServer ??
      vi.fn(async (id: string, request: RemoteServerRequest) =>
        makeServer({
          id,
          label: request.label,
          host: request.host,
          port: request.port ?? 22,
          username: request.username,
          skillsBasePath: request.skillsBasePath,
          sshKeyPath: request.sshKeyPath ?? null,
        }),
      ),
    deleteServer:
      overrides.deleteServer ?? vi.fn(async () => ({ deleted: true })),
    browseRemote:
      overrides.browseRemote ?? vi.fn(async () => makeBrowse()),
    installRemote:
      overrides.installRemote ??
      vi.fn(async (request: RemoteInstallRequest) => ({
        installed: true,
        skillName: "r-one",
        path: "/home/test/.agents/skills/r-one/SKILL.md",
        targets: ["claude"],
        skill: null,
      })),
  };
  render(RemoteServersPanel, {
    props: {
      enabled,
      fetchServers: harness.fetchServers as () => Promise<RemoteServer[]>,
      createServer: harness.createServer as (
        request: RemoteServerRequest,
      ) => Promise<RemoteServer>,
      updateServer: harness.updateServer as (
        id: string,
        request: RemoteServerRequest,
      ) => Promise<RemoteServer>,
      deleteServer: harness.deleteServer as (
        id: string,
      ) => Promise<{ deleted: boolean }>,
      browseRemote: harness.browseRemote as (
        serverId: string,
      ) => Promise<RemoteBrowseResponse>,
      installRemote: harness.installRemote as (
        request: RemoteInstallRequest,
      ) => Promise<{
        installed: boolean;
        skillName: string;
        path: string;
        targets: string[];
        skill: null;
      }>,
    },
  });
  return harness;
}

async function fillAddForm(): Promise<void> {
  await fireEvent.click(screen.getByRole("button", { name: "Add remote server" }));
  await fireEvent.input(screen.getByLabelText("Label"), {
    target: { value: "Staging" },
  });
  await fireEvent.input(screen.getByLabelText("Host"), {
    target: { value: "10.0.0.5" },
  });
  await fireEvent.input(screen.getByLabelText("Port"), {
    target: { value: "2222" },
  });
  await fireEvent.input(screen.getByLabelText("Username"), {
    target: { value: "deploy" },
  });
  await fireEvent.input(screen.getByLabelText("Skills base path"), {
    target: { value: "~/.hermes/skills" },
  });
  await fireEvent.input(screen.getByLabelText("SSH key path"), {
    target: { value: "~/.ssh/id_ed25519" },
  });
}

afterEach(cleanup);

describe("RemoteServersPanel (T16 part B)", () => {
  it("renders the flag-off empty state and issues no calls", async () => {
    const harness = renderPanel(false);
    await screen.findByText(/Remote servers are disabled/);
    expect(harness.fetchServers).not.toHaveBeenCalled();
    expect(screen.queryByRole("button", { name: "Add remote server" })).toBeNull();
  });

  it("loads and lists servers when the flag is on", async () => {
    const harness = renderPanel(true);
    await screen.findByText("Production");
    expect(harness.fetchServers).toHaveBeenCalledTimes(1);
    expect(screen.getByText("root@192.168.1.100:22")).toBeTruthy();
    expect(screen.getByText("Path: ~/.hermes/skills")).toBeTruthy();
  });

  it("surfaces list failures", async () => {
    renderPanel(true, {
      fetchServers: vi.fn(async () => {
        throw new Error("list 500");
      }),
    });
    await screen.findByText("list 500");
  });

  it("adds a server through POST /api/remote/servers fields", async () => {
    const harness = renderPanel(true);
    await screen.findByText("Production");
    await fillAddForm();
    await fireEvent.click(screen.getByRole("button", { name: "Add Server" }));

    await vi.waitFor(() =>
      expect(harness.createServer).toHaveBeenCalledWith({
        label: "Staging",
        host: "10.0.0.5",
        port: 2222,
        username: "deploy",
        skillsBasePath: "~/.hermes/skills",
        sshKeyPath: "~/.ssh/id_ed25519",
      }),
    );
    await screen.findByText("Staging");
    await screen.findByText("Added Staging.");
  });

  it("edits a server through PUT /api/remote/servers/{id}", async () => {
    const harness = renderPanel(true);
    await screen.findByText("Production");
    await fireEvent.click(
      screen.getByRole("button", { name: "Edit Production" }),
    );

    await fireEvent.input(screen.getByLabelText("Host"), {
      target: { value: "10.0.0.9" },
    });
    await fireEvent.click(screen.getByRole("button", { name: "Save Server" }));

    await vi.waitFor(() =>
      expect(harness.updateServer).toHaveBeenCalledWith("srv-1", {
        label: "Production",
        host: "10.0.0.9",
        port: 22,
        username: "root",
        skillsBasePath: "~/.hermes/skills",
        sshKeyPath: null,
      }),
    );
    await screen.findByText("root@10.0.0.9:22");
    await screen.findByText("Saved Production.");
  });

  it("deletes a server through DELETE /api/remote/servers/{id}", async () => {
    const harness = renderPanel(true);
    await screen.findByText("Production");
    await fireEvent.click(
      screen.getByRole("button", { name: "Delete Production" }),
    );

    await vi.waitFor(() =>
      expect(harness.deleteServer).toHaveBeenCalledWith("srv-1"),
    );
    await screen.findByText("Deleted Production.");
    expect(screen.queryByText("Production")).toBeNull();
  });

  it("browses remote skills and installs one through the SSH bridge", async () => {
    const harness = renderPanel(true);
    await screen.findByText("Production");
    await fireEvent.click(
      screen.getByRole("button", { name: "Browse Production" }),
    );

    await vi.waitFor(() =>
      expect(harness.browseRemote).toHaveBeenCalledWith("srv-1"),
    );
    await screen.findByText("r-one");
    expect(screen.getByText("skills/r-one/SKILL.md")).toBeTruthy();
    await screen.findByText("Found 1 remote skill on Production.");

    await fireEvent.click(screen.getByRole("button", { name: "Install r-one" }));
    await vi.waitFor(() =>
      expect(harness.installRemote).toHaveBeenCalledWith({
        serverId: "srv-1",
        remotePath: "skills/r-one/SKILL.md",
      }),
    );
    await screen.findByText("Installed r-one.");
  });

  it("surfaces browse and install failures", async () => {
    renderPanel(true, {
      browseRemote: vi.fn(async () => {
        throw new Error("SSH browse failed");
      }),
    });
    await screen.findByText("Production");
    await fireEvent.click(
      screen.getByRole("button", { name: "Browse Production" }),
    );
    await screen.findByText("SSH browse failed");
  });

  it("does not add a server with an invalid port", async () => {
    const harness = renderPanel(true);
    await screen.findByText("Production");
    await fillAddForm();
    await fireEvent.input(screen.getByLabelText("Port"), {
      target: { value: "70000" },
    });
    const add = screen.getByRole("button", { name: "Add Server" });
    expect((add as HTMLButtonElement).disabled).toBe(true);
    expect(harness.createServer).not.toHaveBeenCalled();
  });
});
