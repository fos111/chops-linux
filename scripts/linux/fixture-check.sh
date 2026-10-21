#!/usr/bin/env bash
# fixture-check.sh — self-check for the synthetic XDG fixture home (plan task T04).
#
# Asserts the EXACT inventory the Linux port tests rely on:
#   linux/fixtures/home/          — the only test home; never a tmp fs? No: tests copy it.
#   linux/fixtures/fake-claude    — stub one-shot Claude CLI (JSON envelope success path)
#   linux/fixtures/fake-codex     — stub one-shot Codex CLI (writes --output-last-message)
#
# Usage: bash scripts/linux/fixture-check.sh
# Reads ONLY repo files under linux/fixtures — never the real $HOME.
set -u

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fx="$repo/linux/fixtures"
home="$fx/home"
pass=0
fails=0

ok()   { echo "PASS  $1"; pass=$((pass + 1)); }
fail() { echo "FAIL  $1"; fails=$((fails + 1)); }

need_file() { if [ -f "$1" ]; then ok "file     $2"; else fail "missing file: $2"; fi; }
need_dir()  { if [ -d "$1" ]; then ok "dir      $2"; else fail "missing dir: $2"; fi; }

echo "fixture-check: repo=$repo"
echo

echo "== synthetic XDG home inventory (exact per plan) =="
need_dir "$home/.claude/skills"                ".claude/skills"
need_dir "$home/.claude/agents"                ".claude/agents"
need_dir "$home/.cursor/rules"                 ".cursor/rules"
need_dir "$home/.codex/skills"                 ".codex/skills"
need_dir "$home/.config/opencode/skills"       ".config/opencode/skills"
need_dir "$home/.config/amp/skills"            ".config/amp/skills"
need_dir "$home/.claude/skills/sub"            ".claude/skills/sub"

assert_frontmatter() {
  # assert_frontmatter <file> <key> <expected-value> <label>
  local file="$1" key="$2" want="$3" label="$4" got
  got="$(awk -v key="$key" '
    $0 == "---" { depth += 1; next }
    depth == 1 && $0 ~ "^" key ":" {
      sub("^" key "[[:space:]]*:[[:space:]]*", "")
      print
      exit
    }' "$file")"
  if [ "$got" = "$want" ]; then
    ok "frontmatter $2  $label = $want"
  else
    fail "frontmatter $2  $label: expected '$want', got '$got'"
  fi
}

echo "== fixture skills: frontmatter pins =="
assert_frontmatter "$home/.claude/skills/a-one.md"  name        "a-one"   ".claude/skills/a-one.md"
assert_frontmatter "$home/.claude/skills/a-one.md"  description "skill a" ".claude/skills/a-one.md"
assert_frontmatter "$home/.claude/skills/b-two.md"  name        "b-two"   ".claude/skills/b-two.md"
assert_frontmatter "$home/.claude/agents/reviewer.md"  name "reviewer" ".claude/agents/reviewer.md"
assert_frontmatter "$home/.cursor/rules/rule-one.mdc"  name "rule-one" ".cursor/rules/rule-one.mdc"
assert_frontmatter "$home/.codex/skills/c-three.md"    name "c-three"  ".codex/skills/c-three.md"
assert_frontmatter "$home/.config/opencode/skills/o-five.md"  name "o-five"  ".config/opencode/skills/o-five.md"
assert_frontmatter "$home/.config/amp/skills/m-six.md"        name "m-six"   ".config/amp/skills/m-six.md"
assert_frontmatter "$home/.claude/skills/sub/x-eight.md"      name "x-eight" ".claude/skills/sub/x-eight.md"

echo "== malformed fixture tolerated intentionally =="
zb="$home/.claude/skills/z-bad.md"
need_file "$zb" ".claude/skills/z-bad.md"
if head -1 "$zb" | grep -q '^---$' \
   && grep -q '^name:[[:space:]]*$' "$zb"; then
  ok "z-bad.md: frontmatter 'name:' present with empty value (unparsed by design)"
else
  fail "z-bad.md: expected frontmatter with 'name:' carrying no value"
fi

echo "== symlink duplicate (resolved-identity dedup seed) =="
if [ -L "$home/.claude/skills/dup-a-md" ]; then
  if [ "$(readlink "$home/.claude/skills/dup-a-md")" = "a-one.md" ]; then
    ok "symlink  .claude/skills/dup-a-md -> a-one.md"
  else
    fail "symlink .claude/skills/dup-a-md -> unexpected target '$(readlink "$home/.claude/skills/dup-a-md")'"
  fi
else
  fail "missing symlink: .claude/skills/dup-a-md"
fi

echo "== stub one-shot agent binaries =="
if [ -f "$fx/fake-claude" ] && [ -x "$fx/fake-claude" ]; then
  ok "stub     fake-claude (executable)"
else
  fail "fake-claude missing or not executable"
fi
if [ -f "$fx/fake-codex" ] && [ -x "$fx/fake-codex" ]; then
  ok "stub     fake-codex (executable)"
else
  fail "fake-codex missing or not executable"
fi

# Functional smoke in a scratch dir (TMPDIR, never the real $HOME).
TMPDIR_BASE="${TMPDIR:-/tmp/opencode/fixture-check}"
rm -rf "$TMPDIR_BASE"
mkdir -p "$TMPDIR_BASE"

claude_json="$("$fx/fake-claude")"
if printf '%s' "$claude_json" | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d["is_error"] is False
assert isinstance(d["total_cost_usd"], float)
assert "```markdown" in d["result"]
' >/dev/null 2>&1; then
  ok "fake-claude: valid {result,is_error,total_cost_usd} envelope with fenced full file"
else
  fail "fake-claude output is not the one-shot JSON success envelope"
fi

if "$fx/fake-codex" --output-last-message "$TMPDIR_BASE/codex.txt" >/dev/null 2>&1; then
  if [ -s "$TMPDIR_BASE/codex.txt" ] && grep -q '^```markdown' "$TMPDIR_BASE/codex.txt" \
     && grep -q '^```[[:space:]]*$' "$TMPDIR_BASE/codex.txt"; then
    ok "fake-codex: wrote last-message (summary + fenced full file) to --output-last-message path"
  else
    fail "fake-codex last message lacks the summary + fenced file shape"
  fi
else
  fail "fake-codex did not run successfully on the one-shot success path"
fi

if "$fx/fake-codex" >/dev/null 2>&1; then
  fail "fake-codex exited 0 WITHOUT --output-last-message (integrity check should fail loudly)"
else
  ok "fake-codex: loud failure when --output-last-message is absent"
fi

rm -rf "$TMPDIR_BASE"

echo
echo "fixture-check: $pass passed, $fails failed"
if [ "$fails" -ne 0 ]; then
  exit 1
fi
