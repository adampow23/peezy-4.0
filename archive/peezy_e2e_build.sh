#!/bin/bash
# ============================================================
# Peezy Autopilot — E2E Test Suite Build
# 9 phases: seed scripts → accessibility IDs → test files → run tests
#
# Usage:
#   chmod +x peezy_e2e_build.sh
#   ./peezy_e2e_build.sh          # run all phases
#   ./peezy_e2e_build.sh 4        # resume from phase 4
#
# Pre-requisites:
#   - Claude Code CLI authenticated (run `claude` then `/login`)
#   - jq installed (brew install jq)
#   - Run from ~/Desktop/Peezy 4.0/
#   - E2E_TEST_SPEC.md in project root
#   - functions/serviceAccountKey.json present
# ============================================================

set -e

PHASES=9
SPEC_FILE="E2E_TEST_SPEC.md"
LOG_DIR="build_logs_e2e_tests"
BUILD_NAME="E2E Test Suite"
START_PHASE=${1:-1}
DEFAULT_TURNS=30

# Phase 1 (Node.js scripts — straightforward creation)
PHASE_1_TURNS=20
# Phase 2 (accessibility IDs — touches many production files, needs care)
PHASE_2_TURNS=40
# Phase 3 (base class + tab tests — foundational)
PHASE_3_TURNS=25
# Phase 4 (welcome + greeting + task card tests — medium)
PHASE_4_TURNS=30
# Phase 5 (task flow tests — complex interactions)
PHASE_5_TURNS=30
# Phase 6 (timeline + chat tests — medium)
PHASE_6_TURNS=30
# Phase 7 (settings + paywall tests — lots of buttons)
PHASE_7_TURNS=35
# Phase 8 (auth + full journey tests — special launch config)
PHASE_8_TURNS=30
# Phase 9 (run tests — mostly bash, minimal Claude)
PHASE_9_TURNS=15

# LE-002: Unset CLAUDECODE for nested session compatibility
unset CLAUDECODE 2>/dev/null || true

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo ""
echo -e "${BLUE}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Peezy Autopilot: ${BUILD_NAME}                       ║${NC}"
echo -e "${BLUE}║   Phases: ${START_PHASE} through ${PHASES}                                       ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""

# ── PRE-FLIGHT CHECKS ──────────────────────────────────────

echo -e "${YELLOW}Running pre-flight checks...${NC}"

if [ ! -f "Peezy 4.0.xcodeproj/project.pbxproj" ]; then
  echo -e "${RED}❌ Wrong directory. Run from ~/Desktop/Peezy 4.0/${NC}"
  exit 1
fi
echo -e "  ${GREEN}✓${NC} Correct directory"

if [ ! -f "$SPEC_FILE" ]; then
  echo -e "${RED}❌ $SPEC_FILE not found in project root.${NC}"
  echo "  Copy it here: cp Documents/$SPEC_FILE ./"
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
  echo -e "${RED}❌ jq not found. Install with: brew install jq${NC}"
  exit 1
fi
echo -e "  ${GREEN}✓${NC} jq available"

if [ ! -f "functions/serviceAccountKey.json" ]; then
  echo -e "${RED}❌ functions/serviceAccountKey.json not found — needed for test user seeding.${NC}"
  exit 1
fi
echo -e "  ${GREEN}✓${NC} Firebase service account key present"

# Seed task catalog
echo -e "  ${YELLOW}⏳${NC} Seeding task catalog..."
cd functions && node seedTaskCatalog.js 2>&1 | tail -1 && cd ..
echo -e "  ${GREEN}✓${NC} Task catalog seeded"

# Verify build
echo -e "  ${YELLOW}⏳${NC} Verifying build compiles..."
BUILD_CHECK=$(xcodebuild -project "Peezy 4.0.xcodeproj" -scheme "Peezy 4.0" \
  -sdk iphonesimulator -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  build 2>&1 | tail -3)
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
  MAX_TURNS=$(eval echo \${PHASE_${i}_TURNS:-$DEFAULT_TURNS})

  # ── GIT SAFETY NET ────────────────────────────────────
  git add -A 2>/dev/null
  git commit -m "e2e-tests: pre-phase-$i snapshot" --allow-empty 2>/dev/null || true
  echo -e "  ${GREEN}✓${NC} Git snapshot saved (pre-phase $i)"

  # ── SPECIAL HANDLING: Phase 1 seeds test data after creating scripts ──
  SEED_STEP=""
  if [ "$i" = "1" ]; then
    SEED_STEP="

AFTER creating the Node.js files, run them:
  cd functions && node testProfile/seedTestUser.js && cd ..
Report the output (how many tasks generated, test user UID)."
  fi

  # ── SPECIAL HANDLING: Phase 9 runs the test suite ──
  RUN_TESTS_STEP=""
  if [ "$i" = "9" ]; then
    RUN_TESTS_STEP="

Run the full test suite:
  xcodebuild test -project 'Peezy 4.0.xcodeproj' -scheme 'Peezy 4.0' \
    -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
    2>&1 | grep -E '(Test Case|Tests|Passed|Failed|error:)'

Report: total tests, passed, failed, and the names of any failing tests.
If tests fail, take a screenshot with XcodeBuildMCP and report what you see."
  fi

  PROMPT="You are building the Peezy E2E test suite.

FIRST: Read CLAUDE.md in the project root.
THEN: Read $SPEC_FILE in the project root.

Execute Phase $i COMPLETELY. Follow every instruction exactly:

- READ every file listed in 'READ FIRST' BEFORE modifying anything
- For production files: ONLY add .accessibilityIdentifier() modifiers — do NOT change layout, styling, or behavior
- For test files: create them in 'Peezy 4.0UITests/'
- DO NOT modify .pbxproj files
- DO NOT modify files not listed in this phase
- DO NOT refactor or restructure unrelated code
- DO NOT add print() statements to production code
- Run xcodebuild build after every set of changes to catch errors immediately
- If build fails, fix the error before continuing
- After ALL changes, diff modified files: git diff -- <file> to verify only intended changes${SEED_STEP}${RUN_TESTS_STEP}

After verification passes, report:
  PHASE $i RESULT: [PASS/FAIL]
  Files created: [list]
  Files modified: [list]
  Build: [SUCCEEDED/FAILED]"

  echo -e "${BLUE}  Sending to Claude Code (max $MAX_TURNS turns)...${NC}"

  claude -p "$PROMPT" \
    --permission-mode acceptEdits \
    --max-turns $MAX_TURNS \
    --output-format json > "$RESULT_FILE" 2>"$LOG_DIR/phase_${i}_stderr.log"

  # Check for errors
  IS_ERROR=$(jq -r '.is_error // false' "$RESULT_FILE" 2>/dev/null || echo "true")

  if [ "$IS_ERROR" = "true" ]; then
    echo -e "${RED}  ❌ Phase $i FAILED — rolling back${NC}"
    git reset --hard HEAD 2>/dev/null
    echo -e "${YELLOW}  ↩ Rolled back to pre-phase $i${NC}"
    echo ""
    FAIL_MSG=$(jq -r '.result // "unknown"' "$RESULT_FILE" 2>/dev/null | head -5)
    echo -e "     Error: $FAIL_MSG"
    echo -e "     Log: $RESULT_FILE"
    echo -e "     Stderr: $LOG_DIR/phase_${i}_stderr.log"
    echo ""
    echo -e "${YELLOW}  To resume: ./${0##*/} $i${NC}"
    exit 1
  fi

  # Phase succeeded — commit
  git add -A 2>/dev/null
  git commit -m "e2e-tests: phase-$i complete" --allow-empty 2>/dev/null || true

  # Cost tracking
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
echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   🎉 E2E TEST SUITE BUILD COMPLETE                      ║${NC}"
echo -e "${GREEN}║   Cost: \$${TOTAL_COST} | Turns: ${TOTAL_TURNS} | Time: ${ELAPSED}m              ${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "Post-build:"
echo "  1. Review test results in $LOG_DIR/phase_9_result.json"
echo "  2. Open TestResults.xcresult in Xcode for screenshots"
echo "  3. Fix any failing tests and re-run phase 9"
echo "  4. When done: cd functions && node testProfile/teardownTestUser.js"
echo ""
