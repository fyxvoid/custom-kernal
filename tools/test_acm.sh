#!/usr/bin/env bash
# ACM LSM integration test — verifies that the MAC module is loaded
# and that /proc/acm_policy is readable/writable with proper restrictions.

set -euo pipefail

GRN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
PASS=0; FAIL=0

pass() { echo -e "${GRN}PASS${NC} $*"; (( PASS++ )) || true; }
fail() { echo -e "${RED}FAIL${NC} $*"; (( FAIL++ )) || true; }

require_root() { [[ $EUID -eq 0 ]] || { echo "Must be root."; exit 1; }; }
require_root

if [[ ! -f /proc/acm_policy ]]; then
    echo "acm_lsm module not loaded. Run: insmod acm_lsm.ko"
    exit 1
fi

echo "=== ACM LSM Integration Tests ==="

# ── Test 1: Module loaded ──────────────────────────────────────────────────────
lsmod | grep -q acm_lsm && pass "acm_lsm module is loaded" || fail "acm_lsm module missing"

# ── Test 2: /proc/acm_policy readable ────────────────────────────────────────
cat /proc/acm_policy &>/dev/null && pass "/proc/acm_policy readable" \
    || fail "/proc/acm_policy not readable"

# ── Test 3: Default labels present ───────────────────────────────────────────
grep -q "trusted" /proc/acm_policy && pass "Label 'trusted' found in policy" \
    || fail "Label 'trusted' missing"
grep -q "default" /proc/acm_policy && pass "Label 'default' found in policy" \
    || fail "Label 'default' missing"

# ── Test 4: Add a label ───────────────────────────────────────────────────────
echo "LABEL testlabel" > /proc/acm_policy
grep -q "testlabel" /proc/acm_policy && pass "LABEL command worked" \
    || fail "LABEL command had no effect"

# ── Test 5: Add an ALLOW rule ─────────────────────────────────────────────────
echo "ALLOW testlabel default read,write" > /proc/acm_policy
grep -q "testlabel" /proc/acm_policy && pass "ALLOW rule added" \
    || fail "ALLOW rule not visible"

# ── Test 6: FLUSH clears rules ────────────────────────────────────────────────
echo "FLUSH" > /proc/acm_policy
RULE_COUNT=$(grep -c "^  [a-z]" /proc/acm_policy 2>/dev/null || true)
[[ "$RULE_COUNT" -eq 0 ]] && pass "FLUSH cleared all rules" \
    || fail "Rules remain after FLUSH (count=$RULE_COUNT)"

# ── Test 7: Non-root cannot write policy ─────────────────────────────────────
if [[ -x /usr/bin/su ]] || command -v sudo &>/dev/null; then
    TMPOUT=$(mktemp)
    sudo -u nobody bash -c 'echo "FLUSH" > /proc/acm_policy' 2>"$TMPOUT" \
        && fail "Non-root wrote to /proc/acm_policy (should be denied)" \
        || pass "Non-root write to /proc/acm_policy correctly denied"
    rm -f "$TMPOUT"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "Results: PASS=$PASS  FAIL=$FAIL"
[[ $FAIL -eq 0 ]] && { echo "All tests passed."; exit 0; } \
    || { echo "Some tests failed."; exit 1; }
