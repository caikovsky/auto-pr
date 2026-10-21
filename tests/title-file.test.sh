#!/usr/bin/env bash
# The documented way to pass untrusted text (a Jira summary, an issue title, a commit subject)
# to gh is a title file read back with "$(cat file)". This test proves the pattern keeps `$0`,
# backticks and quotes literal, and that SKILL.md never puts a title or body in a command line.
# It runs a fake gh that records its --title argument; nothing touches GitHub.
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SKILL="$HERE/../skills/autopr/SKILL.md"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/autopr-title-test.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
mkdir "$WORK/bin"
cat > "$WORK/bin/gh" << 'FAKE_EOF'
#!/usr/bin/env bash
# Record the value that follows --title, and every label or reviewer value (one per line).
while [ $# -gt 0 ]; do
  case "$1" in
    --title) printf '%s' "$2" > "$FAKE_TITLE_OUT" ;;
    --label | --add-label | --reviewer | --add-reviewer) printf '%s\n' "$2" >> "$FAKE_VALUES_OUT" ;;
  esac
  shift
done
FAKE_EOF
chmod +x "$WORK/bin/gh"
export PATH="$WORK/bin:$PATH" FAKE_TITLE_OUT="$WORK/title.out" FAKE_VALUES_OUT="$WORK/values.out"

PASS=0
FAIL=0
expect() { # <name> <expected> <actual>
  if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); echo "ok   $1"; else FAIL=$((FAIL + 1)); echo "FAIL $1: expected [$2] got [$3]"; fi
}

# shellcheck disable=SC2016 # the text must stay literal
HOSTILE='Show $0 balance for `echo INJECTED` users "quoted" \n $(echo SUBST) end'

# The documented pattern: title file written without a shell, then "$(cat file)".
printf '%s\n' "$HOSTILE" > "$WORK/title.txt"
gh pr create --head x --base y --title "$(cat "$WORK/title.txt")" --body-file /dev/null
expect "title file + \$(cat): create keeps the text literal" "$HOSTILE" "$(cat "$FAKE_TITLE_OUT")"
gh pr edit 1 --title "$(cat "$WORK/title.txt")"
expect "title file + \$(cat): edit keeps the text literal" "$HOSTILE" "$(cat "$FAKE_TITLE_OUT")"

# Control: typing the text inside double quotes in a command line expands it (the bug).
bash -c "gh pr create --title \"$HOSTILE\""
if [ "$(cat "$FAKE_TITLE_OUT")" != "$HOSTILE" ]; then PASS=$((PASS + 1)); echo "ok   control: double-quoted text is expanded"; else FAIL=$((FAIL + 1)); echo "FAIL control: double-quoted text was not expanded"; fi

# Labels and reviewer handles are untrusted too: one file per value, read back with "$(cat file)".
# shellcheck disable=SC2016 # the values must stay literal
printf '%s\n' "won't fix" > "$WORK/label-1.txt"
# shellcheck disable=SC2016
printf '%s\n' '$(echo x)' > "$WORK/label-2.txt"
printf '%s\n' 'octo-org/reviewers' > "$WORK/reviewer-1.txt"
: > "$FAKE_VALUES_OUT"
gh pr create --label "$(cat "$WORK/label-1.txt")" --label "$(cat "$WORK/label-2.txt")" --reviewer "$(cat "$WORK/reviewer-1.txt")"
gh pr edit 1 --add-label "$(cat "$WORK/label-1.txt")" --add-reviewer "$(cat "$WORK/reviewer-1.txt")"
# shellcheck disable=SC2016
expect "labels and reviewers keep apostrophes and \$(...) literal" "won't fix"$'\n''$(echo x)'$'\n''octo-org/reviewers'$'\n'"won't fix"$'\n''octo-org/reviewers' "$(cat "$FAKE_VALUES_OUT")"
# Control: a single-quoted placeholder breaks on an apostrophe.
: > "$FAKE_VALUES_OUT"
bash -c "gh pr create --label 'won't fix'" 2> /dev/null || true
if [ "$(cat "$FAKE_VALUES_OUT")" != "won't fix" ]; then PASS=$((PASS + 1)); echo "ok   control: a single-quoted label breaks on an apostrophe"; else FAIL=$((FAIL + 1)); echo "FAIL control: single-quoted label survived"; fi

# Docs lint: no command line in SKILL.md carries a title or body as a double-quoted literal.
if grep -nE -- '--(title|body) "<' "$SKILL"; then
  FAIL=$((FAIL + 1)); echo "FAIL SKILL.md puts a title or body literal in a command line"
else
  PASS=$((PASS + 1)); echo "ok   SKILL.md has no --title/--body literal in a command"
fi

# Docs lint: in the command examples (fenced code blocks), a branch, base, handle or label
# placeholder after a flag must be single-quoted: an unquoted `#` starts a shell comment and
# `<branch>` could hold anything git allows in a ref name.
if awk '/^ *```/ { inside = !inside; next } inside' "$SKILL" | grep -nE -- "--[a-z-]+ <(branch|base)>"; then
  FAIL=$((FAIL + 1)); echo "FAIL SKILL.md has an unquoted branch/base placeholder after a flag"
else
  PASS=$((PASS + 1)); echo "ok   SKILL.md quotes branch/base placeholders in commands"
fi
# Labels and reviewer handles hold arbitrary text (an apostrophe breaks single quotes): they must
# come from a file, as "$(cat <work-dir>/label-N.txt)", never as a bare or single-quoted placeholder.
if awk '/^ *```/ { inside = !inside; next } inside' "$SKILL" | grep -nE -- "--[a-z-]+ '?<(handle|name)>"; then
  FAIL=$((FAIL + 1)); echo "FAIL SKILL.md passes a label or reviewer placeholder directly"
else
  PASS=$((PASS + 1)); echo "ok   SKILL.md reads labels and reviewers from files"
fi
# A heredoc delimiter that is the same every time can collide with the content.
if grep -nE 'AUTOPR_EOF([^_]|$)' "$SKILL" "$HERE/../skills/autopr/references/"*.md; then
  FAIL=$((FAIL + 1)); echo "FAIL a fixed AUTOPR_EOF heredoc delimiter is documented"
else
  PASS=$((PASS + 1)); echo "ok   no fixed heredoc delimiter is documented"
fi

echo
echo "passed: $PASS, failed: $FAIL"
[ "$FAIL" -eq 0 ]
