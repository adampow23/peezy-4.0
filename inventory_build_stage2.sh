#!/bin/bash
# ============================================================
# Peezy Inventory Pipeline — Stage 2 Build Script
# Wire inventory into live Peezy app
#
# LESSONS FROM STAGE 1 BUILT IN:
# - Verifies correct directory before starting
# - Pre-flight checks confirm Stage 1 files exist
# - Verifies build passes BEFORE making any changes
# - Higher max-turns for theming phases (more code to write)
# - Explicit CLAUDECODE unset for nested session compatibility
#
# Usage:
#   chmod +x inventory_build_stage2.sh
#   ./inventory_build_stage2.sh          # Run all phases
#   ./inventory_build_stage2.sh 3        # Resume from phase 3
# ============================================================

set -e

PHASES=8
START_PHASE=${1:-1}
SPEC_FILE="INVENTORY_STAGE2_SPEC.md"
LOG_DIR="build_logs_stage2"

# Unset CLAUDECODE to allow nested sessions (lesson from Stage 1)
unset CLAUDECODE 2>/dev/null || true

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo ""
echo -e "${BLUE}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Peezy Inventory — Stage 2: Wire Into App          ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════╝${NC}"
echo ""

# ── PRE-FLIGHT CHECKS ──────────────────────────────────────

echo -e "${YELLOW}Running pre-flight checks...${NC}"

# Check 1: Correct directory
if [ ! -f "Peezy 4.0.xcodeproj/project.pbxproj" ]; then
  echo -e "${RED}❌ Wrong directory. Must run from Peezy project root.${NC}"
  echo "   Expected to find: Peezy 4.0.xcodeproj"
  echo "   Current directory: $(pwd)"
  echo ""
  echo "   Try: cd ~/Desktop/Peezy\\ 4.0/ && ./inventory_build_stage2.sh"
  exit 1
fi
echo -e "  ${GREEN}✓${NC} Correct directory"

# Check 2: Spec file exists
if [ ! -f "$SPEC_FILE" ]; then
  echo -e "${RED}❌ $SPEC_FILE not found in project root.${NC}"
  exit 1
fi
echo -e "  ${GREEN}✓${NC} Stage 2 spec found"

# Check 3: Stage 1 files exist
STAGE1_FILES=(
  "Peezy 4.0/Inventory/Models/InventoryModels.swift"
  "Peezy 4.0/Inventory/Services/FrameExtractionService.swift"
  "Peezy 4.0/Inventory/Services/InventoryStorageService.swift"
  "Peezy 4.0/Inventory/Services/InventoryAPIClient.swift"
  "Peezy 4.0/Inventory/Views/RoomCaptureView.swift"
  "Peezy 4.0/Inventory/Views/InventoryReviewView.swift"
  "functions/processInventory.js"
)

for f in "${STAGE1_FILES[@]}"; do
  if [ ! -f "$f" ]; then
    echo -e "${RED}❌ Stage 1 file missing: $f${NC}"
    echo "   Run Stage 1 first before proceeding to Stage 2."
    exit 1
  fi
done
echo -e "  ${GREEN}✓${NC} All Stage 1 files present"

# Check 4: Claude Code CLI available
if ! command -v claude &> /dev/null; then
  echo -e "${RED}❌ Claude Code CLI not found.${NC}"
  exit 1
fi
echo -e "  ${GREEN}✓${NC} Claude Code CLI available"

# Check 5: jq available
if ! command -v jq &> /dev/null; then
  echo -e "${RED}❌ jq not found. Install with: brew install jq${NC}"
  exit 1
fi
echo -e "  ${GREEN}✓${NC} jq available"

# Check 6: Current build passes
echo -e "  ${YELLOW}⏳${NC} Verifying current build compiles..."
BUILD_OUTPUT=$(xcodebuild -project "Peezy 4.0.xcodeproj" -scheme "Peezy 4.0" -sdk iphonesimulator -destination "platform=iOS Simulator,name=iPhone 17 Pro" build 2>&1 | tail -3)
if echo "$BUILD_OUTPUT" | grep -q "BUILD SUCCEEDED"; then
  echo -e "  ${GREEN}✓${NC} Current build succeeds"
else
  echo -e "${RED}❌ Current build is broken. Fix before running Stage 2.${NC}"
  echo "$BUILD_OUTPUT"
  exit 1
fi

echo ""
echo -e "${GREEN}All pre-flight checks passed!${NC}"
echo ""

# ── CREATE LOG DIRECTORY ──────────────────────────────────

mkdir -p "$LOG_DIR"

# ── PHASE EXECUTION ───────────────────────────────────────

TOTAL_COST=0

for i in $(seq $START_PHASE $PHASES); do
  echo ""
  echo -e "${YELLOW}════════════════════════════════════════════════════════${NC}"
  echo -e "${YELLOW}  🚀 Phase $i of $PHASES${NC}"
  echo -e "${YELLOW}════════════════════════════════════════════════════════${NC}"
  echo ""

  RESULT_FILE="$LOG_DIR/phase_${i}_result.json"

  # Theming phases need more turns (more code to write)
  MAX_TURNS=25
  if [ "$i" -le 2 ]; then
    MAX_TURNS=30  # Theming phases are code-heavy
  fi
  if [ "$i" -eq 5 ]; then
    MAX_TURNS=30  # Task catalog + multiple file modifications
  fi

  PROMPT="You are modifying the Peezy iOS app to wire in the inventory scanning feature.

Read the file INVENTORY_STAGE2_SPEC.md in the project root.

FIRST: If this is Phase 1, run the Pre-Flight Check section from the spec. If any check fails, STOP.

Then execute Phase $i COMPLETELY. Follow every instruction exactly:
- READ every file mentioned in the phase BEFORE modifying it
- Follow all Peezy theming conventions (PeezyTheme.Colors, PeezyTheme.Typography, PeezyTheme.Animation, PeezyTheme.Layout)
- Use @Observable, NOT ObservableObject/@Published
- Use async/await for all async operations
- DO NOT modify any files not listed in this phase
- DO NOT modify camera/AVCaptureSession code (it works — Stage 1 proved it)
- Run the verification xcodebuild command after completing the phase
- If build fails, fix the error before marking complete

After verification passes, add '<!-- Phase $i: COMPLETE -->' at the end of Phase $i in INVENTORY_STAGE2_SPEC.md"

  echo -e "${BLUE}  Sending to Claude Code (max $MAX_TURNS turns)...${NC}"

  claude -p "$PROMPT" \
    --permission-mode acceptEdits \
    --max-turns $MAX_TURNS \
    --output-format json > "$RESULT_FILE" 2>"$LOG_DIR/phase_${i}_stderr.log"

  # Check for errors
  IS_ERROR=$(jq -r '.is_error // false' "$RESULT_FILE" 2>/dev/null || echo "true")

  if [ "$IS_ERROR" = "true" ]; then
    echo -e "${RED}  ❌ Phase $i FAILED${NC}"
    echo -e "     Result: $RESULT_FILE"
    echo -e "     Stderr: $LOG_DIR/phase_${i}_stderr.log"
    echo ""
    FAIL_MSG=$(jq -r '.result // "unknown error"' "$RESULT_FILE" 2>/dev/null | head -5)
    echo -e "     Error: $FAIL_MSG"
    echo ""
    echo -e "${YELLOW}  To resume: ./inventory_build_stage2.sh $i${NC}"
    exit 1
  fi

  PHASE_COST=$(jq -r '.total_cost_usd // "?"' "$RESULT_FILE" 2>/dev/null)
  NUM_TURNS=$(jq -r '.num_turns // "?"' "$RESULT_FILE" 2>/dev/null)

  if [ "$PHASE_COST" != "?" ] && [ "$PHASE_COST" != "null" ]; then
    TOTAL_COST=$(echo "$TOTAL_COST + $PHASE_COST" | bc 2>/dev/null || echo "$TOTAL_COST")
  fi

  echo -e "${GREEN}  ✅ Phase $i complete! (Cost: \$${PHASE_COST} | Turns: ${NUM_TURNS})${NC}"

done

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   🎉 STAGE 2 COMPLETE!                              ║${NC}"
echo -e "${GREEN}║   Total cost: \$${TOTAL_COST}                        ${NC}"
echo -e "${GREEN}║                                                      ║${NC}"
echo -e "${GREEN}║   Next steps:                                        ║${NC}"
echo -e "${GREEN}║   1. Add new Swift files to Xcode target             ║${NC}"
echo -e "${GREEN}║   2. Re-seed task catalog:                           ║${NC}"
echo -e "${GREEN}║      cd functions && node seedTaskCatalog.js         ║${NC}"
echo -e "${GREEN}║   3. Build to device and test full flow:             ║${NC}"
echo -e "${GREEN}║      Settings → Scan Room Inventory                  ║${NC}"
echo -e "${GREEN}║      Card stack → "Create moving inventory" task     ║${NC}"
echo -e "${GREEN}║   4. Test multi-room: scan 2-3 rooms, review all     ║${NC}"
echo -e "${GREEN}║   5. Verify moving estimate numbers are reasonable   ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
echo ""
echo "Build logs: $LOG_DIR/"
