#!/usr/bin/env python3
"""PostToolUse hook — spec-01 Phase 0a support.

Records a successful xcodebuild by touching .build_ok whenever a tool result
contains the xcodebuild success banner. The Stop hook compares this marker's
mtime against Swift file mtimes.
"""
import json
import sys
import time
from pathlib import Path

MARKER = Path(__file__).resolve().parent / ".build_ok"

try:
    payload = json.load(sys.stdin)
except Exception:
    sys.exit(0)

blob = json.dumps(payload.get("tool_response", ""), default=str)
if "BUILD SUCCEEDED" in blob:
    MARKER.write_text(str(time.time()))
sys.exit(0)
