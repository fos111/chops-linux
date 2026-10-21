#!/usr/bin/env bash
# api-smoke.sh — end-to-end smoke test for the chopsd REST/WS contract (plan T11).
#
# Everything runs against a throwaway COPY of linux/fixtures/home:
#   HOME/XDG_DATA_HOME/XDG_CONFIG_HOME -> $TMP/home
#   PATH starts with a scratch bin exposing the committed stubs as claude/codex
#   CHOPS_SSH_PATH                     -> a local fake ssh (executes the last argv)
#   all registry bases                 -> scripts/linux/mock-registry.py on 47116
#
# Covered: all 23 fixed-contract REST routes + the 2 collection-membership helpers,
# the assist accept-write/reject-discard gate, registry install, remote browse and
# install over the fake SSH, settings persistence, and /ws events (file-changed,
# rescan, assist-status). The real $HOME and the real network are never used.
#
# Usage: scripts/linux/api-smoke.sh
#   CHOPSD_BIN=/path/to/chopsd   override the built binary
#   CHOPSD_PORT=47115            override the HTTP port
#   KEEP_TMP=1                   keep the scratch directory for inspection

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BIN="${CHOPSD_BIN:-$ROOT/.build/debug/chopsd}"
PORT="${CHOPSD_PORT:-47115}"
BASE="http://127.0.0.1:${PORT}"
WS_URL="ws://127.0.0.1:${PORT}/ws"
MOCK_PORT="${CHOPS_MOCK_REGISTRY_PORT:-47116}"
MOCK_URL="http://127.0.0.1:${MOCK_PORT}"

PASSED=0
CHECKS=0

pass() {
    PASSED=$((PASSED + 1))
    echo "PASS $*"
}

fail() {
    echo "FAIL $*" >&2
    exit 1
}

check() {
    CHECKS=$((CHECKS + 1))
    if ! "$@" >/dev/null; then
        fail "check failed: $*"
    fi
}

api() {
    local method="$1" path="$2" body="${3-}"
    if [[ -n "$body" ]]; then
        curl --fail-with-body -sS -X "$method" \
            -H 'content-type: application/json' --data "$body" "$BASE$path"
    else
        curl --fail-with-body -sS -X "$method" "$BASE$path"
    fi
}

# Value of a response header (case-insensitive name), from a `curl -D -` dump.
header_value() {
    local name="$1" headers="$2" want
    want="$(tr '[:upper:]' '[:lower:]' <<<"$name")"
    tr -d '\r' <<<"$headers" | awk -v want="$want" '
        BEGIN { FS = ": " }
        tolower($1) == want { print $2; exit }
    '
}

port_busy() {
    (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null
}

[[ -x "$BIN" ]] || fail "chopsd binary not found/executable at $BIN (run swift build first)"
command -v curl >/dev/null || fail "curl is required"
command -v jq >/dev/null || fail "jq is required"
command -v python3 >/dev/null || fail "python3 is required"
python3 -c 'import websockets' 2>/dev/null || fail "python3 websockets is required"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/chopsd-smoke.XXXXXX")"
chopsd_pid=""
mock_pid=""

cleanup() {
    local status=$?
    if [[ $status -ne 0 && -s "$TMP/chopsd.log" ]]; then
        echo "--- chopsd.log (tail) ---" >&2
        tail -n 80 "$TMP/chopsd.log" >&2 || true
    fi
    if [[ -n "$chopsd_pid" ]]; then
        kill "$chopsd_pid" 2>/dev/null || true
        wait "$chopsd_pid" 2>/dev/null || true
    fi
    if [[ -n "$mock_pid" ]]; then
        kill "$mock_pid" 2>/dev/null || true
        wait "$mock_pid" 2>/dev/null || true
    fi
    if [[ "${KEEP_TMP:-0}" == "1" ]]; then
        echo "scratch directory kept at $TMP"
    else
        rm -rf "$TMP"
    fi
    exit "$status"
}
trap cleanup EXIT

echo "== setup: $TMP"
mkdir -p "$TMP/home" "$TMP/bin" "$TMP/remote/skills/r-one"
cp -a "$ROOT/linux/fixtures/home/." "$TMP/home/"

ln -s "$ROOT/linux/fixtures/fake-claude" "$TMP/bin/claude"
ln -s "$ROOT/linux/fixtures/fake-codex" "$TMP/bin/codex"
chmod +x "$ROOT/linux/fixtures/fake-claude" "$ROOT/linux/fixtures/fake-codex"

stub_claude="$(env HOME="$TMP/home" PATH="$TMP/bin:$PATH" bash -c 'command -v claude')"
[[ "$stub_claude" == "$TMP/bin/claude" ]] \
    || fail "PATH resolves claude to '$stub_claude', not the fixture stub"
stub_codex="$(env HOME="$TMP/home" PATH="$TMP/bin:$PATH" bash -c 'command -v codex')"
[[ "$stub_codex" == "$TMP/bin/codex" ]] \
    || fail "PATH resolves codex to '$stub_codex', not the fixture stub"
echo "PASS PATH stub resolution (claude=$stub_claude codex=$stub_codex)"

cat > "$TMP/remote/skills/r-one/SKILL.md" <<'EOF'
---
name: r-one
description: remote fixture one
---

# R One

Fixture skill served by the fake SSH remote.
EOF

cat > "$TMP/fake-ssh" <<'EOF'
#!/usr/bin/env bash
# Fake ssh: the last argv element is the remote command; run it locally.
set -eu
last="${!#}"
exec bash -c "$last"
EOF
chmod +x "$TMP/fake-ssh"

echo "== setup: mock registry on $MOCK_PORT"
if [[ -n "$(curl -sS --max-time 2 "$MOCK_URL/__health" 2>/dev/null)" ]] \
    && curl -sS --max-time 2 "$MOCK_URL/__health" | jq -e '.service == "chops-mock-registry"' >/dev/null; then
    echo "reusing existing mock registry on $MOCK_PORT"
else
    if port_busy "$MOCK_PORT"; then
        fail "port $MOCK_PORT is already in use by something other than mock-registry.py"
    fi
    python3 "$ROOT/scripts/linux/mock-registry.py" --port "$MOCK_PORT" \
        > "$TMP/mock-registry.log" 2>&1 &
    mock_pid=$!
    for _ in $(seq 1 100); do
        if curl -sS --max-time 1 "$MOCK_URL/__health" 2>/dev/null \
            | jq -e '.service == "chops-mock-registry"' >/dev/null; then
            break
        fi
        kill -0 "$mock_pid" 2>/dev/null || fail "mock registry exited during startup"
        sleep 0.1
    done
    curl -sS --max-time 2 "$MOCK_URL/__health" \
        | jq -e '.service == "chops-mock-registry"' >/dev/null \
        || fail "mock registry did not become healthy on $MOCK_PORT"
    echo "started mock registry (pid $mock_pid)"
fi

if port_busy "$PORT"; then
    fail "port $PORT is already in use; stop the other chopsd or set CHOPSD_PORT"
fi

echo "== setup: launching chopsd on $PORT"
env \
    HOME="$TMP/home" \
    XDG_DATA_HOME="$TMP/home/.local/share" \
    XDG_CONFIG_HOME="$TMP/home/.config" \
    PATH="$TMP/bin:$PATH" \
    CHOPSD_PORT="$PORT" \
    CHOPS_SSH_PATH="$TMP/fake-ssh" \
    CHOPS_REGISTRY_BASE_URL="$MOCK_URL" \
    CHOPS_GITHUB_RAW_BASE_URL="$MOCK_URL" \
    CHOPS_GITHUB_API_BASE_URL="$MOCK_URL" \
    NO_PROXY="127.0.0.1,localhost" \
    no_proxy="127.0.0.1,localhost" \
    "$BIN" > "$TMP/chopsd.log" 2>&1 &
chopsd_pid=$!

for _ in $(seq 1 150); do
    if curl -fsS --max-time 1 "$BASE/api/tools" >/dev/null 2>&1; then
        break
    fi
    kill -0 "$chopsd_pid" 2>/dev/null || fail "chopsd exited during startup (see log)"
    sleep 0.1
done
curl -fsS --max-time 2 "$BASE/api/tools" >/dev/null \
    || fail "chopsd did not become healthy on $BASE"

# ---------------------------------------------------------------------------
# Tools
# ---------------------------------------------------------------------------
tools="$(api GET /api/tools)"
check jq -e '
    length > 0
    and (map(select(.id == "claude"))[0].isInstalled == true)
    and (map(select(.id == "augment"))[0].isInstalled == false)
    and (map(select(.id == "claude"))[0] | has("globalPaths"))
' <<<"$tools"

echo "== GET /api/tools"
pass "GET /api/tools (13 listable tools, claude installed / augment absent)"

# ---------------------------------------------------------------------------
# CORS: the Tauri webview is cross-origin to 127.0.0.1:47115
# ---------------------------------------------------------------------------
cors_headers="$(curl -sS -D - -o /dev/null -H 'Origin: tauri://localhost' "$BASE/api/tools")"
cors_origin="$(header_value 'Access-Control-Allow-Origin' "$cors_headers")"
[[ "$cors_origin" == "tauri://localhost" ]] \
    || fail "GET /api/tools did not reflect the Tauri origin (got '${cors_origin:-<missing>}')"
grep -qi '^vary: origin' <<<"$(tr -d '\r' <<<"$cors_headers")" \
    || fail "GET /api/tools is missing Vary: Origin"

echo "== CORS GET /api/tools"
pass "CORS GET /api/tools (Origin: tauri://localhost -> ACAO echo + Vary: Origin)"

preflight_headers="$(curl -sS -D - -o /dev/null -X OPTIONS \
    -H 'Origin: http://localhost:5173' \
    -H 'Access-Control-Request-Method: POST' \
    -H 'Access-Control-Request-Headers: content-type, authorization' \
    "$BASE/api/tools")"
preflight_status="$(head -n 1 <<<"$preflight_headers" | awk '{print $2}')"
[[ "$preflight_status" == "204" ]] \
    || fail "OPTIONS /api/tools returned ${preflight_status:-<none>}, expected 204"
[[ "$(header_value 'Access-Control-Allow-Origin' "$preflight_headers")" == "http://localhost:5173" ]] \
    || fail "OPTIONS /api/tools did not reflect the Vite dev origin"
grep -qi '^access-control-allow-methods: GET, POST, PUT, DELETE, OPTIONS' \
    <<<"$(tr -d '\r' <<<"$preflight_headers")" \
    || fail "OPTIONS /api/tools is missing the allowed methods"
grep -qi '^access-control-allow-headers: Content-Type, Authorization' \
    <<<"$(tr -d '\r' <<<"$preflight_headers")" \
    || fail "OPTIONS /api/tools is missing the allowed headers"

echo "== CORS OPTIONS /api/tools"
pass "CORS OPTIONS /api/tools (preflight -> 204 + allow-methods/headers)"

# ---------------------------------------------------------------------------
# Skills: list, filters, detail, editor save, template create
# ---------------------------------------------------------------------------
skills="$(api GET /api/skills)"
check jq -e 'length >= 8 and ([.[].name] | index("a-one")) and ([.[].name] | index("b-two"))' <<<"$skills"

a_one_id="$(jq -r '.[] | select(.name == "a-one") | .id' <<<"$skills" | head -n 1)"
b_two_id="$(jq -r '.[] | select(.name == "b-two") | .id' <<<"$skills" | head -n 1)"
c_three_id="$(jq -r '.[] | select(.name == "c-three") | .id' <<<"$skills" | head -n 1)"
[[ -n "$a_one_id" && -n "$b_two_id" && -n "$c_three_id" ]] || fail "fixture skills were not scanned"

echo "== GET /api/skills"
pass "GET /api/skills (8+ fixture rows; ids a-one=$a_one_id b-two=$b_two_id c-three=$c_three_id)"

codex_only="$(api GET '/api/skills?tool=codex')"
check jq -e 'length == 1 and .[0].name == "c-three"' <<<"$codex_only"

echo "== GET /api/skills?tool=codex"
pass "GET /api/skills?tool=codex (only c-three)"

search_hits="$(api GET '/api/skills?q=b-two')"
check jq -e 'length >= 1 and ([.[].name] | index("b-two") != null)' <<<"$search_hits"

echo "== GET /api/skills?q=b-two"
pass "GET /api/skills?q=b-two (search finds the fixture)"

detail="$(api GET "/api/skills/$a_one_id")"
check jq -e --argjson id "$a_one_id" \
    '.id == $id and .name == "a-one" and (.content | contains("# a-one"))' <<<"$detail"

echo "== GET /api/skills/{id}"
pass "GET /api/skills/$a_one_id (raw Markdown body)"

edited_a_one=$'---\nname: a-one\ndescription: skill a (smoke-edited)\n---\n\n# a-one\n\nEdited by scripts/linux/api-smoke.sh via PUT /api/skills/{id}.\n'
saved="$(api PUT "/api/skills/$a_one_id" "$(jq -n --arg content "$edited_a_one" '{content: $content}')")"
check jq -e --argjson id "$a_one_id" '.id == $id and .description == "skill a (smoke-edited)" and (.content | contains("api-smoke.sh"))' <<<"$saved"
grep -q 'api-smoke.sh' "$TMP/home/.claude/skills/a-one.md" || fail "PUT did not write the file to disk"

echo "== PUT /api/skills/{id}"
pass "PUT /api/skills/$a_one_id (full file written to disk + rescanned)"

created="$(api POST /api/skills '{"name":"Smoke Created","tool":"claude","kind":"skill"}')"
check jq -e '.name == "smoke-created" and .kind == "skill" and (.filePath | endswith("/.claude/skills/smoke-created/SKILL.md"))' <<<"$created"
[[ -f "$TMP/home/.claude/skills/smoke-created/SKILL.md" ]] || fail "POST /api/skills did not create the boilerplate file"

echo "== POST /api/skills"
pass "POST /api/skills (template boilerplate + scan)"

# ---------------------------------------------------------------------------
# Assist: accept writes the fenced full file, reject discards
# ---------------------------------------------------------------------------
assist="$(api POST /api/assist "$(jq -n --argjson id "$a_one_id" '{skillId: $id, prompt: "Rewrite the heading for the smoke test.", agent: "claude"}')")"
pending_id="$(jq -r '.pendingId // empty' <<<"$assist")"
[[ -n "$pending_id" ]] || fail "assist did not return a pendingId: $assist"
check jq -e '.agent == "claude" and (.fullFile | contains("stub-edit"))' <<<"$assist"

echo "== POST /api/assist"
pass "POST /api/assist (claude stub -> pendingId $pending_id + fullFile)"

accepted="$(api POST "/api/assist/$pending_id/accept")"
check jq -e '.accepted == true and (.path | endswith("/.claude/skills/a-one.md"))' <<<"$accepted"
grep -q 'A One (stub-edit)' "$TMP/home/.claude/skills/a-one.md" || fail "assist accept did not write the fenced content"

echo "== POST /api/assist/{pendingId}/accept"
pass "POST /api/assist/$pending_id/accept (fenced content written)"

c_three_before="$(sha256sum "$TMP/home/.codex/skills/c-three.md" | awk '{print $1}')"
assist_reject="$(api POST /api/assist "$(jq -n --argjson id "$c_three_id" '{skillId: $id, prompt: "This proposal must be discarded.", agent: "claude"}')")"
pending_reject="$(jq -r '.pendingId // empty' <<<"$assist_reject")"
[[ -n "$pending_reject" ]] || fail "reject-path assist did not return a pendingId"
rejected="$(api POST "/api/assist/$pending_reject/reject")"
check jq -e '.rejected == true' <<<"$rejected"
c_three_after="$(sha256sum "$TMP/home/.codex/skills/c-three.md" | awk '{print $1}')"
[[ "$c_three_before" == "$c_three_after" ]] || fail "assist reject modified the target file"

echo "== POST /api/assist/{pendingId}/reject"
pass "POST /api/assist/$pending_reject/reject (file unchanged, sha256 match)"

# ---------------------------------------------------------------------------
# Collections (CRUD + membership join table)
# ---------------------------------------------------------------------------
collection="$(api POST /api/collections '{"name":"Smoke Collection","icon":"star","sortOrder":7}')"
collection_id="$(jq -r '.id' <<<"$collection")"
check jq -e '.name == "Smoke Collection" and .icon == "star" and .skillCount == 0' <<<"$collection"

echo "== POST /api/collections"
pass "POST /api/collections (id $collection_id)"

collections="$(api GET /api/collections)"
check jq -e --argjson id "$collection_id" 'any(.id == $id and .skillCount == 0)' <<<"$collections"

echo "== GET /api/collections"
pass "GET /api/collections (new collection listed)"

collection_detail="$(api GET "/api/collections/$collection_id")"
check jq -e '.collection.id == $id and (.skills | length) == 0' \
    --argjson id "$collection_id" <<<"$collection_detail"

echo "== GET /api/collections/{id}"
pass "GET /api/collections/$collection_id (empty detail)"

membership="$(api POST "/api/collections/$collection_id/skills" "$(jq -n --argjson id "$a_one_id" '{skillId: $id}')")"
check jq -e '.added == true' <<<"$membership"

echo "== POST /api/collections/{id}/skills"
pass "POST /api/collections/$collection_id/skills (added a-one)"

collection_detail="$(api GET "/api/collections/$collection_id")"
check jq -e '.collection.skillCount == 1 and (.skills | length) == 1 and .skills[0].name == "a-one"' <<<"$collection_detail"

unmembership="$(api DELETE "/api/collections/$collection_id/skills/$a_one_id")"
check jq -e '.removed == true' <<<"$unmembership"

echo "== DELETE /api/collections/{id}/skills/{skillId}"
pass "DELETE /api/collections/$collection_id/skills/$a_one_id (membership removed)"

deleted_collection="$(api DELETE "/api/collections/$collection_id")"
check jq -e '.deleted == true' <<<"$deleted_collection"

echo "== DELETE /api/collections/{id}"
pass "DELETE /api/collections/$collection_id"

# ---------------------------------------------------------------------------
# Settings
# ---------------------------------------------------------------------------
settings="$(api GET /api/settings)"
check jq -e '.theme == "system" and (.settingsPath | endswith("/chops/settings.json")) and (.databasePath | endswith("/Chops/chops.db"))' <<<"$settings"

echo "== GET /api/settings"
pass "GET /api/settings (theme=system, XDG paths)"

updated_settings="$(api PUT /api/settings '{"theme":"dark","includePluginSkills":true}')"
check jq -e '.theme == "dark" and .includePluginSkills == true' <<<"$updated_settings"
check jq -e '.theme == "dark"' "$TMP/home/.config/chops/settings.json"

echo "== PUT /api/settings"
pass "PUT /api/settings (theme=dark persisted to settings.json)"

# ---------------------------------------------------------------------------
# Registry (mock skills.sh + GitHub on 47116)
# ---------------------------------------------------------------------------
trending="$(api GET /api/registry/trending)"
check jq -e 'length > 0 and ([.[].skillId] | index("pdf-tools") != null)' <<<"$trending"

echo "== GET /api/registry/trending"
pass "GET /api/registry/trending (mock RSC payload parsed)"

registry_search="$(api GET '/api/registry/search?q=pdf')"
check jq -e 'any(.skillId == "pdf-tools")' <<<"$registry_search"

echo "== GET /api/registry/search?q=pdf"
pass "GET /api/registry/search (mock skills.sh results)"

installed="$(api POST /api/registry/install '{"skillId":"pdf-tools","name":"PDF Tools","source":"acme/skills","targets":["claude"]}')"
check jq -e '.installed == true and .skillName == "pdf-tools" and .targets == ["claude"]' <<<"$installed"
[[ -f "$TMP/home/.agents/skills/pdf-tools/SKILL.md" ]] || fail "registry install did not write the canonical SKILL.md"
[[ -L "$TMP/home/.claude/skills/pdf-tools" ]] || fail "registry install did not symlink the claude target"

echo "== POST /api/registry/install"
pass "POST /api/registry/install (canonical file + claude symlink)"

# ---------------------------------------------------------------------------
# Remote servers (fake SSH)
# ---------------------------------------------------------------------------
remote_body="$(jq -n --arg path "$TMP/remote/skills" '{id: "smoke-remote", label: "Smoke Remote", host: "localhost", port: 22, username: "smoke", skillsBasePath: $path}')"
remote="$(api POST /api/remote/servers "$remote_body")"
check jq -e '.id == "smoke-remote" and .label == "Smoke Remote" and .port == 22' <<<"$remote"

echo "== POST /api/remote/servers"
pass "POST /api/remote/servers (smoke-remote)"

remote_list="$(api GET /api/remote/servers)"
check jq -e 'any(.id == "smoke-remote")' <<<"$remote_list"

echo "== GET /api/remote/servers"
pass "GET /api/remote/servers (server listed)"

remote_update="$(api PUT /api/remote/servers/smoke-remote "$(jq -n --arg path "$TMP/remote/skills" '{label: "Smoke Remote 2", host: "localhost", port: 22, username: "smoke", skillsBasePath: $path}')")"
check jq -e '.label == "Smoke Remote 2"' <<<"$remote_update"

echo "== PUT /api/remote/servers/{id}"
pass "PUT /api/remote/servers/smoke-remote (label updated)"

browse="$(api POST /api/remote/browse '{"serverId":"smoke-remote"}')"
check jq -e '(.skills | length) == 1 and .skills[0].name == "r-one" and (.skills[0].content | contains("fake SSH remote"))' <<<"$browse"

echo "== POST /api/remote/browse"
pass "POST /api/remote/browse (find + combined cat over fake SSH)"

remote_skill_id="$(api GET /api/skills | jq -r '.[] | select(.remoteServerID == "smoke-remote") | .id' | head -n 1)"
[[ -n "$remote_skill_id" ]] || fail "browse did not upsert a remote:// skill row"
remote_edit=$'---\nname: r-one\ndescription: remote fixture one\n---\n\n# R One\n\nEdited over fake SSH by api-smoke.sh.\n'
remote_saved="$(api PUT "/api/skills/$remote_skill_id" "$(jq -n --arg content "$remote_edit" '{content: $content}')")"
check jq -e '.remoteServerID == "smoke-remote" and (.content | contains("fake SSH"))' <<<"$remote_saved"
grep -q 'Edited over fake SSH' "$TMP/remote/skills/r-one/SKILL.md" || fail "remote PUT did not write through SSH"

echo "== PUT /api/skills/{id} (remote://)"
pass "PUT /api/skills/$remote_skill_id (remote write through fake SSH)"

remote_installed="$(api POST /api/remote/install "$(jq -n --arg path "$TMP/remote/skills/r-one/SKILL.md" '{serverId: "smoke-remote", remotePath: $path, targets: ["claude"]}')")"
check jq -e '.installed == true and .skillName == "r-one" and .targets == ["claude"]' <<<"$remote_installed"
[[ -f "$TMP/home/.agents/skills/r-one/SKILL.md" ]] || fail "remote install did not write the canonical SKILL.md"

echo "== POST /api/remote/install"
pass "POST /api/remote/install (SSH read -> local install)"

remote_deleted="$(api DELETE /api/remote/servers/smoke-remote)"
check jq -e '.deleted == true' <<<"$remote_deleted"

echo "== DELETE /api/remote/servers/{id}"
pass "DELETE /api/remote/servers/smoke-remote"

# ---------------------------------------------------------------------------
# WebSocket: file-changed + rescan after a fixture micro-write, assist-status
# ---------------------------------------------------------------------------
echo "== WS /ws"
python3 - "$WS_URL" "$BASE" "$TMP/home/.claude/skills/b-two.md" "$c_three_id" <<'PY'
import asyncio
import json
import pathlib
import sys
import urllib.request

import websockets

ws_url, base, target, skill_id = sys.argv[1], sys.argv[2], pathlib.Path(sys.argv[3]), int(sys.argv[4])


def post(path, payload):
    request = urllib.request.Request(
        base + path,
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.loads(response.read())


async def collect(ws, predicate, timeout, label):
    seen = []
    async with asyncio.timeout(timeout):
        while True:
            event = json.loads(await ws.recv())
            seen.append(event)
            if predicate(seen):
                return seen
    raise AssertionError(f"timed out waiting for {label}; saw {seen}")


async def main():
    async with websockets.connect(ws_url) as ws:
        # Give Vapor a beat to finish the upgrade before the write races the watcher.
        await asyncio.sleep(0.35)
        original = target.read_text()
        try:
            target.write_text(original + "\n")
            events = await collect(
                ws,
                lambda seen: {"file-changed", "rescan"} <= {event.get("type") for event in seen},
                10,
                "file-changed + rescan",
            )
            changed = [event for event in events if event.get("type") == "file-changed"]
            rescans = [event for event in events if event.get("type") == "rescan"]
            assert changed and changed[0]["path"] == str(target), changed
            assert changed[0]["kind"] == "modified", changed
            assert rescans and isinstance(rescans[0].get("count"), int), rescans
            print(f"PASS WS file-changed + rescan after micro-write ({len(events)} frames)")

            response = await asyncio.to_thread(
                post,
                "/api/assist",
                {"skillId": skill_id, "prompt": "WS assist-status probe.", "agent": "claude"},
            )
            pending_id = response.get("pendingId")
            assert pending_id, response
            assist_events = await collect(
                ws,
                lambda seen: {"running", "pending"} <= {
                    event.get("status")
                    for event in seen
                    if event.get("type") == "assist-status"
                },
                10,
                "assist-status running + pending",
            )
            statuses = {event.get("status") for event in assist_events if event.get("type") == "assist-status"}
            assert "running" in statuses and "pending" in statuses, assist_events
            print(f"PASS WS assist-status ({sorted(s for s in statuses if s)})")
            await asyncio.to_thread(post, f"/api/assist/{pending_id}/reject", {})
        finally:
            target.write_text(original)


asyncio.run(main())
PY
pass "WS /ws (file-changed + rescan + assist-status)"
CHECKS=$((CHECKS + 1))

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo "============================================================"
echo "SMOKE PASS: 25 REST routes + WS; $PASSED endpoint groups, $CHECKS assertions"
echo "  temp home: $TMP/home"
echo "  chopsd log: $TMP/chopsd.log"
echo "============================================================"
