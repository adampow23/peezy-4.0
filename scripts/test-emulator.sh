#!/bin/bash
# S1 (briefs/S1_BRIEF.md): run Peezy's emulator-backed suites.
# Signing: the project's automatic signing (team + entitlements) is required; an
# ad-hoc or unsigned host loses get-task-allow/keychain and cannot be attached.
# Emulator only. This script never targets a production Firebase project:
# --project is the demo project id the emulators accept without credentials.
#
# Usage:
#   scripts/test-emulator.sh                      # Swift S1 suites + rules tests
#   scripts/test-emulator.sh swift [Suite ...]    # Swift suites only (default: S1 suites)
#   scripts/test-emulator.sh rules                # rules tests only
set -euo pipefail
cd "$(dirname "$0")/.."

export PATH="/opt/homebrew/opt/openjdk@21/bin:/opt/homebrew/opt/node@24/bin:$PATH"
PROJECT="demo-peezy-phase1"
SIM="${PEEZY_SIM_UDID:-DC0CC10C-6DB0-496A-8B0E-51E60D958A27}"   # iPhone 17 Pro (spec v5 §9.2)
MODE="${1:-all}"; shift || true
DEFAULT_SUITES=("Peezy 4.0Tests/DurableStoreRecoveryTests" "Peezy 4.0Tests/TaskPlanDispositionTests" "Peezy 4.0Tests/TaskSupersessionTests")
SUITES=("${@:-${DEFAULT_SUITES[@]}}")

ONLY=""
for s in "${SUITES[@]}"; do ONLY+=" -only-testing:'$s'"; done

SWIFT_CMD="env -u PEEZY_RUN_FIRESTORE_INTEGRATION \
  TEST_RUNNER_FIRESTORE_EMULATOR_HOST=\"\$FIRESTORE_EMULATOR_HOST\" \
  TEST_RUNNER_FIREBASE_AUTH_EMULATOR_HOST=\"\$FIREBASE_AUTH_EMULATOR_HOST\" \
  TEST_RUNNER_FIREBASE_STORAGE_EMULATOR_HOST=\"\${FIREBASE_STORAGE_EMULATOR_HOST:-}\" \
  xcodebuild test -project 'Peezy 4.0.xcodeproj' -scheme 'Peezy 4.0' -configuration Debug \
  -destination 'platform=iOS Simulator,id=$SIM' -parallel-testing-enabled NO $ONLY \
  -skip-testing:'Peezy 4.0UITests' 2>&1 | tee /tmp/peezy-emulator-xcodebuild.log | grep -E 'Test Suite|Test Case|✔|✘|error:|\\*\\* TEST|Executed' || true; \
  test \"\${PIPESTATUS[0]}\" -eq 0"

RULES_CMD="(cd functions && FIRESTORE_EMULATOR_HOST=\"\$FIRESTORE_EMULATOR_HOST\" node --test rules-tests/firestoreRules.test.js)"

case "$MODE" in
  swift) INNER="$SWIFT_CMD" ;;
  rules) INNER="$RULES_CMD" ;;
  all)   INNER="$SWIFT_CMD && $RULES_CMD" ;;
  *) echo "unknown mode: $MODE" >&2; exit 2 ;;
esac

exec firebase emulators:exec --only firestore,auth,storage --project "$PROJECT" "$INNER"
