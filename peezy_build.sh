#!/bin/bash
# ============================================================
# Peezy Autopilot — Spec 09 Catalog Restructure
# Phase 0 is complete; this runner executes Phases 1-6.
# Compatible with macOS Bash 3.2.
# ============================================================

set -e

PHASES=6
SPEC_FILE="PEEZY_SPEC_09_CATALOG_RESTRUCTURE.md"
AUDIT_FILE="SPEC06_AUDIT.md"
CATALOG_INPUT="peezy-catalog-v2.json"
LOG_DIR="logs/catalog_restructure"
BUILD_NAME="Spec 09 Catalog Restructure"
START_PHASE=${1:-1}
DEFAULT_TURNS=25
EXPECTED_CATALOG_SHA256="218a0ea7211b3142fc08d5d571780f62a23fd1ff415535669edfcf7dd93f9e90"

# LE-002: nested Claude Code sessions must not inherit CLAUDECODE.
unset CLAUDECODE 2>/dev/null || true

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

fail() {
  echo -e "${RED}ERROR: $1${NC}"
  exit 1
}

catalog_input_is_immutable() {
  ACTUAL_SHA256=$(shasum -a 256 "$CATALOG_INPUT" | awk '{print $1}')
  [ "$ACTUAL_SHA256" = "$EXPECTED_CATALOG_SHA256" ]
}

# Validate that taskCatalogData.json is the raw taskCatalog array from the
# companion input, byte for byte. This deliberately does not parse/stringify.
validate_catalog_transcription() {
  node - "$CATALOG_INPUT" "functions/taskCatalogData.json" <<'NODE'
const fs = require('fs');
const sourcePath = process.argv[2];
const targetPath = process.argv[3];
const source = fs.readFileSync(sourcePath, 'utf8');
const keyAt = source.indexOf('"taskCatalog"');
if (keyAt < 0) throw new Error('taskCatalog key missing from companion input');
const start = source.indexOf('[', keyAt);
if (start < 0) throw new Error('taskCatalog array start missing');

let depth = 0;
let inString = false;
let escaped = false;
let end = -1;
for (let i = start; i < source.length; i += 1) {
  const ch = source[i];
  if (inString) {
    if (escaped) escaped = false;
    else if (ch === '\\') escaped = true;
    else if (ch === '"') inString = false;
    continue;
  }
  if (ch === '"') inString = true;
  else if (ch === '[') depth += 1;
  else if (ch === ']') {
    depth -= 1;
    if (depth === 0) {
      end = i;
      break;
    }
  }
}
if (end < 0) throw new Error('taskCatalog array end missing');

const expected = Buffer.from(source.slice(start, end + 1), 'utf8');
const actual = fs.readFileSync(targetPath);
if (!expected.equals(actual)) {
  throw new Error(
    `catalog transcription is not byte-identical (expected ${expected.length} bytes, got ${actual.length})`
  );
}
NODE
}

# Remove only new, non-ignored files created during a failed phase. Every
# pre-existing file is committed by the phase checkpoint before work begins.
remove_failed_phase_untracked_files() {
  git ls-files --others --exclude-standard -z | while IFS= read -r -d '' NEW_PATH; do
    [ -n "$NEW_PATH" ] || continue
    git clean -fd -- "$NEW_PATH" >/dev/null 2>&1 || true
  done
}

rollback_phase() {
  FAILED_PHASE=$1
  CHECKPOINT=$2
  echo -e "${YELLOW}Rolling Phase $FAILED_PHASE back to $CHECKPOINT...${NC}"
  git reset --hard "$CHECKPOINT" >/dev/null
  remove_failed_phase_untracked_files
  echo -e "${YELLOW}Rollback complete. Logs were preserved in $LOG_DIR.${NC}"
}

run_xcodebuild() {
  PHASE_LABEL=$1
  BUILD_LOG="$LOG_DIR/${PHASE_LABEL}_xcodebuild.log"
  if xcodebuild -project "Peezy 4.0.xcodeproj" \
      -scheme "Peezy 4.0" \
      -destination 'generic/platform=iOS Simulator' \
      build -quiet >"$BUILD_LOG" 2>&1; then
    return 0
  fi
  tail -80 "$BUILD_LOG"
  return 1
}

echo ""
echo -e "${BLUE}Peezy Autopilot: ${BUILD_NAME}${NC}"
echo ""

# ── PRE-FLIGHT (exact project/spec inputs plus runner dependencies) ────────

echo -e "${YELLOW}Running Spec 09 pre-flight...${NC}"

[ -f "Peezy 4.0.xcodeproj/project.pbxproj" ] || fail "Peezy 4.0.xcodeproj not found; run from the project root."
[ -f "functions/taskCatalogData.json" ] || fail "functions/taskCatalogData.json not found."
[ -f "functions/seedTaskCatalog.js" ] || fail "functions/seedTaskCatalog.js not found."
[ -f "functions/flowDefinitionsData.json" ] || fail "functions/flowDefinitionsData.json not found."
[ -f "$SPEC_FILE" ] || fail "$SPEC_FILE not found."
[ -f "$AUDIT_FILE" ] || fail "$AUDIT_FILE not found."
[ -f "$CATALOG_INPUT" ] || fail "$CATALOG_INPUT not found."
[ -f "CLAUDE.md" ] || fail "CLAUDE.md not found."

command -v claude >/dev/null 2>&1 || fail "Claude Code CLI not found."
command -v jq >/dev/null 2>&1 || fail "jq not found."
command -v node >/dev/null 2>&1 || fail "Node.js not found."
command -v git >/dev/null 2>&1 || fail "git not found."
command -v firebase >/dev/null 2>&1 || fail "Firebase CLI not found."
git rev-parse --git-dir >/dev/null 2>&1 || fail "Project root is not a Git repository."

case "$START_PHASE" in
  1|2|3|4|5|6) ;;
  *) fail "Start phase must be an integer from 1 through 6." ;;
esac

catalog_input_is_immutable || fail "$CATALOG_INPUT differs from the approved input hash."

mkdir -p "$LOG_DIR"
echo -e "  ${GREEN}OK${NC} Project and all three inputs are present"
echo -e "  ${GREEN}OK${NC} Catalog input hash is locked"
echo -e "  ${YELLOW}WAIT${NC} Baseline xcodebuild"
run_xcodebuild "preflight" || fail "Baseline xcodebuild failed; see $LOG_DIR/preflight_xcodebuild.log."
echo -e "  ${GREEN}OK${NC} Baseline xcodebuild passed"
echo ""

# ── EXECUTE PHASES ────────────────────────────────────────────────────────

for i in $(seq "$START_PHASE" "$PHASES"); do
  case "$i" in
    1|3|4) MAX_TURNS=30 ;;
    *) MAX_TURNS=$DEFAULT_TURNS ;;
  esac

  echo ""
  echo -e "${YELLOW}========================================================${NC}"
  echo -e "${YELLOW}  Phase $i of $PHASES — max $MAX_TURNS turns${NC}"
  echo -e "${YELLOW}========================================================${NC}"

  # Commit every current file before the phase. This is the exact rollback
  # point and also brings the three companion inputs under version control.
  git add -A
  git commit -m "autopilot: pre-phase-$i snapshot (spec09)" --allow-empty >/dev/null
  PRE_PHASE_COMMIT=$(git rev-parse HEAD)
  echo -e "  ${GREEN}OK${NC} Pre-phase checkpoint $PRE_PHASE_COMMIT"

  RESULT_FILE="$LOG_DIR/phase_${i}_result.json"
  STDERR_FILE="$LOG_DIR/phase_${i}_stderr.log"

  PHASE_DEPLOY_POLICY="No deploy is authorized in this phase unless the phase text names a targeted deploy. Never run a broad Firebase Functions deploy."
  if [ "$i" -eq 2 ]; then
    PHASE_DEPLOY_POLICY="Do not run any deploy command in this Claude session. The outer runner owns both the exact targeted functions:spawnTasks deploy and the separate Firestore-rules approval gate."
  fi

  PHASE_RETRY_CONTEXT=""
  if [ "$i" -eq 1 ] && [ -s "$LOG_DIR/phase_1_result.json" ]; then
    PHASE_RETRY_CONTEXT="Prior Phase 1 attempts resolved and verified the implementation shape, but the runner rolled local edits back. One attempt exhausted its turn limit after a successful live seed; the next completed in 22 turns with live seed, build, and diff checks passing, but the outer raw-byte gate rejected functions/taskCatalogData.json because it contained exactly one trailing LF (68,968 bytes instead of the 68,967-byte raw array). Implement again from the clean checkpoint. CRITICAL: write only raw_catalog bytes with a binary write such as open(path, 'wb').write(raw_catalog) or fs.writeFileSync(path, Buffer); do not append a newline or any byte before/after the closing bracket. Compare the target Buffer directly to the raw source slice. To stay within 30 turns: do not write a temporary script, do not retry blocked shasum commands, and do not run xcodebuild in the background. Use an in-memory Node/Python pipeline for extraction/merge and run verification in the foreground. The resolved companion has 61 catalog rows and 34 definitions; the intended merge has 35 definitions: 22 original documents unchanged byte-for-byte, 3 overlapping conversation definitions replaced from the companion (setup_utilities, transfer_utilities, financial_accounts), and 10 companion additions. Do not re-investigate that resolved merge shape. The forward-mail taskId in the immutable companion is FORWARD_MAIL_USPS; use that real id for the seeder spot check."
  elif [ "$i" -eq 2 ] && [ -s "$LOG_DIR/phase_2_result.json" ]; then
    PHASE_RETRY_CONTEXT="A prior Phase 2 attempt completed the entire required architecture/test read pass but exhausted the 25-turn limit before editing; the runner rolled back a clean tree and no deploy occurred. Begin implementation after one BATCHED read call for the exact READ FIRST files/ranges; do not rediscover or repeatedly grep. Resolved facts: functions/index.js imports callable modules at the top and exports them at the bottom; add require('./spawnTasks') and exports.spawnTasks. Existing modules use firebase-functions/v2/https onCall + HttpsError, guard admin.initializeApp(), and us-central1/15s/256MiB style. The canonical move-date read is users/{uid}/identity/identity first, then users/{uid}/user_assessments limit(1), accepting Timestamp.toDate/string/number as in peezyChat.js dateFromValue. The generation document shape and due-date formula are exactly those pasted in Spec 09/audit from Assessment/AssessmentModels/TaskGenerationService.swift. firestore.rules needs only the additive moveAnswers owner-read block and no client write. Keep pure validation/date/doc builders testable if that lets node:test cover duplicate-token/unknown-id/batch-shape behavior efficiently. Do not run shasum, firebase --version, java --version, or any deploy command; the outer runner handles immutable hash, build, targeted function deploy, and rules gate. Run tests/build in the foreground."
  fi

  PROMPT="You are implementing exactly Phase $i of Spec 09 in the Peezy iOS repository.

Read CLAUDE.md and peezy-conventions-v2.md. Then read $SPEC_FILE, the entire Phase $i section, every file named in READ FIRST, and the cited sections of $AUDIT_FILE before editing. Phase 0 is already complete.

Execute Phase $i completely and only Phase $i. Follow all architecture decisions, DO NOT CHANGE boundaries, file limits, tests, and verification in the spec. Write PHASE_MANIFEST before edits as required by the repository hooks. Do not refactor, redesign, improve locked copy, or touch unrelated files. Use @Observable for new Swift observable classes, preserve the single Firestore-to-PeezyCard decoder, use NSNumber-safe decoding, guard empty Firestore document ids, and add accessibility identifiers to new views.

Deployment policy: $PHASE_DEPLOY_POLICY

Retry context, if any: $PHASE_RETRY_CONTEXT

Phase 1 content boundary: $CATALOG_INPUT is immutable and its SHA-256 must remain $EXPECTED_CATALOG_SHA256. Do not author, edit, normalize, pretty-print, or improve any catalog content. Write functions/taskCatalogData.json from the raw taskCatalog array bytes in the companion input and byte-compare the result. Preserve every original flow definition byte-for-byte except an overlapping conversation definition that the companion intentionally replaces; copy replacement/addition bytes only from the companion.

Before finishing: run every phase-specific verification, run the Spec 09 xcodebuild, review git diff from checkpoint $PRE_PHASE_COMMIT, and fix failures. Do not mark the spec file or edit it to record completion. In your final result, report exact tests, deploy commands, changed files, and any unresolved failure."

  echo -e "  ${BLUE}Starting fresh Claude Code session...${NC}"
  set +e
  claude -p "$PROMPT" \
    --permission-mode acceptEdits \
    --max-turns "$MAX_TURNS" \
    --output-format json >"$RESULT_FILE" 2>"$STDERR_FILE"
  CLAUDE_EXIT=$?
  set -e

  IS_ERROR=true
  if [ "$CLAUDE_EXIT" -eq 0 ] && jq empty "$RESULT_FILE" >/dev/null 2>&1; then
    IS_ERROR=$(jq -r '.is_error // false' "$RESULT_FILE" 2>/dev/null)
  fi

  if [ "$CLAUDE_EXIT" -ne 0 ] || [ "$IS_ERROR" = "true" ]; then
    echo -e "${RED}  Phase $i Claude session failed (exit $CLAUDE_EXIT).${NC}"
    jq -r '.result // empty' "$RESULT_FILE" 2>/dev/null | tail -40 || true
    rollback_phase "$i" "$PRE_PHASE_COMMIT"
    echo -e "${YELLOW}Resume with: ./peezy_build.sh $i${NC}"
    exit 1
  fi

  catalog_input_is_immutable || {
    echo -e "${RED}  Immutable catalog input changed during Phase $i.${NC}"
    rollback_phase "$i" "$PRE_PHASE_COMMIT"
    exit 1
  }

  if [ "$i" -eq 1 ]; then
    if ! validate_catalog_transcription; then
      echo -e "${RED}  Phase 1 catalog is not a byte-for-byte transcription.${NC}"
      rollback_phase "$i" "$PRE_PHASE_COMMIT"
      exit 1
    fi
    echo -e "  ${GREEN}OK${NC} Catalog transcription is byte-identical"
  fi

  echo -e "  ${YELLOW}WAIT${NC} Independent post-phase xcodebuild"
  if ! run_xcodebuild "phase_${i}"; then
    echo -e "${RED}  Phase $i failed independent xcodebuild.${NC}"
    rollback_phase "$i" "$PRE_PHASE_COMMIT"
    echo -e "${YELLOW}Resume with: ./peezy_build.sh $i${NC}"
    exit 1
  fi

  git diff --check "$PRE_PHASE_COMMIT" -- || {
    echo -e "${RED}  Phase $i failed git diff --check.${NC}"
    rollback_phase "$i" "$PRE_PHASE_COMMIT"
    exit 1
  }

  git add -A
  git commit -m "autopilot: phase-$i complete (spec09)" --allow-empty >/dev/null
  PHASE_COMMIT=$(git rev-parse HEAD)
  PHASE_COST=$(jq -r '.total_cost_usd // "?"' "$RESULT_FILE" 2>/dev/null)
  NUM_TURNS=$(jq -r '.num_turns // "?"' "$RESULT_FILE" 2>/dev/null)
  echo -e "${GREEN}  Phase $i complete at $PHASE_COMMIT (cost: \$$PHASE_COST; turns: $NUM_TURNS)${NC}"

  # Human gate required by Spec 09. The Phase 2 agent was forbidden from
  # deploying anything; only these exact outer-runner commands can do so.
  if [ "$i" -eq 2 ]; then
    echo ""
    echo -e "${YELLOW}Deploying only functions:spawnTasks...${NC}"
    set +e
    firebase deploy --only functions:spawnTasks 2>&1 | tee "$LOG_DIR/phase_2_spawnTasks_deploy.log"
    FUNCTION_DEPLOY_EXIT=${PIPESTATUS[0]}
    set -e
    if [ "$FUNCTION_DEPLOY_EXIT" -ne 0 ]; then
      fail "Targeted functions:spawnTasks deploy failed; see $LOG_DIR/phase_2_spawnTasks_deploy.log."
    fi
    echo -e "${GREEN}Targeted functions:spawnTasks deploy complete.${NC}"

    echo ""
    echo -e "${YELLOW}APPROVAL REQUIRED: deploy checked-in firestore.rules now? [y/n]${NC}"
    while true; do
      IFS= read -r RULES_APPROVAL || fail "No approval received for Firestore rules deploy."
      case "$RULES_APPROVAL" in
        y|Y|yes|YES)
          echo -e "${YELLOW}Deploying only firestore.rules...${NC}"
          firebase deploy --only firestore:rules 2>&1 | tee "$LOG_DIR/phase_2_firestore_rules_deploy.log"
          echo -e "${GREEN}Firestore rules deploy complete.${NC}"
          break
          ;;
        n|N|no|NO)
          echo -e "${YELLOW}Firestore rules deploy skipped by user; continuing the local build.${NC}"
          break
          ;;
        *)
          echo "Enter y or n."
          ;;
      esac
    done
  fi
done

echo ""
echo -e "${GREEN}Spec 09 autonomous build complete: Phases 1-6 passed.${NC}"
echo "Logs: $LOG_DIR"
