#!/bin/bash
# ============================================================
# Peezy Autopilot — Assessment & Home Screen Bug Fixes
# 6 bugs, 6 phases
# ============================================================

set -e

PHASES=6
SPEC_FILE="BUGFIX_ASSESSMENT_SPEC.md"
LOG_DIR="build_logs_bugfix_assessment"
BUILD_NAME="Assessment & Home Fixes"
START_PHASE=${1:-1}
DEFAULT_TURNS=25

# Phase 1 (task generation) needs more turns for diagnostic work
PHASE_1_TURNS=30

# Unset CLAUDECODE for nested session compatibility
unset CLAUDECODE 2>/dev/null || true

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo ""
echo -e "${BLUE}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Peezy Autopilot: ${BUILD_NAME}${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════╝${NC}"
echo ""

# ── PRE-FLIGHT CHECKS ──────────────────────────────────────

echo -e "${YELLOW}Running pre-flight checks...${NC}"

if [ ! -f "Peezy 4.0.xcodeproj/project.pbxproj" ]; then
  echo -e "${RED}❌ Wrong directory. Must run from Peezy project root.${NC}"
  echo "   Try: cd ~/Desktop/Peezy\\ 4.0/ && ./${0##*/}"
  exit 1
fi
echo -e "  ${GREEN}✓${NC} Correct directory"

if [ ! -f "$SPEC_FILE" ]; then
  echo -e "${RED}❌ $SPEC_FILE not found.${NC}"
  exit 1
fi
echo -e "  ${GREEN}✓${NC} Spec file found"

if [ ! -f "CLAUDE.md" ]; then
  echo -e "${RED}❌ CLAUDE.md not found.${NC}"
  exit 1
fi
echo -e "  ${GREEN}✓${NC} CLAUDE.md present"

if ! command -v claude &> /dev/null; then
  echo -e "${RED}❌ Claude Code CLI not found.${NC}"
  exit 1
fi
echo -e "  ${GREEN}✓${NC} Claude Code available"

if ! command -v jq &> /dev/null; then
  echo -e "${RED}❌ jq not found. brew install jq${NC}"
  exit 1
fi
echo -e "  ${GREEN}✓${NC} jq available"

echo -e "  ${YELLOW}⏳${NC} Verifying build..."
BUILD_CHECK=$(xcodebuild -project "Peezy 4.0.xcodeproj" -scheme "Peezy 4.0" -sdk iphonesimulator -destination "platform=iOS Simulator,name=iPhone 17 Pro" build 2>&1 | tail -3)
if echo "$BUILD_CHECK" | grep -q "BUILD SUCCEEDED"; then
  echo -e "  ${GREEN}✓${NC} Build succeeds"
else
  echo -e "${RED}❌ Build broken. Fix first.${NC}"
  echo "$BUILD_CHECK"
  exit 1
fi

echo ""
echo -e "${GREEN}Pre-flight passed!${NC}"
echo ""

# ── EXECUTE PHASES ─────────────────────────────────────────

mkdir -p "$LOG_DIR"
TOTAL_COST=0
TOTAL_TURNS=0
START_TIME=$(date +%s)

for i in $(seq $START_PHASE $PHASES); do
  echo ""
  echo -e "${YELLOW}════════════════════════════════════════════════════════${NC}"
  echo -e "${YELLOW}  🔧 Bug Fix $i of $PHASES${NC}"
  echo -e "${YELLOW}════════════════════════════════════════════════════════${NC}"
  echo ""

  RESULT_FILE="$LOG_DIR/phase_${i}_result.json"
  # Get phase-specific turns (only phase 1 has override)
  MAX_TURNS=$(eval echo \${PHASE_${i}_TURNS:-$DEFAULT_TURNS})

  PROMPT="You are fixing bugs in the Peezy iOS app.

Read the file $SPEC_FILE in the project root.

FIRST: If this is Phase 1, run the Pre-Flight Check section. If any check fails, STOP.

Execute Phase $i COMPLETELY. This is a BUG FIX — follow the diagnostic approach:
1. READ every file listed in 'READ FIRST'
2. DIAGNOSE the root cause by tracing data flow
3. FIX the specific issue described
4. VERIFY xcodebuild succeeds
5. Do NOT refactor or improve unrelated code
6. Do NOT modify files not listed in this phase

Use @Observable conventions BUT do NOT convert existing ObservableObject classes — work within existing patterns.

After verification passes, add '<!-- Phase $i: COMPLETE -->' at the end of Phase $i in $SPEC_FILE"

  echo -e "${BLUE}  Sending to Claude Code (max $MAX_TURNS turns)...${NC}"

  claude -p "$PROMPT" \
    --permission-mode acceptEdits \
    --max-turns $MAX_TURNS \
    --output-format json > "$RESULT_FILE" 2>"$LOG_DIR/phase_${i}_stderr.log"

  IS_ERROR=$(jq -r '.is_error // false' "$RESULT_FILE" 2>/dev/null || echo "true")

  if [ "$IS_ERROR" = "true" ]; then
    echo -e "${RED}  ❌ Phase $i FAILED${NC}"
    FAIL_MSG=$(jq -r '.result // "unknown"' "$RESULT_FILE" 2>/dev/null | head -5)
    echo -e "     Error: $FAIL_MSG"
    echo ""
    echo -e "${YELLOW}  To resume: ./${0##*/} $i${NC}"
    exit 1
  fi

  PHASE_COST=$(jq -r '.total_cost_usd // "?"' "$RESULT_FILE" 2>/dev/null)
  NUM_TURNS=$(jq -r '.num_turns // "?"' "$RESULT_FILE" 2>/dev/null)

  if [ "$PHASE_COST" != "?" ] && [ "$PHASE_COST" != "null" ]; then
    TOTAL_COST=$(echo "$TOTAL_COST + $PHASE_COST" | bc 2>/dev/null || echo "$TOTAL_COST")
  fi
  if [ "$NUM_TURNS" != "?" ] && [ "$NUM_TURNS" != "null" ]; then
    TOTAL_TURNS=$((TOTAL_TURNS + NUM_TURNS))
  fi

  echo -e "${GREEN}  ✅ Bug $i fixed! (Cost: \$${PHASE_COST} | Turns: ${NUM_TURNS})${NC}"
done

END_TIME=$(date +%s)
ELAPSED=$(( (END_TIME - START_TIME) / 60 ))

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   🎉 ALL 6 BUGS FIXED                               ║${NC}"
echo -e "${GREEN}║   Cost: \$${TOTAL_COST} | Turns: ${TOTAL_TURNS} | Time: ${ELAPSED}m${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
echo ""
echo "Post-fix steps:"
echo "  1. Build to device and test fresh assessment"
echo "  2. Verify tasks generate (check card stack + task list)"
echo "  3. Verify typewriter text is smooth"
echo "  4. Verify text field spacing on all text input pages"
echo "  5. Verify keyboard doesn't hide text fields"
echo "  6. Verify no white bar behind home screen tab bar"
echo "  7. Verify tab bar height is compact"
