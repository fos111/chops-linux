# Chops on Linux

Chops for Linux is an additive port of the macOS app:

- `Core/ChopsCore` — portable Swift core (parsers, scanner, GRDB store, agents, registry, SSH, watcher).
- `Core/chopsd` — Vapor HTTP/WebSocket sidecar on `127.0.0.1:47115`.
- `linux/tauri-app` — Tauri v2 + Svelte 5 desktop shell.
- `scripts/linux` — fixture, smoke, and verification harnesses.

The macOS sources under `Chops/`, `project.yml`, `Chops.xcodeproj`, and `*.plist` are not
modified by the Linux port.

## Prerequisites

- Debian 13 (trixie) or a compatible distribution with X11/Wayland.
- Swift 6.4 toolchain (`swift --version`).
- Rust and Cargo (`rustc --version`).
- Node.js 20+ and npm (`node -v`).
- Tauri/WebKitGTK development packages:

```bash
sudo apt-get update
sudo apt-get install -y build-essential curl wget file libxdo-dev libssl-dev \
  libayatana-appindicator3-dev librsvg2-dev libwebkit2gtk-4.1-dev \
  libgtk-3-dev libsqlite3-dev
```

`swift`, `cargo`, and `npm` must be on `PATH` for non-interactive shells too. If Swift was
installed under `~/.local/bin`, export that directory before building.

## Build the sidecar

```bash
swift build --product chopsd
```

The debug binary is written to `.build/debug/chopsd`.

For a release package, build and stage it where Tauri expects the sidecar:

```bash
swift build -c release --product chopsd
mkdir -p linux/tauri-app/src-tauri/bin
cp .build/release/chopsd linux/tauri-app/src-tauri/bin/chopsd-x86_64-unknown-linux-gnu
chmod +x linux/tauri-app/src-tauri/bin/chopsd-x86_64-unknown-linux-gnu
```

## Run in development

```bash
npm ci --prefix linux/tauri-app
npm run tauri dev --prefix linux/tauri-app
```

This starts the Vite dev server (`http://localhost:5173`) and opens the Chops window. The
Tauri dev command uses the staged sidecar from the previous section.

## Build the Debian package

```bash
cd linux/tauri-app
npm ci
npx tauri build --bundles deb
```

The package is written to
`linux/tauri-app/src-tauri/target/release/bundle/deb/Chops_0.1.0_amd64.deb`.

Install it with:

```bash
sudo dpkg -i linux/tauri-app/src-tauri/target/release/bundle/deb/Chops_0.1.0_amd64.deb
sudo apt-get install -f
```

The package installs `chops-linux`, the bundled `chopsd` sidecar, icons, and a desktop entry.

## Verify the port

```bash
bash scripts/linux/verify.sh
```

Full mode runs:

1. Fixture inventory (`linux/fixtures/home`).
2. `swift build --product chopsd`.
3. `swift test --filter chopscoretests`.
4. Isolated chopsd boot check on loopback with a throwaway fixture `HOME`.
5. REST/WebSocket smoke suite against `chopsd` and the mock registry.
6. Inotify watcher integration tests.

`--fast` skips the live server steps.

Front-end checks:

```bash
cd linux/tauri-app/ui
npm run check
npm test
npm run build
```

## Layout

| Path | Purpose |
|------|---------|
| `Core/ChopsCore/Sources/chopscore` | Portable Swift core |
| `Core/chopsd` | Vapor sidecar and REST/WS routes |
| `linux/fixtures/home` | Synthetic XDG home used by every test |
| `linux/tauri-app/ui` | Svelte 5 front-end |
| `linux/tauri-app/src-tauri` | Tauri Rust shell and bundle config |
| `scripts/linux/verify.sh` | One-command verification |

## Runtime locations

- Database: `${XDG_DATA_HOME:-$HOME/.local/share}/Chops/chops.db`
- Settings: `${XDG_CONFIG_HOME:-$HOME/.config}/chops/settings.json`
- API: `http://127.0.0.1:47115` (`CHOPSD_PORT` overrides the port)

## Troubleshooting

- **`chopsd` not found**: rebuild the sidecar and copy it to
  `linux/tauri-app/src-tauri/bin/chopsd-x86_64-unknown-linux-gnu`.
- **Port already in use**: stop the other listener or set `CHOPSD_PORT` to another value.
- **Missing WebKitGTK**: install `libwebkit2gtk-4.1-dev`.
- **Swift build cache points at another clone**: remove `.build/out/ModuleCache.noindex` and rebuild.
