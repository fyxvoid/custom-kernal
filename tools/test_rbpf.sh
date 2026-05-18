#!/usr/bin/env bash
# RBPF integration test — verifies that the packet filter module blocks
# and accepts traffic according to configured rules.
#
# Requires: nmap, hping3 or curl, and the rbpf module loaded.

set -euo pipefail

GRN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
PASS=0; FAIL=0

pass() { echo -e "${GRN}PASS${NC} $*"; (( PASS++ )) || true; }
fail() { echo -e "${RED}FAIL${NC} $*"; (( FAIL++ )) || true; }

require_root() { [[ $EUID -eq 0 ]] || { echo "Must be root."; exit 1; }; }
require_root

if [[ ! -f /proc/rbpf_rules ]]; then
    echo "rbpf module not loaded. Run: insmod rbpf.ko"
    exit 1
fi

echo "=== RBPF Integration Tests ==="

# ── Test 1: Module loaded ──────────────────────────────────────────────────────
lsmod | grep -q rbpf && pass "rbpf module is loaded" || fail "rbpf module missing"

# ── Test 2: /proc interface readable ─────────────────────────────────────────
cat /proc/rbpf_rules &>/dev/null && pass "/proc/rbpf_rules readable" \
    || fail "/proc/rbpf_rules not readable"

# ── Test 3: Add a rule and verify it appears ─────────────────────────────────
echo "FLUSH" > /proc/rbpf_rules
echo "ADD 10 127.0.0.1/32 0.0.0.0/0 0-0 9999-9999 tcp accept" > /proc/rbpf_rules
grep -q "9999" /proc/rbpf_rules && pass "Rule ADD visible in /proc/rbpf_rules" \
    || fail "Rule not found after ADD"

# ── Test 4: DEL removes the rule ─────────────────────────────────────────────
echo "DEL 10" > /proc/rbpf_rules
grep -q "9999" /proc/rbpf_rules && fail "Rule still present after DEL" \
    || pass "Rule removed after DEL"

# ── Test 5: FLUSH clears all rules ───────────────────────────────────────────
echo "ADD 5 0.0.0.0/0 0.0.0.0/0 0-0 0-0 any drop" > /proc/rbpf_rules
echo "FLUSH" > /proc/rbpf_rules
COUNT=$(grep -c "^[0-9]" /proc/rbpf_rules 2>/dev/null || true)
[[ "$COUNT" -eq 0 ]] && pass "FLUSH cleared all rules" || fail "Rules remain after FLUSH"

# ── Test 6: Loopback traffic (default rule) ───────────────────────────────────
echo "ADD 1 127.0.0.0/8 0.0.0.0/0 0-0 0-0 any accept" > /proc/rbpf_rules
ping -c 1 -W 1 127.0.0.1 &>/dev/null && pass "Loopback ICMP accepted" \
    || fail "Loopback ICMP dropped (unexpected)"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "Results: PASS=$PASS  FAIL=$FAIL"
[[ $FAIL -eq 0 ]] && { echo "All tests passed."; exit 0; } \
    || { echo "Some tests failed."; exit 1; }
