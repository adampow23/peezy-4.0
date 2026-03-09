#!/bin/bash
# ============================================================
# Peezy Autopilot v2 — Build 1: Assessment Overhaul
# 7 phases: copy changes, layout fixes, new question, cleanup
# ============================================================

set -e

PHASES=7
SPEC_FILE="BUILD1_ASSESSMENT_OVERHAUL_SPEC.md"
LOG_DIR="build_logs_assessment_overhaul"
BUILD_NAME="Assessment Overhaul Build 1"
START_PHASE=${1:-1}
DEFAULT_TURNS=25

# Phase 1 needs more turns (enum + sequence + new file creation)
PHASE_1_TURNS=30
# Phase 2 needs more turns (15 copy changes in one method)
PHASE_2_TURNS=30
# Phase 5 needs more turns (multiple layout files)
PHASE_5_TURNS=30

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

# Initialize git if not already
if ! git rev-parse --git-dir > /dev/null 2>&1; then
  echo -e "  ${YELLOW}⏳${NC} Initializing git..."
  git init
  echo "Pods/\nDerivedData/\n.build/\nbuild_logs*/\n*.xcuserdata\nnode_modules/\n.env" > .gitignore
  git add -A
  git commit -m "autopilot: initial commit before build" || true
fi
echo -e "  ${GREEN}✓${NC} Git ready"

echo -e "  ${YELLOW}⏳${NC} Verifying build..."
BUILD_CHECK=$(xcodebuild -project "Peezy 4.0.xcodeproj" -scheme "Peezy 4.0" -sdk iphonesimulator -destination "platform=iOS Simulator,name=iPhone 17 Pro" build 2>&1 | tail -3)
if echo "$BUILD_CHECK" | grep -q "BUILD SUCCEEDED"; then
  echo -e "  ${GREEN}✓${NC} Build succeeds"
else
  echo -e "${RED}❌ Build broken before starting. Fix first.${NC}"
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
  
  # Get phase-specific turns
  MAX_TURNS=$(eval echo \${PHASE_${i}_TURNS:-$DEFAULT_TURNS})

  # ── GIT SAFETY NET ────────────────────────────────────
  git add -A 2>/dev/null
  git commit -m "autopilot: pre-phase-$i snapshot" --allow-empty 2>/dev/null || true
  echo -e "  ${GREEN}✓${NC} Git snapshot saved (pre-phase $i)"

  PROMPT="You are modifying the Peezy iOS app.

Read the file $SPEC_FILE in the project root.

FIRST: If this is Phase 1, run the Pre-Flight Check section. If any check fails, STOP.

Execute Phase $i COMPLETELY. Follow every instruction exactly:
- READ every file mentioned in 'READ FIRST' BEFORE modifying anything
- Use @Observable, NOT ObservableObject/@Published for NEW classes. But do NOT convert existing ObservableObject classes.
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

  # Check for errors
  IS_ERROR=$(jq -r '.is_error // false' "$RESULT_FILE" 2>/dev/null || echo "true")

  if [ "$IS_ERROR" = "true" ]; then
    echo -e "${RED}  ❌ Phase $i FAILED — rolling back changes${NC}"
    git reset --hard HEAD 2>/dev/null
    echo -e "${YELLOW}  ↩ Rolled back to pre-phase $i state${NC}"
    echo ""
    FAIL_MSG=$(jq -r '.result // "unknown"' "$RESULT_FILE" 2>/dev/null | head -5)
    echo -e "     Error: $FAIL_MSG"
    echo -e "     Full log: $RESULT_FILE"
    echo -e "     Stderr: $LOG_DIR/phase_${i}_stderr.log"
    echo ""
    echo -e "${YELLOW}  To resume: ./${0##*/} $i${NC}"
    exit 1
  fi

  # Phase succeeded — commit the changes
  git add -A 2>/dev/null
  git commit -m "autopilot: phase-$i complete ($SPEC_FILE)" --allow-empty 2>/dev/null || true

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
echo -e "${GREEN}║   🎉 BUILD 1 COMPLETE                                ║${NC}"
echo -e "${GREEN}║   Cost: \$${TOTAL_COST} | Turns: ${TOTAL_TURNS} | Time: ${ELAPSED}m${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
echo ""
echo "Post-build verification:"
echo "  1. Build to device"
echo "  2. Run through FULL assessment"
echo "  3. Verify all copy changes match the spec"
echo "  4. Verify sqft questions are GONE"
echo "  5. Verify anyKids question appears and branches correctly"
echo "  6. Verify promo code screen is GONE"
echo "  7. Verify spacing on text field pages (username, addresses)"
echo "  8. Verify date picker has breathing room"
echo "  9. Verify address icons are plain pencil"
echo "  10. Verify storage icons (sizes + pie charts)"
echo "  11. Verify tab bar has no titles and no white bar"
echo "  12. Verify welcome card body text is centered"
echo ""
echo "After verification, push to GitHub and sync project knowledge."
echo "Then bring bug list for Build 2 (typewriter rebuild + new screens)."
