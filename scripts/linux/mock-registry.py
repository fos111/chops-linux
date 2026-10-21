#!/usr/bin/env python3
"""Canned local stand-in for skills.sh + GitHub (raw + REST) used by T09 tests.

The registry client's four bases are injectable, so the test suite points them all at
this server (`127.0.0.1:47116`) and exercises the EXACT production endpoint shapes:

  GET /api/search?q=<query>&limit=30          skills.sh search JSON
  GET /trending                               skills.sh Next.js RSC HTML
  GET /<owner>/<repo>/<branch>/<path>         raw.githubusercontent.com file
  GET /repos/<owner>/<repo>                   api.github.com repo metadata
  GET /repos/<owner>/<repo>/git/trees/<branch>?recursive=1
                                              api.github.com tree listing

Diagnostics (not part of the real upstream APIs):
  GET /__health                               readiness probe
  GET /__requests                             access log for cache assertions

This process only ever binds loopback; nothing in the suite reaches the real network.
"""

from __future__ import annotations

import argparse
import json
import signal
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

HOST = "127.0.0.1"
DEFAULT_PORT = 47116

SEARCH_SKILLS = [
    {
        "id": "acme/skills/pdf-tools",
        "skillId": "pdf-tools",
        "name": "PDF Tools",
        "installs": 12500,
        "source": "acme/skills",
        "isOfficial": True,
    },
    {
        "id": "acme/skills/web-audit",
        "skillId": "web-audit",
        "name": "Web Audit",
        "installs": 340,
        "source": "acme/skills",
        "isOfficial": False,
    },
    {
        "id": "acme/skills/root-skill",
        "skillId": "root-skill",
        "name": "Root Skill",
        "installs": 42,
        "source": "acme/skills",
        "isOfficial": False,
    },
    {
        "id": "acme/skills/tree-only",
        "skillId": "tree-only",
        "name": "Tree Only",
        "installs": 7,
        "source": "acme/skills",
        "isOfficial": False,
    },
    {
        "id": "acme/skills/mismatch",
        "skillId": "mismatch",
        "name": "Mismatch",
        "installs": 1,
        "source": "acme/skills",
        "isOfficial": False,
    },
]

TRENDING_SKILLS = [
    {
        "skillId": "pdf-tools",
        "name": "PDF Tools",
        "installs": 12500,
        "source": "acme/skills",
        "isOfficial": True,
    },
    {
        "skillId": "web-audit",
        "name": "Web Audit",
        "installs": 340,
        "source": "acme/skills",
        "isOfficial": False,
    },
    # Duplicate id: parseTrending must keep the first occurrence only.
    {
        "skillId": "pdf-tools",
        "name": "PDF Tools",
        "installs": 12000,
        "source": "acme/skills",
        "isOfficial": True,
    },
]

ROOT_SKILL = """---
name: root-skill
description: Repository-root canned skill
---

# Root Skill

Returned by the root SKILL.md conventional path.
"""

PDF_TOOLS = """---
name: pdf-tools
description: Work with PDF files
---

# PDF Tools

Canned body from scripts/linux/mock-registry.py.
"""

TREE_ONLY = """---
name: tree-only
description: Only discoverable through the GitHub tree API
---

# Tree Only

This file lives outside every conventional path.
"""

MISMATCH = """---
name: wrong-name
description: Frontmatter deliberately does not match the requested skill
---

# Wrong Name
"""

RAW_FILES = {
    "acme/skills/main/SKILL.md": ROOT_SKILL,
    "acme/skills/main/skills/pdf-tools/SKILL.md": PDF_TOOLS,
    "acme/skills/main/skills/deep/tree-only/SKILL.md": TREE_ONLY,
    "acme/skills/main/archive/mismatch/SKILL.md": MISMATCH,
}

REPOS = {
    "acme/skills": {"default_branch": "main"},
    "rate-limited/repo": {"default_branch": "main"},
}

TREES = {
    ("acme/skills", "main"): [
        {"path": "README.md", "type": "blob"},
        {"path": "SKILL.md", "type": "blob"},
        {"path": "skills/pdf-tools/SKILL.md", "type": "blob"},
        {"path": "skills/deep/tree-only/SKILL.md", "type": "blob"},
        {"path": "archive/mismatch/SKILL.md", "type": "blob"},
        {"path": "skills/pdf-tools", "type": "tree"},
    ],
    ("rate-limited/repo", "main"): [],
}

REQUESTS: list[dict[str, str]] = []
REQUESTS_LOCK = threading.Lock()


def trending_html() -> str:
    """Mirror the Next.js RSC payload: JSON objects inside a JS string, quotes escaped."""
    payload = ",".join(
        json.dumps(skill, separators=(",", ":")).replace('"', '\\"')
        for skill in TRENDING_SKILLS
    )
    return (
        "<!doctype html><html><body>"
        '<script>self.__next_f.push([1,"'
        + payload
        + '"])</script></body></html>'
    )


class Handler(BaseHTTPRequestHandler):
    server_version = "ChopsMockRegistry/1.0"

    # -- plumbing ---------------------------------------------------------------

    def log_message(self, fmt: str, *args) -> None:
        sys.stdout.write("mock-registry %s %s\n" % (self.command, self.path))
        sys.stdout.flush()

    def send_body(self, status: int, body: bytes, content_type: str) -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def send_json(self, status: int, value) -> None:
        self.send_body(status, json.dumps(value).encode("utf-8"), "application/json")

    def record(self, parsed) -> None:
        entry = {
            "method": self.command,
            "path": parsed.path,
            "query": parsed.query,
            "userAgent": self.headers.get("User-Agent", ""),
        }
        with REQUESTS_LOCK:
            REQUESTS.append(entry)

    # -- routing ----------------------------------------------------------------

    def do_GET(self) -> None:  # noqa: N802 (BaseHTTPRequestHandler API)
        parsed = urlparse(self.path)
        path = parsed.path
        self.record(parsed)

        if path == "/__health":
            self.send_json(
                200,
                {
                    "service": "chops-mock-registry",
                    "status": "ok",
                    "port": self.server.server_address[1],
                },
            )
            return

        if path == "/__requests":
            with REQUESTS_LOCK:
                self.send_json(200, {"requests": list(REQUESTS)})
            return

        if path == "/api/search":
            self.handle_search(parsed)
            return

        if path == "/trending":
            self.send_body(200, trending_html().encode("utf-8"), "text/html; charset=utf-8")
            return

        parts = [part for part in path.strip("/").split("/") if part]
        if len(parts) >= 3 and parts[0] == "repos":
            self.handle_github_api(parts)
            return

        self.handle_raw(path)
        return

    def do_HEAD(self) -> None:  # noqa: N802
        self.do_GET()

    def handle_search(self, parsed) -> None:
        query = parse_qs(parsed.query).get("q", [""])[0]
        try:
            limit = int(parse_qs(parsed.query).get("limit", ["30"])[0])
        except ValueError:
            limit = 30

        needle = query.lower()
        matches = [
            skill
            for skill in SEARCH_SKILLS
            if needle in skill["name"].lower()
            or needle in skill["skillId"].lower()
            or needle in skill["source"].lower()
        ][:limit]
        self.send_json(200, {"skills": matches, "count": len(matches)})

    def handle_github_api(self, parts: list[str]) -> None:
        owner, repo = parts[1], parts[2]
        source = f"{owner}/{repo}"

        if source == "rate-limited/repo":
            self.send_json(403, {"message": "API rate limit exceeded"})
            return

        if len(parts) == 3:
            payload = REPOS.get(source)
            if payload is None:
                self.send_json(404, {"message": "Not Found", "source": source})
                return
            self.send_json(200, payload)
            return

        if len(parts) >= 6 and parts[3] == "git" and parts[4] == "trees":
            branch = "/".join(parts[5:])
            tree = TREES.get((source, branch))
            if tree is None:
                self.send_json(404, {"message": "Not Found", "source": source, "branch": branch})
                return
            self.send_json(200, {"sha": "mock-sha", "tree": tree, "truncated": False})
            return

        self.send_json(404, {"message": "Not Found", "path": "/".join(parts)})

    def handle_raw(self, path: str) -> None:
        key = path.strip("/")
        body = RAW_FILES.get(key)
        if body is None:
            self.send_json(404, {"message": "Not Found", "path": key})
            return
        self.send_body(200, body.encode("utf-8"), "text/plain; charset=utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=DEFAULT_PORT)
    args = parser.parse_args()

    server = ThreadingHTTPServer((HOST, args.port), Handler)
    server.daemon_threads = True

    def shutdown(_signum, _frame) -> None:
        threading.Thread(target=server.shutdown, daemon=True).start()

    signal.signal(signal.SIGTERM, shutdown)
    signal.signal(signal.SIGINT, shutdown)

    print(
        f"mock-registry listening on http://{HOST}:{args.port} "
        f"(skills.sh + raw.githubusercontent.com + api.github.com)",
        flush=True,
    )
    try:
        server.serve_forever(poll_interval=0.05)
    finally:
        server.server_close()
        print("mock-registry stopped", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
