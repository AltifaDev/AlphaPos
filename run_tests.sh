#!/usr/bin/env bash
# run_tests.sh
# AlphaPos — Phase 4: Automated Unit Test Runner
#
# Usage:
#   ./run_tests.sh           # run all suites
#   ./run_tests.sh --verbose # identical (verbose by default)
#
# The script compiles all test files together with the Core/Security helper
# using the Swift compiler (no Xcode required) and executes the runner.
# Exit code: 0 = all green, 1 = one or more failures.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR/AlphaPos"
TESTS_DIR="$PROJECT_DIR/Tests"
BUILD_DIR="$SCRIPT_DIR/.build/tests"

# ── Terminal colours ──────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RESET='\033[0m'

echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${RESET}"
echo -e "${CYAN}║          AlphaPos — Automated Unit Test Runner               ║${RESET}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${RESET}"
echo ""

# ── Sanity checks ─────────────────────────────────────────────────────────────
if ! command -v swift &>/dev/null; then
    echo -e "${RED}ERROR: 'swift' command not found. Install Xcode or Swift toolchain.${RESET}"
    exit 1
fi

SWIFT_VERSION=$(swift --version 2>&1 | head -1)
echo -e "  Swift : ${CYAN}${SWIFT_VERSION}${RESET}"
echo -e "  Tests : ${CYAN}${TESTS_DIR}${RESET}"
echo ""

# ── Collect source files ───────────────────────────────────────────────────────
# Order matters: shared helpers first, then TestResult, suites, then runner.
SOURCES=(
    "$PROJECT_DIR/Core/Security/SecurityHelper.swift"
    "$PROJECT_DIR/Core/Localization/AppLocalization.swift"
    "$PROJECT_DIR/Models/InventoryMovementType.swift"
    "$TESTS_DIR/TestResult.swift"
    "$TESTS_DIR/SecurityTests.swift"
    "$TESTS_DIR/POSTests.swift"
    "$TESTS_DIR/DecimalCurrencyTests.swift"
    "$TESTS_DIR/ThreadSafetyTests.swift"
    "$TESTS_DIR/InventoryTests.swift"
    "$TESTS_DIR/InventoryEnhancementTests.swift"
    "$TESTS_DIR/InventoryEnterpriseTests.swift"
    "$TESTS_DIR/TimecardTests.swift"
    "$TESTS_DIR/PayrollTests.swift"
    "$TESTS_DIR/LocalizationTests.swift"
    "$TESTS_DIR/ExpenseTests.swift"
    "$TESTS_DIR/InventoryAdvancedTests.swift"
    "$TESTS_DIR/TestRunner.swift"
)

# Verify each source file exists before attempting compilation.
MISSING=0
for f in "${SOURCES[@]}"; do
    if [[ ! -f "$f" ]]; then
        echo -e "${RED}  MISSING: $f${RESET}"
        MISSING=1
    fi
done
if [[ $MISSING -eq 1 ]]; then
    echo -e "${RED}One or more test files are missing. Aborting.${RESET}"
    exit 1
fi

# ── Emit a tiny Swift entry-point wrapper ─────────────────────────────────────
mkdir -p "$BUILD_DIR"

ENTRY_POINT="$BUILD_DIR/main.swift"
cat > "$ENTRY_POINT" <<'SWIFT_EOF'
import Foundation
let allPassed = TestRunner.runAll()
exit(allPassed ? 0 : 1)
SWIFT_EOF

BINARY="$BUILD_DIR/AlphaPosTests"

# ── Compile ───────────────────────────────────────────────────────────────────
echo -e "${YELLOW}  Compiling test bundle …${RESET}"

if ! swiftc \
        -D TEST_RUNNER \
        "${SOURCES[@]}" \
        "$ENTRY_POINT" \
        -o "$BINARY" \
        2>&1; then
    echo ""
    echo -e "${RED}══════════════════════════════════════════════════════════════${RESET}"
    echo -e "${RED}  COMPILATION FAILED — see errors above.${RESET}"
    echo -e "${RED}══════════════════════════════════════════════════════════════${RESET}"
    exit 1
fi

if [[ ! -f "$BINARY" ]]; then
    echo -e "${RED}  ERROR: binary not produced at expected path: $BINARY${RESET}"
    exit 1
fi

echo -e "${GREEN}  Compilation succeeded.${RESET}"
echo ""

# ── Execute ───────────────────────────────────────────────────────────────────
"$BINARY"
EXIT_CODE=$?

# ── Report ────────────────────────────────────────────────────────────────────
if [[ $EXIT_CODE -eq 0 ]]; then
    echo -e "${GREEN}  Shell exit code: 0 — All tests passed ✅${RESET}"
else
    echo -e "${RED}  Shell exit code: $EXIT_CODE — Some tests failed ❌${RESET}"
fi

echo ""
exit $EXIT_CODE
