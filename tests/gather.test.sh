#!/usr/bin/env bash
# Tests for skills/autopr/scripts/gather.sh. Needs only bash, git and jq.
# Each test builds a throwaway repo with a local bare "origin" and a fake gh on PATH.
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
GATHER="$HERE/../skills/autopr/scripts/gather.sh"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/autopr-test.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=Test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=Test GIT_COMMITTER_EMAIL=test@example.com
export GIT_TERMINAL_PROMPT=0

# Fake gh: answers `pr view` and `repo view` from FAKE_GH_* variables and logs every call.
FAKEBIN="$WORK/bin"
mkdir -p "$FAKEBIN"
cat > "$FAKEBIN/gh" << 'FAKE_EOF'
#!/usr/bin/env bash
echo "$*" >> "${FAKE_GH_LOG:-/dev/null}"
case "$1 $2" in
  "pr view")
    if [ -n "${FAKE_GH_PR_JSON:-}" ]; then printf '%s' "$FAKE_GH_PR_JSON"; exit 0; fi
    if [ -n "${FAKE_GH_PR_ERR:-}" ]; then echo "$FAKE_GH_PR_ERR" >&2; exit 1; fi
    echo 'no pull requests found for branch "x"' >&2
    exit 1
    ;;
  "repo view")
    if [ -n "${FAKE_GH_DEFAULT:-}" ]; then echo "$FAKE_GH_DEFAULT"; exit 0; fi
    echo "error connecting to api.github.com" >&2
    exit 1
    ;;
esac
exit 1
FAKE_EOF
chmod +x "$FAKEBIN/gh"
export PATH="$FAKEBIN:$PATH"
export FAKE_GH_LOG="$WORK/gh.log"

PASS=0
FAIL=0
OUT="$WORK/out.json"
ERR="$WORK/err.txt"
DIR=""

ok() {
  PASS=$((PASS + 1))
  echo "ok   $1"
}

bad() {
  FAIL=$((FAIL + 1))
  echo "FAIL $1: expected [$2] got [$3]"
}

# check <name> <jq filter> <expected>
check() {
  local actual
  actual=$(jq -r "$2" "$OUT")
  if [ "$actual" = "$3" ]; then ok "$1"; else bad "$1" "$3" "$actual"; fi
}

# check_no <name> <jq boolean filter that must be false>
check_no() {
  check "$1" "$2" false
}

# new_repo: bare origin, clone on main with one commit, origin/HEAD set, cwd = clone.
new_repo() {
  DIR=$(mktemp -d "$WORK/t.XXXXXX")
  git init -q --bare -b main "$DIR/origin.git"
  git clone -q "$DIR/origin.git" "$DIR/repo" 2> /dev/null
  cd "$DIR/repo"
  git checkout -q -b main
  echo base > README.md
  git add README.md
  git commit -q -m "initial"
  git push -q -u origin main
  git remote set-head origin main
  : > "$FAKE_GH_LOG"
  unset FAKE_GH_PR_JSON FAKE_GH_PR_ERR FAKE_GH_DEFAULT
}

# feature <branch>: create the branch, commit one file, push it with upstream.
feature() {
  git checkout -q -b "$1"
  echo feature > feature.txt
  git add feature.txt
  git commit -q -m "add feature"
  git push -q -u origin "$1"
}

# run_gather [args]: run gather.sh in the current repo; stdout to $OUT, stderr to $ERR.
run_gather() {
  "$BASH" "$GATHER" "$@" > "$OUT" 2> "$ERR" || {
    echo "gather.sh exited non-zero: $(cat "$ERR")" >&2
    return 1
  }
  jq -e . "$OUT" > /dev/null
}

# expect_fail <name> <stderr substring> [args]: gather.sh must exit 2 and mention the substring.
expect_fail() {
  local name="$1" needle="$2" code=0
  shift 2
  "$BASH" "$GATHER" "$@" > "$OUT" 2> "$ERR" || code=$?
  if [ "$code" -ne 2 ]; then
    bad "$name: exit code" 2 "$code"
  elif grep -qF -- "$needle" "$ERR"; then
    ok "$name"
  else
    bad "$name: stderr" "contains [$needle]" "$(cat "$ERR")"
  fi
}

# --- base moved ahead: upstream commits must not show up -------------------------------------
new_repo
feature feature/moved
other="$DIR/other"
git clone -q "$DIR/origin.git" "$other" 2> /dev/null
(cd "$other" && echo upstream > upstream.txt && git add upstream.txt && git commit -q -m "upstream change" && git push -q origin main)
run_gather --base main
check "base moved: only own commits" '.commit_count' 1
check "base moved: commit subject" '.commits[0] | endswith("add feature")' true
check "base moved: files" '.files | join(",")' "feature.txt"
check "base moved: diff omits upstream file" '.diff | contains("upstream.txt")' false
check "base moved: fetch picked up the new base" '.base' main

# --- no-network: no fetch, no gh calls ------------------------------------------------------
(cd "$other" && echo more > more.txt && git add more.txt && git commit -q -m "more upstream" && git push -q origin main)
: > "$FAKE_GH_LOG"
run_gather --no-network
check "no-network: base from origin/HEAD" '.base_source' origin-head
check "no-network: no gh calls" '.pr' null
if [ ! -s "$FAKE_GH_LOG" ]; then ok "no-network: gh never called"; else bad "no-network: gh never called" "empty log" "$(cat "$FAKE_GH_LOG")"; fi
before=$(git rev-parse origin/main)
AUTOPR_NO_NETWORK=1 run_gather
if [ "$(git rev-parse origin/main)" = "$before" ]; then ok "no-network env: origin/main not fetched"; else bad "no-network env" "$before" "$(git rev-parse origin/main)"; fi

# --- uncommitted edits excluded and flagged -------------------------------------------------
new_repo
feature feature/dirty
run_gather --base main
check_no "clean tree: uncommitted false" '.uncommitted'
echo "edited but uncommitted" >> feature.txt
echo scratch > scratch.txt
run_gather --base main
check "dirty tree: uncommitted true" '.uncommitted' true
check "dirty tree: edit not in diff" '.diff | contains("edited but uncommitted")' false
check "dirty tree: untracked not in files" '.files | join(",")' "feature.txt"

# --- unpushed commits and upstream status ---------------------------------------------------
new_repo
feature feature/pushed
run_gather --base main
check "pushed: has_upstream" '.has_upstream' true
check "pushed: upstream name" '.upstream' origin/feature/pushed
check "pushed: unpushed_count 0" '.unpushed_count' 0
echo two > two.txt
git add two.txt
git commit -q -m "second commit"
run_gather --base main
check "unpushed: count" '.unpushed_count' 1
check "unpushed: commits still counted" '.commit_count' 2

new_repo
git checkout -q -b feature/local-only
echo x > x.txt
git add x.txt
git commit -q -m "local only"
run_gather --base main
check_no "no upstream: has_upstream" '.has_upstream'
check "no upstream: upstream null" '.upstream' null
check "no upstream: unpushed_count null" '.unpushed_count' null

# --- ticket keys ----------------------------------------------------------------------------
ticket_case() { # <branch> <expected key or null>
  new_repo
  feature "$1"
  run_gather --base main
  check "ticket candidate: $1" '.ticket_candidate' "$2"
}
ticket_case "task/TLAB-2023" TLAB-2023
ticket_case "feature/tlab-2023-new-login" TLAB-2023
ticket_case "bugfix/ab2c-45-crash" AB2C-45
ticket_case "TLAB-7" TLAB-7
ticket_case "feature/no-ticket-here" null
ticket_case "feature/1234-numbers-only" null
ticket_case "release/v2" null
ticket_case "release/v1-2" null
ticket_case "dependabot/npm_and_yarn/lodash-4.17.21" null
ticket_case "renovate/node-20.x" null
ticket_case "update-deps-2024" DEPS-2024 # kept as a candidate: SKILL.md verifies it with acli

# --- lockfile and generated-file exclusion --------------------------------------------------
new_repo
git checkout -q -b feature/locks
mkdir -p app/generated
echo 'real code change' > app/code.kt
echo '{"lock":1}' > package-lock.json
echo 'lock' > app/yarn.lock
echo 'lock' > Cargo.lock
echo 'gen' > app/generated/Api.kt
echo 'min' > app/site.min.js
git add -A
git commit -q -m "code and locks"
git push -q -u origin feature/locks
run_gather --base main
check "locks: all files listed" '.file_count' 6
check "locks: real code in diff" '.diff | contains("real code change")' true
check "locks: package-lock not in diff" '.diff | contains("package-lock.json")' false
check "locks: nested yarn.lock not in diff" '.diff | contains("yarn.lock")' false
check "locks: Cargo.lock not in diff" '.diff | contains("Cargo.lock")' false
check "locks: generated dir not in diff" '.diff | contains("generated/Api.kt")' false
check "locks: minified js not in diff" '.diff | contains("site.min.js")' false
check "locks: excluded files reported" '.diff_excluded_files | length' 5

# --- truncation flag ------------------------------------------------------------------------
new_repo
git checkout -q -b feature/big
seq 1 100 > big.txt
git add big.txt
git commit -q -m "big file"
git push -q -u origin feature/big
run_gather --base main --max-diff-lines 20
check "truncation: flagged" '.truncated' true
check "truncation: diff cut to limit" '.diff | split("\n") | map(select(length > 0)) | length' 20
check "truncation: full length reported" '.diff_lines > 100' true
run_gather --base main
check_no "truncation: not flagged under the limit" '.truncated'
check "size: insertions" '.insertions' 100
check "size: deletions" '.deletions' 0

# --- PR template discovery ------------------------------------------------------------------
template_case() { # <path> ; creates the file on the feature branch
  new_repo
  git checkout -q -b feature/tpl
  mkdir -p "$(dirname "$1")"
  printf '## Summary\n<!-- Describe your changes -->\n' > "$1"
  echo x > x.txt
  git add -A
  git commit -q -m "template"
  git push -q -u origin feature/tpl
  run_gather --base main
  check "template: $1 path" '.template.path' "$1"
  check "template: $1 content" '.template.content | contains("Describe your changes")' true
}
template_case ".github/pull_request_template.md"
template_case ".github/PULL_REQUEST_TEMPLATE.md"
template_case "pull_request_template.md"
template_case "PULL_REQUEST_TEMPLATE.md"
template_case "docs/pull_request_template.md"
template_case "docs/PULL_REQUEST_TEMPLATE.md"
template_case ".github/PULL_REQUEST_TEMPLATE/default.md"

new_repo
feature feature/notpl
run_gather --base main
check "template: none" '.template' null

new_repo
git checkout -q -b feature/tpl-order
mkdir -p .github docs
echo github > .github/pull_request_template.md
echo docs > docs/pull_request_template.md
mkdir -p .github/PULL_REQUEST_TEMPLATE
echo a > .github/PULL_REQUEST_TEMPLATE/a.md
echo b > .github/PULL_REQUEST_TEMPLATE/b.md
git add -A
git commit -q -m "templates"
git push -q -u origin feature/tpl-order
run_gather --base main
check "template: .github wins over docs" '.template.path' ".github/pull_request_template.md"
check "template: directory templates listed" '.other_templates | join(",")' ".github/PULL_REQUEST_TEMPLATE/a.md,.github/PULL_REQUEST_TEMPLATE/b.md"

# --- base resolution ------------------------------------------------------------------------
new_repo
git checkout -q -b develop
git push -q -u origin develop
feature feature/base
export FAKE_GH_DEFAULT=develop
run_gather
check "base: gh default branch" '.base' develop
check "base: gh default source" '.base_source' gh-default-branch

export FAKE_GH_PR_JSON='{"number":9,"url":"https://github.com/o/r/pull/9","title":"T","body":"B","isDraft":true,"baseRefName":"main","state":"OPEN"}'
run_gather
check "base: existing PR beats gh default" '.base' main
check "base: existing PR source" '.base_source' pull-request
check "pr: number" '.pr.number' 9
check "pr_lookup: found for an open PR" '.pr_lookup' found
check "pr: draft" '.pr.isDraft' true
check "pr: state field not exposed" '.pr | has("state")' false

run_gather --base develop
check "base: argument beats PR" '.base' develop
check "base: argument source" '.base_source' argument

unset FAKE_GH_PR_JSON FAKE_GH_DEFAULT
run_gather
check "base: gh offline falls back to origin/HEAD" '.base' main
check "base: origin/HEAD source" '.base_source' origin-head
check "base: gh failure warned" '.warnings | map(select(startswith("gh repo view failed"))) | length' 1

git remote set-head origin -d > /dev/null
run_gather --no-network
check "base: common-name fallback" '.base' main
check "base: common-name source" '.base_source' common-name

if "$BASH" "$GATHER" --no-network --base nope > "$OUT" 2> "$ERR"; then
  bad "base: unknown base fails" "exit 2" "exit 0"
else
  ok "base: unknown base fails"
fi

# --- gh behaviour --------------------------------------------------------------------------
new_repo
feature feature/gh
export FAKE_GH_PR_ERR="error connecting to api.github.com"
expect_fail "gh pr view error is fatal" "gh pr view failed" --base main
expect_fail "gh pr view error names the sandbox" "outside the sandbox" --base main
export FAKE_GH_PR_ERR="Get https://api.github.com: x509: certificate signed by unknown authority"
expect_fail "gh x509 error is fatal" "x509" --base main
if grep -qF -- "--no-network" "$ERR"; then bad "gh error message: no --no-network hint" "no hint" "$(cat "$ERR")"; else ok "gh error message: no --no-network hint"; fi
run_gather --base main --no-network
check "gh error skipped with --no-network" '.pr' null
check "pr_lookup: skipped with --no-network" '.pr_lookup' skipped
unset FAKE_GH_PR_ERR

run_gather --base main
check "gh: no PR is not a warning" '.warnings | length' 0
check "gh: no PR gives null" '.pr' null
check "pr_lookup: none when gh finds no PR" '.pr_lookup' none

export FAKE_GH_PR_JSON='{"number":4,"url":"u","title":"T","body":"B","isDraft":false,"baseRefName":"main","state":"MERGED"}'
run_gather --base main
check "gh: merged PR treated as none" '.pr' null
check "pr_lookup: none for a merged PR" '.pr_lookup' none
check "gh: merged PR warned" '.warnings | map(select(contains("MERGED"))) | length' 1
unset FAKE_GH_PR_JSON

# --- large stat: no SIGPIPE from head ------------------------------------------------------
new_repo
git checkout -q -b feature/huge
deep="app/src/main/java/com/league/feature/subfeature/module/implementation/internal/very/long/package/name"
mkdir -p "$deep"
for i in $(seq 1 800); do echo "val a$i = $i" > "$deep/GeneratedLookingFile$i.kt"; done
git add -A
git commit -q -m "many files"
git push -q -u origin feature/huge
run_gather --base main
check "large stat: file count" '.file_count' 800
check "large stat: stat capped" '.stat | split("\n") | map(select(length > 0)) | length' 100
check "large stat: summary line kept" '.stat | split("\n") | map(select(length > 0)) | last | contains("800 files changed")' true

# --- fetch failure is fatal -----------------------------------------------------------------
new_repo
feature feature/fetchfail
git remote set-url origin "$DIR/missing.git"
expect_fail "fetch failure is fatal" "git fetch" --base main
if grep -qF -- "--no-network" "$ERR"; then bad "fetch error message: no --no-network hint" "no hint" "$(cat "$ERR")"; else ok "fetch error message: no --no-network hint"; fi
run_gather --base main --no-network
check "fetch skipped with --no-network" '.base' main

# --- shallow and single-branch clones -------------------------------------------------------
new_repo
feature feature/clone
git clone -q --depth 1 --branch feature/clone "file://$DIR/origin.git" "$DIR/shallow" 2> /dev/null
cd "$DIR/shallow"
expect_fail "shallow clone: clear message" "git fetch --unshallow" --base main
cd "$DIR/repo"
git clone -q --single-branch --branch feature/clone "file://$DIR/origin.git" "$DIR/single" 2> /dev/null
cd "$DIR/single"
run_gather --base main
check "single-branch clone: base fetched" '.commit_count' 1

# --- no origin remote -----------------------------------------------------------------------
new_repo
feature feature/noorigin
git remote remove origin
expect_fail "no origin: clear message" "no remote named origin" --base main
expect_fail "no origin: checked before the base" "no remote named origin"

# --- non-ASCII paths ------------------------------------------------------------------------
new_repo
git checkout -q -b feature/unicode
echo a > "café.txt"
echo b > "日本語.txt"
git add -A
git commit -q -m "unicode names"
git push -q -u origin feature/unicode
run_gather --base main
check "unicode: file list not escaped" '.files | index("café.txt") != null and index("日本語.txt") != null' true
check "unicode: diff header not escaped" '.diff | contains("a/café.txt") or contains("b/café.txt")' true

# --- upstream named after another branch ----------------------------------------------------
new_repo
git checkout -q -b feat/from-main origin/main
echo x > x.txt
git add x.txt
git commit -q -m "branched from origin/main"
run_gather --base main
check_no "upstream mismatch: has_upstream" '.has_upstream'
check "upstream mismatch: configured upstream reported" '.upstream' origin/main
check "upstream mismatch: unpushed unknown" '.unpushed_count' null
check "upstream mismatch: warned" '.warnings | map(select(contains("git push -u origin feat/from-main"))) | length' 1
git push -q -u origin feat/from-main
run_gather --base main
check "upstream fixed by push -u" '.has_upstream' true
check "upstream fixed: nothing unpushed" '.unpushed_count' 0

# --- upstream on a remote other than origin -------------------------------------------------
new_repo
feature feature/forked
git init -q --bare -b main "$DIR/fork.git"
git remote add fork "$DIR/fork.git"
git push -q -u fork feature/forked 2> /dev/null
run_gather --base main
check_no "fork upstream: has_upstream" '.has_upstream'
check "fork upstream: configured upstream reported" '.upstream' fork/feature/forked
check "fork upstream: unpushed unknown" '.unpushed_count' null
check "fork upstream: warning names the remote" '.warnings | map(select(contains("fork") and contains("git push -u origin feature/forked"))) | length' 1

# --- linked issues from closing keywords ----------------------------------------------------
new_repo
echo history > history.txt
git add history.txt
git commit -q -m "Closes #99 on the base branch only"
git push -q origin main
git checkout -q -b feature/linked
echo one > one.txt
git add one.txt
git commit -q -m "Add one" -m "Closes #12"
echo two > two.txt
git add two.txt
git commit -q -m "Fixes #7 and something else"
echo three > three.txt
git add three.txt
git commit -q -m "Add three (#44)" -m "Resolved: #30. Unfixed #9 stays out. Fix #12 again."
echo four > four.txt
git add four.txt
git commit -q -m "Add four" -m "Fix #13abc and closes #14x, then fixes #15, and resolves #16."
git push -q -u origin feature/linked
run_gather --base main
check "linked issues: closing keywords, sorted, unique" '.linked_issues | join(",")' "7,12,15,16,30"
check "linked issues: digits glued to letters rejected" '.linked_issues | index(13) == null and index(14) == null' true
check "linked issues: base commits and bare refs ignored" '.linked_issues | index(99) == null and index(44) == null and index(9) == null' true

new_repo
feature feature/unlinked
run_gather --base main
check "linked issues: none" '.linked_issues | length' 0

# --- branch and base names that are unsafe in a shell command -------------------------------
# shellcheck disable=SC2016 # the names must stay literal
DOLLAR_BRANCH='feature/a$b'
# shellcheck disable=SC2016
DOLLAR_BASE='release/x$y'
new_repo
git checkout -q -b "$DOLLAR_BRANCH"
echo x > x.txt
git add x.txt
git commit -q -m "dollar in the branch name"
git push -q -u origin "$DOLLAR_BRANCH"
expect_fail "unsafe branch name rejected" "unsafe" --base main
git checkout -q -b 'feature/a`b'
git push -q -u origin 'feature/a`b'
expect_fail "backtick in the branch name rejected" "unsafe" --base main
git checkout -q feature/a_b.c-1 2> /dev/null || git checkout -q -b feature/a_b.c-1
git push -q -u origin feature/a_b.c-1
run_gather --base main
check "safe branch name accepted" '.branch' feature/a_b.c-1
git branch -q "$DOLLAR_BASE" origin/main
git push -q origin "$DOLLAR_BASE"
expect_fail "unsafe base name rejected" "unsafe" --base "$DOLLAR_BASE"

# --- names that start with # or - and non-ASCII names ---------------------------------------
new_repo
git checkout -q -b '#lead'
echo x > x.txt
git add x.txt
git commit -q -m "leading hash"
git push -q -u origin '#lead'
expect_fail "leading # in the branch name rejected" "not starting with # or -" --base main
new_repo
feature feature/dash
git update-ref refs/heads/-x HEAD
git symbolic-ref HEAD refs/heads/-x
expect_fail "leading - in the branch name rejected" "not starting with # or -" --base main
git symbolic-ref HEAD refs/heads/feature/dash
expect_fail "leading # in the base name rejected" "not starting with # or -" --base '#lead'
expect_fail "leading - in the base name rejected" "not starting with # or -" --base -x
new_repo
git checkout -q -b "feature/café"
echo x > x.txt
git add x.txt
git commit -q -m "accent"
git push -q -u origin "feature/café"
expect_fail "non-ASCII name rejected" "ASCII letters, digits and ._/@+#%,:=~-" --base main
if grep -qF "characters a shell would expand" "$ERR"; then bad "refusal message: old wording gone" "no old wording" "$(cat "$ERR")"; else ok "refusal message: old wording gone"; fi

# --- option validation ----------------------------------------------------------------------
expect_fail "max-diff-lines 0 rejected" "positive integer" --max-diff-lines 0
expect_fail "max-diff-lines text rejected" "positive integer" --max-diff-lines abc

# --- argument errors ------------------------------------------------------------------------
new_repo
feature feature/args
if "$BASH" "$GATHER" --bogus > "$OUT" 2> "$ERR"; then bad "args: unknown flag fails" "exit 2" "exit 0"; else ok "args: unknown flag fails"; fi
git checkout -q --detach
if "$BASH" "$GATHER" --no-network --base main > "$OUT" 2> "$ERR"; then bad "detached HEAD fails" "exit 2" "exit 0"; else ok "detached HEAD fails"; fi

echo
echo "passed: $PASS, failed: $FAIL"
[ "$FAIL" -eq 0 ]
