#!/bin/bash
# ============================================================
# Peezy Autopilot v2 — Build 2: Typewriter + New Screens + Main Interface
# 7 phases
# ============================================================

set -e

PHASES=7
SPEC_FILE="BUILD2_ASSESSMENT_OVERHAUL_SPEC.md"
LOG_DIR="build_logs_assessment_overhaul_2"
BUILD_NAME="Assessment Overhaul Build 2"
START_PHASE=${1:-1}
DEFAULT_TURNS=25

# Phase 1 (typewriter rebuild) needs full attention
PHASE_1_TURNS=30
# Phase 4 (3 detail redesigns) is heavy
PHASE_4_TURNS=30
# Phase 7 (swipe + animation) is complex
PHASE_7_TURNS=30

# Unset CLAUDECODE for nested session compatibility
unset CLAUDECODE 2>/dev/null || true

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo ""
echo -e "${BLUE}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Peezy Autopilot v2: ${BUILD_NAME}${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════╝${NC}"
echo ""

# ── PRE-FLIGHT CHECKS ──────────────────────────────────────

echo -e "${YELLOW}Running pre-flight checks...${NC}"

if [ ! -f "Peezy 4.0.xcodeproj/project.pbxproj" ]; then
  echo -e "${RED}❌ Wrong directory.${NC}"
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
  echo -e "${RED}❌ jq not found.${NC}"
  exit 1
fi
echo -e "  ${GREEN}✓${NC} jq available"

# Seed task catalog before build
echo -e "  ${YELLOW}⏳${NC} Seeding task catalog..."
cd functions && node seedTaskCatalog.js 2>&1 | tail -1 && cd ..
echo -e "  ${GREEN}✓${NC} Task catalog seeded"

echo -e "  ${YELLOW}⏳${NC} Verifying build..."
BUILD_CHECK=$(xcodebuild -project "Peezy 4.0.xcodeproj" -scheme "Peezy 4.0" -sdk iphonesimulator -destination "platform=iOS Simulator,name=iPhone 17 Pro" build 2>&1 | tail -3)
if echo "$BUILD_CHECK" | grep -q "BUILD SUCCEEDED"; then
  echo -e "  ${GREEN}✓${NC} Build succeeds"
else
  echo -e "${RED}❌ Build broken before starting.${NC}"
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
  echo -e "${YELLOW}  Phase $i of $PHASES${NC}"
  echo -e "${YELLOW}════════════════════════════════════════════════════════${NC}"
  echo ""

  RESULT_FILE="$LOG_DIR/phase_${i}_result.json"
  MAX_TURNS=$(eval echo \${PHASE_${i}_TURNS:-$DEFAULT_TURNS})

  # Git safety net
  git add -A 2>/dev/null
  git commit -m "autopilot: pre-phase-$i snapshot (build2)" --allow-empty 2>/dev/null || true
  echo -e "  ${GREEN}✓${NC} Git snapshot saved (pre-phase $i)"

  PROMPT="You are modifying the Peezy iOS app.

Read the file $SPEC_FILE in the project root.

FIRST: If this is Phase 1, run the Pre-Flight Check section. If any check fails, STOP.

Execute Phase $i COMPLETELY. Follow every instruction exactly:
- READ every file mentioned in 'READ FIRST' BEFORE modifying anything
- Use @Observable, NOT ObservableObject/@Published for NEW classes. Do NOT convert existing classes.
- Use async/await for all async operations
- Follow PeezyTheme conventions for all UI
- DO NOT modify files not listed in this phase
- DO NOT refactor or restructure unrelated code
- Run the verification xcodebuild command after completing the phase
- If build fails, fix the error before marking complete

After verification passes, add '<!-- Phase $i: COMPLETE -->' at the end of Phase $i in $SPEC_FILE"

  echo -e "${BLUE}  Sending to Claude Code (max $MAX_TURNS turns)...${NC}"

  claude -p "$PROMPT" \
    --permission-mode acceptEdits \
    --max-turns $MAX_TURNS \
    --output-format json > "$RESULT_FILE" 2>"$LOG_DIR/phase_${i}_stderr.log"

  IS_ERROR=$(jq -r '.is_error // false' "$RESULT_FILE" 2>/dev/null || echo "true")

  if [ "$IS_ERROR" = "true" ]; then
    echo -e "${RED}  ❌ Phase $i FAILED — rolling back${NC}"
    git reset --hard HEAD 2>/dev/null
    echo -e "${YELLOW}  ↩ Rolled back to pre-phase $i${NC}"
    FAIL_MSG=$(jq -r '.result // "unknown"' "$RESULT_FILE" 2>/dev/null | head -5)
    echo -e "     Error: $FAIL_MSG"
    echo -e "     Log: $RESULT_FILE"
    echo ""
    echo -e "${YELLOW}  To resume: ./${0##*/} $i${NC}"
    exit 1
  fi

  git add -A 2>/dev/null
  git commit -m "autopilot: phase-$i complete (build2)" --allow-empty 2>/dev/null || true

  PHASE_COST=$(jq -r '.total_cost_usd // "?"' "$RESULT_FILE" 2>/dev/null)
  NUM_TURNS=$(jq -r '.num_turns // "?"' "$RESULT_FILE" 2>/dev/null)

  if [ "$PHASE_COST" != "?" ] && [ "$PHASE_COST" != "null" ]; then
    TOTAL_COST=$(echo "$TOTAL_COST + $PHASE_COST" | bc 2>/dev/null || echo "$TOTAL_COST")
  fi
  if [ "$NUM_TURNS" != "?" ] && [ "$NUM_TURNS" != "null" ]; then
    TOTAL_TURNS=$((TOTAL_TURNS + NUM_TURNS))
  fi

  echo -e "${GREEN}  ✅ Phase $i complete! (Cost: \$${PHASE_COST} | Turns: ${NUM_TURNS})${NC}"
done

END_TIME=$(date +%s)
ELAPSED=$(( (END_TIME - START_TIME) / 60 ))

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   🎉 BUILD 2 COMPLETE                                ║${NC}"
echo -e "${GREEN}║   Cost: \$${TOTAL_COST} | Turns: ${TOTAL_TURNS} | Time: ${ELAPSED}m${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
echo ""
echo "Post-build verification:"
echo "  1. Build to device"
echo "  2. Typewriter text: ZERO shake, ZERO alignment shift, ZERO word jumping"
echo "  3. Intro page: icon sparkles, then text typewriters, then button appears"
echo "  4. Services explainer page appears before movers question"
echo "  5. Address change explainer page appears before financial question"
echo "  6. Financial/healthcare/fitness details: one entry at a time"
echo "  7. Tasks generate (check card stack after completing assessment)"
echo "  8. No promo page flash during transition to main app"
echo "  9. Welcome card pages swipe left/right, page 3 has button"
echo "  10. Task cards fly off screen when completed/snoozed"
echo ""
echo "Push to GitHub and sync project knowledge after verification."
