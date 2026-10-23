# Chops Linux desktop shell (Tauri v2 + SvelteKit/TS + Vite)

Tauri v2 desktop shell for the Chops Linux port. The Svelte 5 + TypeScript
frontend lives in `ui/` (SvelteKit + Vite, static adapter); the Rust shell and
Tauri config live in `src-tauri/`.

## Layout

```
linux/tauri-app/
  package.json          # npm workspace root: dev/build/tauri scripts
  ui/                   # Svelte 5 + TypeScript + Vite frontend (SvelteKit, SPA)
    public/             # static assets, incl. tool-logos/ copied from macOS assets
  src-tauri/            # Rust shell, tauri.conf.json (devUrl :5173, deb bundle)
```

## Prerequisites

Rust toolchain, Node.js ≥ 20, and the Tauri v2 Debian packages
(`libwebkit2gtk-4.1-dev`, `libgtk-3-dev`, `librsvg2-dev`, etc. — see
`linux/docs/`).

## Commands

```bash
npm install                 # installs workspace deps (@tauri-apps/cli + ui)
npm run dev                 # Vite dev server on http://localhost:5173
npm run tauri dev           # Vite + X11/WebKitGTK window (Ctrl+C to stop)
npm run build               # static frontend build -> ui/build
npm run tauri build -- --bundles deb   # packaging (T18; needs src-tauri/bin/chopsd-<triple>)
```

The `chopsd` sidecar binary is not committed; build it from the repo root with
`swift build -c release --product chopsd` and copy it to
`src-tauri/bin/chopsd-x86_64-unknown-linux-gnu` before `tauri build`.
