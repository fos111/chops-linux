#!/usr/bin/env bash
# verify.sh — one-command verification for the Linux port (plan T12).
#
# Full mode (default):
#   1. scripts/linux/fixture-check.sh          synthetic XDG fixture inventory
#   2. swift build --product chopsd           sidecar builds
#   3. swift test --filter chopscoretests     full core suite (library + fixtures)
#   4. chopsd boot check                      binds 127.0.0.1:${CHOPSD_PORT:-47115},
#                                             HOME/XDG -> throwaway fixture copy,
#                                             fixture stubs first on PATH
#   5. scripts/linux/api-smoke.sh             REST/WS contract over loopback
#   6. watcher-only rerun                     T10 FileWatcherInotifyTests
#
# --fast skips the live parts (4-6); the unit suite in step 3 still covers the
# watcher and everything else that does not need a listening server.
#
# Safety guarantees:
#   * The real $HOME is never scanned or written: chopsd always runs with
#     HOME/XDG_DATA_HOME/XDG_CONFIG_HOME pointed at a mktemp copy of
#     linux/fixtures/home, and the committed claude/codex stubs sit first on PATH.
#   * No real network: api-smoke points every registry base at its committed mock
#     registry; this script points the boot-check bases at an unbound loopback
#     address and exports NO_PROXY for 127.0.0.1/localhost.
#   * Re-runnable: scratch state lives in mktemp and is removed on EXIT; if the
#     default ports are busy (and no explicit override was given) free loopback
#     ports are picked and recorded in the transcript.
#
# Transcript: qa/t12/verify.txt (next to the repository root).
#
# Usage: bash scripts/linux/verify.sh [--fast]
# Env:   CHOPSD_PORT                 preferred chopsd port (default 47115)
#        CHOPS_MOCK_REGISTRY_PORT    preferred mock-registry port (default 47116)
#        TMPDIR                      scratch parent (default /tmp)

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TRANSCRIPT="$ROOT/qa/t12/verify.txt"
MODE="full"

for arg in "$@"; do
    case "$arg" in
        --fast) MODE="fast" ;;
        -h|--help)
            echo "usage: bash scripts/linux/verify.sh [--fast]"
            exit 0
            ;;
        *)
            echo "unknown argument: $arg" >&2
            echo "usage: bash scripts/linux/verify.sh [--fast]" >&2
            exit 1
            ;;
    esac
done

mkdir -p "$(dirname "$TRANSCRIPT")"
: > "$TRANSCRIPT"

log() {
    printf '%s\n' "$*" | tee -a "$TRANSCRIPT"
}

fail() {
    log "FAIL: $*"
    exit 1
}

# Run a command, show it in the transcript, and stop the harness on failure.
run() {
    log "\$ $*"
    set +e
    "$@" 2>&1 | tee -a "$TRANSCRIPT"
    local rc=${PIPESTATUS[0]}
    set -e
    if [ "$rc" -ne 0 ]; then
        fail "command exited $rc: $*"
    fi
}

port_busy() {
    (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null
}

free_port() {
    python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()'
}

# ---------------------------------------------------------------------------
# Header / prerequisites
# ---------------------------------------------------------------------------
log "============================================================"
log "chops Linux verification (plan T12)"
log "started:  $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
log "mode:     $MODE"
log "repo:     $ROOT"
if git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    log "commit:   $(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown) ($(git -C "$ROOT" branch --show-current 2>/dev/null || echo detached))"
fi
log "host:     $(uname -srm)"
log "transcript: $TRANSCRIPT"
log "============================================================"

# Swift is commonly installed under ~/.local/bin (swiftly) and may not be in a
# non-interactive PATH. Do not otherwise touch the real $HOME here.
if ! command -v swift >/dev/null 2>&1; then
    if [ -x "$HOME/.local/bin/swift" ]; then
        export PATH="$HOME/.local/bin:$PATH"
    elif [ -f "$HOME/.local/share/swiftly/env.sh" ]; then
        # shellcheck disable=SC1090
        . "$HOME/.local/share/swiftly/env.sh" >/dev/null 2>&1 || true
    fi
fi

command -v swift  >/dev/null 2>&1 || fail "swift not found on PATH (install Swift 6.x or add swiftly to PATH)"
command -v python3 >/dev/null 2>&1 || fail "python3 is required"
if [ "$MODE" = "full" ]; then
    command -v curl >/dev/null 2>&1 || fail "curl is required for the full harness"
    command -v jq   >/dev/null 2>&1 || fail "jq is required for the full harness"
    python3 -c 'import websockets' >/dev/null 2>&1 \
        || fail "python3 'websockets' is required for api-smoke (python3 -m pip install --user websockets)"
fi

run swift --version

TMP="$(mktemp -d "${TMPDIR:-/tmp}/chops-verify.XXXXXX")"
BOOT_PID=""

cleanup() {
    status=$?
    if [ -n "$BOOT_PID" ]; then
        kill "$BOOT_PID" 2>/dev/null || true
        wait "$BOOT_PID" 2>/dev/null || true
    fi
    rm -rf "$TMP"
    if [ "$status" -eq 0 ]; then
        log "verify: PASS ($MODE mode, $(date -u '+%Y-%m-%dT%H:%M:%SZ'))"
    else
        log "verify: FAIL (exit $status)"
    fi
    exit "$status"
}
trap cleanup EXIT

export NO_PROXY="127.0.0.1,localhost"
export no_proxy="127.0.0.1,localhost"

# ---------------------------------------------------------------------------
# 1. Fixture inventory
# ---------------------------------------------------------------------------
log ""
log "== [1/6] fixture-check =="
run bash "$ROOT/scripts/linux/fixture-check.sh"

# ---------------------------------------------------------------------------
# 2. Build the sidecar
# ---------------------------------------------------------------------------
log ""
log "== [2/6] swift build --product chopsd =="
run swift build --product chopsd
CHOPSD_BIN="$ROOT/.build/debug/chopsd"
[ -x "$CHOPSD_BIN" ] || fail "chopsd binary not found/executable at $CHOPSD_BIN"

# ---------------------------------------------------------------------------
# 3. Full core test suite
# ---------------------------------------------------------------------------
log ""
log "== [3/6] swift test --filter chopscoretests =="
run swift test --filter chopscoretests

if [ "$MODE" = "fast" ]; then
    log ""
    log "== --fast: skipping chopsd boot check, api-smoke, and the watcher-only rerun =="
    log "== (step 3 already executed FileWatcherInotifyTests inside chopscoretests) =="
    log ""
    log "verify: fast checks complete"
    exit 0
fi

# ---------------------------------------------------------------------------
# 4. chopsd boot check (isolated fixture HOME, loopback only)
# ---------------------------------------------------------------------------
log ""
log "== [4/6] chopsd boot check =="

PORT_EXPLICIT=0
if [ -n "${CHOPSD_PORT:-}" ]; then
    PORT_EXPLICIT=1
fi
PORT="${CHOPSD_PORT:-47115}"
if port_busy "$PORT"; then
    if [ "$PORT_EXPLICIT" -eq 1 ]; then
        fail "port $PORT is already in use (CHOPSD_PORT is set); stop the other listener or choose another CHOPSD_PORT"
    fi
    PORT="$(free_port)"
    log "note: 127.0.0.1:47115 is busy; using free port $PORT for this run"
fi
export CHOPSD_PORT="$PORT"

MOCK_EXPLICIT=0
if [ -n "${CHOPS_MOCK_REGISTRY_PORT:-}" ]; then
    MOCK_EXPLICIT=1
fi
MOCK_PORT="${CHOPS_MOCK_REGISTRY_PORT:-47116}"
if port_busy "$MOCK_PORT" || [ "$MOCK_PORT" = "$PORT" ]; then
    if [ "$MOCK_EXPLICIT" -eq 1 ] && [ "$MOCK_PORT" != "$PORT" ]; then
        log "note: 127.0.0.1:$MOCK_PORT is busy; api-smoke will report if it is not a compatible mock"
    else
        MOCK_PORT="$(free_port)"
        while [ "$MOCK_PORT" = "$PORT" ]; do
            MOCK_PORT="$(free_port)"
        done
        log "note: using free mock-registry port $MOCK_PORT for this run"
    fi
fi
export CHOPS_MOCK_REGISTRY_PORT="$MOCK_PORT"

BOOT_HOME="$TMP/boot/home"
BOOT_BIN="$TMP/boot/bin"
mkdir -p "$BOOT_HOME" "$BOOT_BIN" "$BOOT_HOME/.local/share" "$BOOT_HOME/.config"
cp -a "$ROOT/linux/fixtures/home/." "$BOOT_HOME/"
ln -s "$ROOT/linux/fixtures/fake-claude" "$BOOT_BIN/claude"
ln -s "$ROOT/linux/fixtures/fake-codex" "$BOOT_BIN/codex"
chmod +x "$ROOT/linux/fixtures/fake-claude" "$ROOT/linux/fixtures/fake-codex"

stub_claude="$(env HOME="$BOOT_HOME" PATH="$BOOT_BIN:$PATH" bash -c 'command -v claude')"
[ "$stub_claude" = "$BOOT_BIN/claude" ] \
    || fail "PATH resolved claude to '$stub_claude', not the fixture stub"
stub_codex="$(env HOME="$BOOT_HOME" PATH="$BOOT_BIN:$PATH" bash -c 'command -v codex')"
[ "$stub_codex" = "$BOOT_BIN/codex" ] \
    || fail "PATH resolved codex to '$stub_codex', not the fixture stub"
log "PASS PATH stub resolution (claude=$stub_claude codex=$stub_codex)"

BOOT_BASE="http://127.0.0.1:$PORT"
BOOT_DB="$BOOT_HOME/.local/share/Chops/chops.db"
BOOT_SETTINGS="$BOOT_HOME/.config/chops/settings.json"

env \
    HOME="$BOOT_HOME" \
    XDG_DATA_HOME="$BOOT_HOME/.local/share" \
    XDG_CONFIG_HOME="$BOOT_HOME/.config" \
    PATH="$BOOT_BIN:$PATH" \
    CHOPSD_PORT="$PORT" \
    CHOPS_REGISTRY_BASE_URL="http://127.0.0.1:9" \
    CHOPS_GITHUB_RAW_BASE_URL="http://127.0.0.1:9" \
    CHOPS_GITHUB_API_BASE_URL="http://127.0.0.1:9" \
    NO_PROXY="127.0.0.1,localhost" \
    no_proxy="127.0.0.1,localhost" \
    "$CHOPSD_BIN" > "$TMP/boot/chopsd.log" 2>&1 &
BOOT_PID=$!
log "started chopsd pid $BOOT_PID on $BOOT_BASE with HOME=$BOOT_HOME"

ready=0
for ((i = 0; i < 150; i++)); do
    if curl --noproxy '*' -fsS --max-time 1 "$BOOT_BASE/api/tools" > "$TMP/boot/tools.json" 2>/dev/null; then
        ready=1
        break
    fi
    if ! kill -0 "$BOOT_PID" 2>/dev/null; then
        log "--- chopsd.log (tail) ---"
        tail -n 80 "$TMP/boot/chopsd.log" 2>&1 | tee -a "$TRANSCRIPT" || true
        fail "chopsd exited during startup"
    fi
    sleep 0.1
done
if [ "$ready" -ne 1 ]; then
    log "--- chopsd.log (tail) ---"
    tail -n 80 "$TMP/boot/chopsd.log" 2>&1 | tee -a "$TRANSCRIPT" || true
    fail "chopsd did not become healthy on $BOOT_BASE"
fi

jq -e 'length > 0 and (map(select(.id == "claude"))[0].isInstalled == true)' \
    "$TMP/boot/tools.json" >/dev/null \
    || fail "GET /api/tools did not report the fixture claude stub as installed"
log "PASS GET /api/tools (fixture claude installed)"

curl --noproxy '*' -fsS --max-time 2 "$BOOT_BASE/api/settings" > "$TMP/boot/settings.json" \
    || fail "GET /api/settings failed on the boot check"
jq -e --arg db "$BOOT_DB" --arg settings "$BOOT_SETTINGS" \
    '.databasePath == $db and .settingsPath == $settings' \
    "$TMP/boot/settings.json" >/dev/null \
    || fail "chopsd resolved XDG paths outside the fixture copy (db=$BOOT_DB settings=$BOOT_SETTINGS)"
[ -f "$BOOT_DB" ] || fail "chopsd did not create the fixture-copy database at $BOOT_DB"
log "PASS XDG isolation (db=$BOOT_DB)"

kill "$BOOT_PID" 2>/dev/null || true
wait "$BOOT_PID" 2>/dev/null || true
BOOT_PID=""
for ((i = 0; i < 50; i++)); do
    port_busy "$PORT" || break
    sleep 0.1
done
if port_busy "$PORT"; then
    fail "port $PORT stayed busy after chopsd shutdown"
fi
log "PASS chopsd boot check (127.0.0.1:$PORT, isolated fixture HOME)"

# ---------------------------------------------------------------------------
# 5. REST/WS contract smoke
# ---------------------------------------------------------------------------
log ""
log "== [5/6] api-smoke =="
log "ports: chopsd=$CHOPSD_PORT mock-registry=$CHOPS_MOCK_REGISTRY_PORT"
run bash "$ROOT/scripts/linux/api-smoke.sh"

# ---------------------------------------------------------------------------
# 6. Watcher-only rerun (explicit T10 proof)
# ---------------------------------------------------------------------------
log ""
log "== [6/6] watcher test (FileWatcherInotifyTests) =="
WATCH_LOG="$TMP/watcher.log"
log "\$ swift test --filter FileWatcherInotifyTests"
set +e
swift test --filter FileWatcherInotifyTests 2>&1 | tee -a "$TRANSCRIPT" | tee "$WATCH_LOG"
watch_rc=${PIPESTATUS[0]}
set -e
if [ "$watch_rc" -ne 0 ]; then
    fail "watcher test failed (exit $watch_rc)"
fi
grep -q 'FileWatcherInotifyTests' "$WATCH_LOG" \
    || fail "watcher filter matched no FileWatcherInotifyTests output"
if grep -qE 'Executed 0 tests' "$WATCH_LOG"; then
    fail "watcher filter executed 0 tests"
fi
log "PASS watcher test (FileWatcherInotifyTests)"

log ""
log "verify: all checks complete"
