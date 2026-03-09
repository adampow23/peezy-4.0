#!/bin/bash
# ============================================================
# Peezy Inventory Pipeline — Stage 1 Build Script
# 
# Executes INVENTORY_SPEC.md phase-by-phase using Claude Code
# in headless mode. Each phase gets a fresh context window.
#
# Prerequisites:
#   - Claude Code CLI installed and authenticated
#   - jq installed (brew install jq)
#   - Run from the Peezy project root directory
#   - INVENTORY_SPEC.md in the project root
#
# Usage:
#   chmod +x inventory_build_stage1.sh
#   ./inventory_build_stage1.sh
#
# To resume from a specific phase:
#   ./inventory_build_stage1.sh 5
# ============================================================

set -e

PHASES=8
START_PHASE=${1:-1}  # Resume from specific phase if passed as argument
SPEC_FILE="INVENTORY_SPEC.md"
LOG_DIR="build_logs"
TOTAL_COST=0

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Ensure spec file exists
if [ ! -f "$SPEC_FILE" ]; then
  echo -e "${RED}❌ $SPEC_FILE not found in current directory.${NC}"
  echo "   Place INVENTORY_SPEC.md in your project root and try again."
  exit 1
fi

# Ensure jq is available
if ! command -v jq &> /dev/null; then
  echo -e "${RED}❌ jq not found. Install with: brew install jq${NC}"
  exit 1
fi

# Ensure claude CLI is available
if ! command -v claude &> /dev/null; then
  echo -e "${RED}❌ Claude Code CLI not found. Install from: https://docs.anthropic.com/en/docs/claude-code${NC}"
  exit 1
fi

# Create log directory
mkdir -p "$LOG_DIR"

echo ""
echo -e "${BLUE}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Peezy Inventory Pipeline — Stage 1 Build          ║${NC}"
echo -e "${BLUE}║   Phases: $START_PHASE through $PHASES                                  ║${NC}"
echo -e "${BLUE}║   Spec: $SPEC_FILE                            ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════╝${NC}"
echo ""

for i in $(seq $START_PHASE $PHASES); do
  echo ""
  echo -e "${YELLOW}════════════════════════════════════════════════════════${NC}"
  echo -e "${YELLOW}  🚀 Phase $i of $PHASES${NC}"
  echo -e "${YELLOW}════════════════════════════════════════════════════════${NC}"
  echo ""

  RESULT_FILE="$LOG_DIR/phase_${i}_result.json"
  
  # Build the prompt for this phase
  PROMPT="You are building the Peezy Inventory Video Pipeline feature.

Read the file INVENTORY_SPEC.md in the project root.

Execute Phase $i COMPLETELY. Follow every instruction in that phase exactly:
- Create the exact files specified with the exact structure described
- Follow all code patterns, method signatures, and error handling requirements
- Use the existing project conventions from CLAUDE.md (especially @Observable, async/await, PeezyTheme)
- Run the verification command specified at the end of the phase
- After verification passes, add a comment '<!-- Phase $i: COMPLETE -->' at the end of Phase $i's section in INVENTORY_SPEC.md

CRITICAL RULES:
- Do NOT modify any files not listed in this phase
- Do NOT skip error handling — every async call needs try/catch
- Do NOT use ObservableObject/@Published — use @Observable (Observation framework)
- Do NOT create any files outside the paths specified in the spec
- If the verification build fails, fix the error before marking complete
- Read peezyBrain.js to see how the Anthropic SDK key is initialized, and use the same pattern in processInventory.js"

  # Execute with Claude Code headless mode
  echo -e "${BLUE}  Sending to Claude Code...${NC}"
  
  claude -p "$PROMPT" \
    --permission-mode acceptEdits \
    --max-turns 25 \
    --output-format json > "$RESULT_FILE" 2>"$LOG_DIR/phase_${i}_stderr.log"
  
  # Check for errors
  IS_ERROR=$(jq -r '.is_error // false' "$RESULT_FILE" 2>/dev/null || echo "true")
  
  if [ "$IS_ERROR" = "true" ]; then
    echo -e "${RED}  ❌ Phase $i FAILED${NC}"
    echo -e "${RED}  Check: $RESULT_FILE${NC}"
    echo -e "${RED}  Stderr: $LOG_DIR/phase_${i}_stderr.log${NC}"
    echo ""
    echo -e "${YELLOW}  To resume from this phase: ./inventory_build_stage1.sh $i${NC}"
    exit 1
  fi
  
  # Extract cost info
  PHASE_COST=$(jq -r '.total_cost_usd // "unknown"' "$RESULT_FILE" 2>/dev/null || echo "unknown")
  NUM_TURNS=$(jq -r '.num_turns // "unknown"' "$RESULT_FILE" 2>/dev/null || echo "unknown")
  
  if [ "$PHASE_COST" != "unknown" ] && [ "$PHASE_COST" != "null" ]; then
    TOTAL_COST=$(echo "$TOTAL_COST + $PHASE_COST" | bc 2>/dev/null || echo "$TOTAL_COST")
  fi
  
  echo -e "${GREEN}  ✅ Phase $i complete!${NC}"
  echo -e "     Cost: \$${PHASE_COST} | Turns: ${NUM_TURNS}"
  echo ""

done

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   🎉 ALL $PHASES PHASES COMPLETE!                        ║${NC}"
echo -e "${GREEN}║   Total estimated cost: \$${TOTAL_COST}                  ${NC}"
echo -e "${GREEN}║                                                      ║${NC}"
echo -e "${GREEN}║   Next steps:                                        ║${NC}"
echo -e "${GREEN}║   1. Deploy: cd functions && firebase deploy          ║${NC}"
echo -e "${GREEN}║   2. Set API key: firebase functions:secrets:set ...  ║${NC}"
echo -e "${GREEN}║   3. Build to real device and test the pipeline       ║${NC}"
echo -e "${GREEN}║   4. Once validated, proceed to Stage 2 (wire in)    ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
echo ""
echo "Build logs saved to: $LOG_DIR/"
