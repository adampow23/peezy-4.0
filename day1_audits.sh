#!/bin/bash
# ============================================================
# Peezy Day 1 — Read-Only Audits (A: Scanner, B: Tasks/n8n,
#                                 C: Research, D: Copy)
# Hard rule: any change outside audit_reports/ = revert + fail
# ============================================================

set -e

SPEC_FILE="DAY1_AUDITS_SPEC.md"
LOG_DIR="build_logs_day1_audits"
START_AUDIT=${1:-A}
MAX_TURNS=30

unset CLAUDECODE 2>/dev/null || true

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

echo ""
echo -e "${BLUE}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Peezy Day 1: Read-Only Audits                      ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════╝${NC}"

# ── PRE-FLIGHT ─────────────────────────────────────────────
[ -f "Peezy 4.0.xcodeproj/project.pbxproj" ] || { echo -e "${RED}❌ Wrong directory.${NC}"; exit 1; }
[ -f "$SPEC_FILE" ] || { echo -e "${RED}❌ $SPEC_FILE not found.${NC}"; exit 1; }
[ -f "PEEZY_LAUNCH_PLAN_AUG2026.md" ] || { echo -e "${RED}❌ Launch plan not in project root (audits reference it).${NC}"; exit 1; }
command -v claude &> /dev/null || { echo -e "${RED}❌ Claude Code CLI not found.${NC}"; exit 1; }
command -v jq &> /dev/null || { echo -e "${RED}❌ jq not found.${NC}"; exit 1; }
git rev-parse --git-dir > /dev/null 2>&1 || { echo -e "${RED}❌ Not a git repo.${NC}"; exit 1; }

# Clean tree required so the read-only check is meaningful
if [ -n "$(git status --porcelain)" ]; then
  echo -e "${RED}❌ Working tree not clean. Commit or stash first — the${NC}"
  echo -e "${RED}   read-only enforcement depends on a clean baseline.${NC}"
  exit 1
fi
echo -e "  ${GREEN}✓${NC} Pre-flight passed (clean tree)"

mkdir -p "$LOG_DIR" audit_reports
git add -A && git commit -m "day1: pre-audit snapshot" --allow-empty >/dev/null

AUDIT_A_NAME="Scanner Pipeline End-to-End"
AUDIT_B_NAME="Task Catalog + n8n Touchpoints"
AUDIT_C_NAME="Research Remnants"
AUDIT_D_NAME="Copy Inventory"

STARTED=false
for X in A B C D; do
  [ "$X" = "$START_AUDIT" ] && STARTED=true
  [ "$STARTED" = true ] || continue

  NAME_VAR="AUDIT_${X}_NAME"
  NAME="${!NAME_VAR}"
  RESULT_FILE="$LOG_DIR/audit_${X}_result.json"

  echo ""
  echo -e "${YELLOW}════════════════════════════════════════════════════════${NC}"
  echo -e "${YELLOW}  Audit $X — $NAME${NC}"
  echo -e "${YELLOW}════════════════════════════════════════════════════════${NC}"

  PROMPT="You are auditing the Peezy iOS app. THIS IS A READ-ONLY AUDIT.

Read $SPEC_FILE in the project root. Also read PEEZY_LAUNCH_PLAN_AUG2026.md sections referenced by the audit.

Execute Audit $X ONLY, exactly as specified:
- You may write ONLY to audit_reports/AUDIT_${X}_REPORT.md. Touch nothing else.
- Do NOT fix, refactor, format, or 'improve' anything you read.
- Every claim needs file:line evidence. Freshness claims need git log evidence.
- Use the exact report format in the spec.
- Finish by running: git status --porcelain — and state its output at the top of your report."

  claude -p "$PROMPT" \
    --permission-mode acceptEdits \
    --max-turns $MAX_TURNS \
    --output-format json > "$RESULT_FILE" 2>"$LOG_DIR/audit_${X}_stderr.log"

  IS_ERROR=$(jq -r '.is_error // false' "$RESULT_FILE" 2>/dev/null || echo "true")

  # ── READ-ONLY ENFORCEMENT ──────────────────────────────
  VIOLATIONS=$(git status --porcelain | grep -v "^?? audit_reports/" | grep -v "^?? ${LOG_DIR}/" || true)
  if [ -n "$VIOLATIONS" ]; then
    echo -e "${RED}  ❌ READ-ONLY VIOLATION — audit modified source:${NC}"
    echo "$VIOLATIONS"
    git checkout -- . 2>/dev/null || true
    git clean -fd --exclude=audit_reports --exclude="$LOG_DIR" 2>/dev/null || true
    echo -e "${YELLOW}  ↩ Source reverted. Report preserved but treat it as suspect.${NC}"
    echo -e "${YELLOW}  Re-run: ./${0##*/} $X${NC}"
    exit 1
  fi

  if [ "$IS_ERROR" = "true" ]; then
    echo -e "${RED}  ❌ Audit $X failed.${NC}  Log: $RESULT_FILE"
    echo -e "${YELLOW}  Re-run: ./${0##*/} $X${NC}"
    exit 1
  fi

  if [ ! -s "audit_reports/AUDIT_${X}_REPORT.md" ]; then
    echo -e "${RED}  ❌ Audit $X produced no report.${NC}"
    echo -e "${YELLOW}  Re-run: ./${0##*/} $X${NC}"
    exit 1
  fi

  COST=$(jq -r '.total_cost_usd // "?"' "$RESULT_FILE" 2>/dev/null)
  echo -e "${GREEN}  ✅ Audit $X complete — audit_reports/AUDIT_${X}_REPORT.md (\$${COST})${NC}"
done

git add audit_reports/ && git commit -m "day1: audit reports A-D" >/dev/null

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   🎉 DAY 1 AUDITS COMPLETE — source untouched        ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
echo ""
echo "Read all four reports in audit_reports/, then bring them back"
echo "to Claude chat. Day 2-4 build specs get written FROM these"
echo "reports — fixes and audits never share a session."
