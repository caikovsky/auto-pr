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
# Record the value that follows --title.
while [ $# -gt 0 ]; do
  if [ "$1" = --title ]; then printf '%s' "$2" > "$FAKE_TITLE_OUT"; fi
  shift
done
FAKE_EOF
chmod +x "$WORK/bin/gh"
export PATH="$WORK/bin:$PATH" FAKE_TITLE_OUT="$WORK/title.out"

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

# Docs lint: no command line in SKILL.md carries a title or body as a double-quoted literal.
if grep -nE -- '--(title|body) "<' "$SKILL"; then
  FAIL=$((FAIL + 1)); echo "FAIL SKILL.md puts a title or body literal in a command line"
else
  PASS=$((PASS + 1)); echo "ok   SKILL.md has no --title/--body literal in a command"
fi

echo
echo "passed: $PASS, failed: $FAIL"
[ "$FAIL" -eq 0 ]
