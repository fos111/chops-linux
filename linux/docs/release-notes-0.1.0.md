# Chops for Linux 0.1.0

First Linux desktop build of Chops, packaged as a Debian `.deb`.

## Highlights

- Native Tauri + Svelte desktop shell for Debian 13 (trixie) and compatible distributions.
- Swift `chopsd` sidecar with GRDB storage, filesystem watcher, and REST/WebSocket API.
- Scan and edit Claude, Codex, Cursor, OpenCode, Amp, and other installed tool libraries.
- Collections, registry browse/install, AI compose with diff review, settings, and remote
  skill servers over SSH.
- Local-only runtime: `chopsd` binds `127.0.0.1:47115`; skills stay on disk.

## Install

```sh
sudo dpkg -i Chops_0.1.0_amd64.deb
sudo apt-get install -f
```

Launch **Chops** from the application menu or run `chops-linux`.

## Requirements

- Debian 13 / Ubuntu 24.04 or newer with WebKitGTK 4.1 and GTK 3.
- Claude and/or Codex CLI installed for AI compose (optional).

## Notes

- Package is unsigned; install only from the official fork release.
- The Linux build is additive and does not modify the macOS app sources.
