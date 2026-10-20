#!/usr/bin/env bash
# Print a Jira summary without its bracketed tags ([AN], [Android], [SPIKE], [PoC], ...).
#
# Usage: clean-title.sh "<summary>"   or   printf '%s\n' "<summary>" | clean-title.sh
#
# Removes every [...] group anywhere in the text (no nesting), collapses whitespace and trims.
# When nothing is left, prints the original summary trimmed.
set -euo pipefail

if [ $# -gt 0 ]; then
  original="$*"
else
  original=$(cat)
fi

trim() {
  sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

cleaned=$(printf '%s' "$original" | sed -e 's/\[[^]]*\]//g' | tr -s '[:space:]' ' ' | trim)

if [ -n "$cleaned" ]; then
  printf '%s\n' "$cleaned"
else
  printf '%s\n' "$original" | trim
fi
