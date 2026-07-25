#!/usr/bin/env python3
"""Stop hook — spec-01 Phase 0a + 0c.

Blocks ending the turn when:
1. Swift files changed (vs git) after the last recorded successful xcodebuild
   (marker .build_ok, maintained by post_tool_use.py), or
2. any NEW Swift file declares more View structs than it has
   .accessibilityIdentifier() calls (CLAUDE.md accessibility convention).
Exit 0 = allow stop. Exit 2 = block (stderr shown to the model).
"""
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MARKER = Path(__file__).resolve().parent / ".build_ok"

VIEW_STRUCT_RE = re.compile(
    r"^\s*(?:\w+\s+)*struct\s+\w+(?:<[^>]*>)?\s*:[^{\n]*\bView\b", re.M
)


def block(msg):
    print(msg, file=sys.stderr)
    sys.exit(2)


def main():
    try:
        payload = json.load(sys.stdin)
    except Exception:
        payload = {}
    if payload.get("stop_hook_active"):
        sys.exit(0)  # never loop the stop gate

    out = subprocess.run(
        ["git", "status", "--porcelain"], cwd=ROOT, capture_output=True, text=True
    ).stdout

    changed, new = [], []
    for line in out.splitlines():
        status, path = line[:2], line[3:].strip().strip('"')
        if " -> " in path:  # rename entry: take the new side
            path = path.split(" -> ", 1)[1].strip().strip('"')
        if not path.endswith(".swift") or "D" in status:
            continue
        p = ROOT / path
        if p.exists():
            changed.append(p)
            if status.strip() in ("??", "A", "AM"):
                new.append(p)

    if not changed:
        sys.exit(0)

    newest = max(p.stat().st_mtime for p in changed)
    if not MARKER.exists() or MARKER.stat().st_mtime < newest:
        block(
            "STOP BLOCKED: Swift files changed after the last successful xcodebuild "
            "(or no successful build recorded this session). Run xcodebuild to "
            "BUILD SUCCEEDED before ending the turn. (spec-01 stop gate)"
        )

    for p in new:
        src = p.read_text(errors="ignore")
        views = len(VIEW_STRUCT_RE.findall(src))
        ids = src.count(".accessibilityIdentifier(")
        if views and ids < views:
            block(
                f"STOP BLOCKED: {p.relative_to(ROOT)} declares {views} View "
                f"struct(s) but has {ids} .accessibilityIdentifier() call(s). "
                "Every new View needs at least one (accessibility convention)."
            )
    sys.exit(0)


main()
