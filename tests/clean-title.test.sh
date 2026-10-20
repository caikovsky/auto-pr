#!/usr/bin/env bash
# Tests for skills/autopr/scripts/clean-title.sh. Needs only bash.
# The first five cases are ported from the Python CLI (PR #7, test_clean_title_strips_tags).
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CLEAN="$HERE/../skills/autopr/scripts/clean-title.sh"

PASS=0
FAIL=0

# check <name> <input> <expected>: input as an argument, then as stdin.
check() {
  local actual
  actual=$("$BASH" "$CLEAN" "$2")
  if [ "$actual" = "$3" ]; then PASS=$((PASS + 1)); echo "ok   $1"; else FAIL=$((FAIL + 1)); echo "FAIL $1: expected [$3] got [$actual]"; fi
  actual=$(printf '%s\n' "$2" | "$BASH" "$CLEAN")
  if [ "$actual" = "$3" ]; then PASS=$((PASS + 1)); echo "ok   $1 (stdin)"; else FAIL=$((FAIL + 1)); echo "FAIL $1 (stdin): expected [$3] got [$actual]"; fi
}

# --- ported from PR #7 ---
check "platform tag" "[AN] Fix bug" "Fix bug"
check "platform and spike tags" "[AN] [SPIKE] Fix bug" "Fix bug"
check "long platform and PoC tags" "[Android] [PoC] Investigate auth" "Investigate auth"
check "no tags" "Fix bug" "Fix bug"
check "three tags and a double space" "[SPIKE] [AN] [iOS]  Explore feature" "Explore feature"

# --- added ---
check "iOS tag" "[iOS] Update onboarding" "Update onboarding"
check "lowercase tag" "[an] Fix crash" "Fix crash"
check "tag in the middle" "Fix [AN] crash on login" "Fix crash on login"
check "tag at the end" "Fix crash on login [AN]" "Fix crash on login"
check "tags at both ends" "[SPIKE] Fix crash [AN]" "Fix crash"
check "double spaces collapse" "Fix   the    bug" "Fix the bug"
check "spaces inside brackets" "[ AN ] Fix bug" "Fix bug"
check "tag glued to words" "Fix[AN]bug" "Fixbug"
check "leading and trailing space" "   Fix bug  " "Fix bug"
check "only tags: original trimmed" "  [AN] [SPIKE]  " "[AN] [SPIKE]"
check "only one tag: original" "[SPIKE]" "[SPIKE]"
check "empty input" "" ""
check "unmatched bracket stays" "[AN Fix bug" "[AN Fix bug"
check "round brackets stay" "Fix (AN) bug" "Fix (AN) bug"
check "tab and newline collapse" "$(printf 'Fix\tthe\nbug')" "Fix the bug"
check "ticket-like text stays" "Add TLAB-12 support" "Add TLAB-12 support"

# several arguments join with a space
actual=$("$BASH" "$CLEAN" "[AN]" "Fix" "bug")
if [ "$actual" = "Fix bug" ]; then PASS=$((PASS + 1)); echo "ok   several arguments"; else FAIL=$((FAIL + 1)); echo "FAIL several arguments: got [$actual]"; fi

echo
echo "passed: $PASS, failed: $FAIL"
[ "$FAIL" -eq 0 ]
