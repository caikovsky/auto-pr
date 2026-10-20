#!/usr/bin/env bash
# Tests for skills/autopr/scripts/clean-title.sh. Needs bash and jq.
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

# --- hostile summaries: nothing may be expanded or executed ---
# shellcheck disable=SC2016 # the text must stay literal
HOSTILE='Show $0 balance for `echo INJECTED` users [AN]'
# shellcheck disable=SC2016
CLEAN_HOSTILE='Show $0 balance for `echo INJECTED` users'
actual=$(printf '%s\n' "$HOSTILE" | "$BASH" "$CLEAN")
if [ "$actual" = "$CLEAN_HOSTILE" ]; then PASS=$((PASS + 1)); echo "ok   hostile summary on stdin stays literal"; else FAIL=$((FAIL + 1)); echo "FAIL hostile summary on stdin: got [$actual]"; fi

# The documented command from SKILL.md: Jira JSON -> jq -> clean-title.sh -> title file.
WORK=$(mktemp -d "${TMPDIR:-/tmp}/autopr-clean-test.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
jq -n --arg s "$HOSTILE" '{fields: {summary: $s}}' > "$WORK/jira.json"
jq -r .fields.summary "$WORK/jira.json" | "$BASH" "$CLEAN" | { printf '[TLAB-1] - '; cat; } > "$WORK/title.txt"
actual=$(cat "$WORK/title.txt")
if [ "$actual" = "[TLAB-1] - $CLEAN_HOSTILE" ]; then PASS=$((PASS + 1)); echo "ok   documented jira-to-title pipeline stays literal"; else FAIL=$((FAIL + 1)); echo "FAIL documented pipeline: got [$actual]"; fi

# several arguments join with a space
actual=$("$BASH" "$CLEAN" "[AN]" "Fix" "bug")
if [ "$actual" = "Fix bug" ]; then PASS=$((PASS + 1)); echo "ok   several arguments"; else FAIL=$((FAIL + 1)); echo "FAIL several arguments: got [$actual]"; fi

echo
echo "passed: $PASS, failed: $FAIL"
[ "$FAIL" -eq 0 ]
