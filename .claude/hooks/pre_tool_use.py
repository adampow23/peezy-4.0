#!/usr/bin/env python3
"""PreToolUse hook — spec-01 Phase 0a.

Denies Write/Edit on compliance-critical/frozen files and on any repo path
not listed in PHASE_MANIFEST at the repo root.
Exit 0 = allow. Exit 2 = deny (stderr is shown to the model).
"""
import fnmatch
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

# Frozen/compliance regions per peezy-conventions-v2.md. fnmatch: '*' spans '/'.
PROTECTED = [
    "*project.pbxproj",
    "*GoogleService-Info.plist",
    "functions/.env",
    "*Configuration.storekit",
    "*Inventory/Camera/*",
    "*SubscriptionManager.swift",
    "*PaywallGateView.swift",  # Spec 04 lifts this for its one declared edit
]

WRITE_TOOLS = ("Write", "Edit", "MultiEdit", "NotebookEdit")


def deny(reason):
    print(reason, file=sys.stderr)
    sys.exit(2)


def main():
    try:
        payload = json.load(sys.stdin)
    except Exception:
        sys.exit(0)  # malformed input must not block unrelated tools
    if payload.get("tool_name") not in WRITE_TOOLS:
        sys.exit(0)
    tool_input = payload.get("tool_input") or {}
    raw = tool_input.get("file_path") or tool_input.get("notebook_path") or ""
    if not raw:
        sys.exit(0)
    path = Path(raw)
    if not path.is_absolute():
        path = Path(payload.get("cwd", str(ROOT))) / path
    try:
        rel = path.resolve().relative_to(ROOT)
    except ValueError:
        sys.exit(0)  # outside the repo (scratchpad, memory) — not guarded
    rel_s = rel.as_posix()

    for pat in PROTECTED:
        if fnmatch.fnmatch(rel_s, pat):
            deny(
                f"BLOCKED: {rel_s} is a protected file (COMPLIANCE/frozen region, "
                "spec-01 Phase 0a). Do not modify it."
            )

    if rel_s == "PHASE_MANIFEST":
        sys.exit(0)

    manifest = ROOT / "PHASE_MANIFEST"
    if not manifest.exists():
        deny(
            "BLOCKED: no PHASE_MANIFEST at repo root. Write PHASE_MANIFEST "
            "(this phase's intended paths, one per line) before editing repo files."
        )
    patterns = [
        line.strip()
        for line in manifest.read_text().splitlines()
        if line.strip() and not line.strip().startswith("#")
    ]
    for pat in patterns:
        if rel_s == pat or fnmatch.fnmatch(rel_s, pat):
            sys.exit(0)
    deny(
        f"BLOCKED: {rel_s} is not in PHASE_MANIFEST. If it is genuinely in this "
        "phase's scope, add it to PHASE_MANIFEST first; otherwise STOP and report "
        "per spec-01."
    )


main()
