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
{
  printf '#!%s\n' "$BASH"
  cat << 'FAKE_EOF'
echo "$*" >> "${FAKE_GH_LOG:-/dev/null}"
# Like gh: --jq <expr> filters the JSON output.
jq_expr=""
prev=""
for arg in "$@"; do
  if [ "$prev" = --jq ]; then jq_expr="$arg"; fi
  prev="$arg"
done
if [ -n "$jq_expr" ] && [ -z "${FAKE_GH_FILTERED:-}" ]; then
  FAKE_GH_FILTERED=1 "$0" "$@" | jq -r "$jq_expr"
  exit "${PIPESTATUS[0]}"
fi
# Which repository real gh uses when no --repo is given: a remote named upstream, else origin.
repo_of() { sed -E -e 's#^.*[:/]([^/:]+)/([^/]+)$#\1/\2#' -e 's#\.git$##'; }
self=$(git remote get-url origin 2> /dev/null | repo_of)
if url=$(git remote get-url upstream 2> /dev/null); then resolved=$(printf '%s' "$url" | repo_of); else resolved="$self"; fi
arg_repo=""
head_arg=""
state_arg="open"
limit_arg="30"
prev=""
for arg in "$@"; do
  case "$prev" in --repo | -R) arg_repo="$arg" ;; --head) head_arg="$arg" ;; --state) state_arg="$arg" ;; --limit) limit_arg="$arg" ;; esac
  prev="$arg"
done
resolved="${arg_repo:-$resolved}"
# A renamed repository: gh follows the redirect and answers with the new repository's data.
if [ -n "${FAKE_GH_REDIRECT_FROM:-}" ] && [ "$resolved" = "$FAKE_GH_REDIRECT_FROM" ]; then resolved="$FAKE_GH_REDIRECT_TO"; fi
case "$1 $2" in
  "pr view" | "pr list")
    if [ -n "${FAKE_GH_PR_ERR:-}" ]; then echo "$FAKE_GH_PR_ERR" >&2; exit 1; fi
    for failing in ${FAKE_GH_FAIL_REPOS:-}; do
      if [ "$failing" = "$resolved" ]; then echo "error connecting to api.github.com" >&2; exit 1; fi
    done
    for gone in ${FAKE_GH_NOTFOUND_REPOS:-}; do
      if [ "$gone" = "$resolved" ]; then echo "GraphQL: Could not resolve to a Repository with the name '$gone'. (repository)" >&2; exit 1; fi
    done
    # Fake PRs (FAKE_GH_PRS, a JSON array, or the single FAKE_GH_PR_JSON) live in the repository
    # named by their URL and are found only there.
    if [ -n "${FAKE_GH_PRS:-}" ]; then prs="$FAKE_GH_PRS"; elif [ -n "${FAKE_GH_PR_JSON:-}" ]; then prs="[$FAKE_GH_PR_JSON]"; else prs="[]"; fi
    here=$(jq -c --arg r "$resolved" --arg h "$head_arg" \
      '[.[] | select((.url | sub("^https?://[^/]+/"; "") | sub("/pull/.*$"; "")) == $r and (($h == "") or .headRefName == $h))]' <<< "$prs")
    if [ "$1 $2" = "pr list" ]; then
      # Like gh: the state filter applies first, then the limit cuts the list.
      jq -c --arg st "$state_arg" --argjson lim "$limit_arg" \
        '[.[] | select($st == "all" or ($st == "open" and .state == "OPEN") or ($st == "closed" and .state == "CLOSED") or ($st == "merged" and .state == "MERGED"))] | .[:$lim]' <<< "$here"
      exit 0
    fi
    case "${3:-}" in
      '' | -*) number="" ;;
      *) number="$3" ;;
    esac
    if [ -n "$number" ]; then
      found=$(jq -c --argjson n "$number" --arg r "$resolved" \
        '[.[] | select(.number == $n and ((.url | sub("^https?://[^/]+/"; "") | sub("/pull/.*$"; "")) == $r))] | first // empty' <<< "$prs")
      if [ -n "$found" ]; then printf '%s' "$found"; exit 0; fi
      echo "Could not resolve to a PullRequest with the number of $number. (repository.pullRequest)" >&2
      exit 1
    fi
    if [ "$(jq length <<< "$here")" -gt 0 ]; then jq -c '.[0]' <<< "$here"; exit 0; fi
    echo 'no pull requests found for branch "x"' >&2
    exit 1
    ;;
  "repo set-default")
    if [ -n "${FAKE_GH_SET_DEFAULT:-}" ]; then echo "$FAKE_GH_SET_DEFAULT"; exit 0; fi
    echo "X No default remote repository has been set. To learn more about the default repository, run: gh repo set-default --help"
    exit 0
    ;;
  "repo view")
    target="${3:-}"
    case "$target" in -* | "") target="$resolved" ;; esac
    if [ "$target" != "$self" ]; then # another repository: its canonical name and default branch
      for missing in ${FAKE_GH_MISSING:-}; do
        if [ "$missing" = "${3:-}" ]; then echo "GraphQL: Could not resolve to a Repository with the name '$missing'. (repository)" >&2; exit 1; fi
      done
      empty_json='{}' # not written inline: bash 3.2 keeps the backslash in ${VAR:-{\}}
      base_json="${FAKE_GH_PARENT_JSON:-$empty_json}"
      if [ -n "${FAKE_GH_REDIRECT_FROM:-}" ] && [ "$target" = "$FAKE_GH_REDIRECT_FROM" ]; then target="$FAKE_GH_REDIRECT_TO"; fi
      jq -c --arg n "$target" '. + {nameWithOwner: $n}' <<< "$base_json"
      exit 0
    fi
    if [ -n "${FAKE_GH_REPO_JSON:-}" ]; then printf '%s' "$FAKE_GH_REPO_JSON"; exit 0; fi
    if [ -n "${FAKE_GH_DEFAULT:-}" ]; then
      printf '{"nameWithOwner":"%s","parent":null,"defaultBranchRef":{"name":"%s"}}' "$self" "$FAKE_GH_DEFAULT"
      exit 0
    fi
    echo "error connecting to api.github.com" >&2
    exit 1
    ;;
esac
exit 1
FAKE_EOF
} > "$FAKEBIN/gh"
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
  unset FAKE_GH_NOTFOUND_REPOS FAKE_GH_FAIL_REPOS FAKE_GH_MISSING FAKE_GH_REDIRECT_FROM FAKE_GH_REDIRECT_TO FAKE_GH_PR_JSON FAKE_GH_PRS FAKE_GH_PR_ERR FAKE_GH_DEFAULT FAKE_GH_REPO_JSON FAKE_GH_PARENT_JSON FAKE_GH_SET_DEFAULT
}

# feature <branch>: create the branch, commit one file, push it with upstream.
feature() {
  git checkout -q -b "$1"
  echo feature > feature.txt
  git add feature.txt
  git commit -q -m "add feature"
  git push -q -u origin "$1"
}

# run_gather_in_path <dir> [args]: run_gather with <dir> first on PATH (a wrapper around git).
run_gather_in_path() {
  local PATH="$1:$PATH"
  shift
  run_gather "$@"
}

# expect_fail_in_path <dir> <name> <needle> [args]: expect_fail with <dir> first on PATH.
expect_fail_in_path() {
  local PATH="$1:$PATH"
  shift
  expect_fail "$@"
}

# expect <name> <expected> <actual>
expect() {
  if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "$2" "$3"; fi
}

# origin_repo: owner/repo of the origin remote, as gather.sh derives it from the URL.
origin_repo() {
  git remote get-url origin | sed -E -e 's#^.*[:/]([^/:]+)/([^/]+)$#\1/\2#' -e 's#\.git$##'
}

# pr_json <number> <draft> <base> <state> <head oid> [repo the PR is in] [head owner]:
# JSON the fake gh prints for `pr view` and `pr list` (the PR's head is the current branch).
pr_json() {
  local branch owner
  branch=$(git branch --show-current)
  owner="${7:-$(origin_repo | cut -d/ -f1)}"
  printf '{"number":%s,"url":"https://github.com/%s/pull/%s","title":"T","body":"B","isDraft":%s,"baseRefName":"%s","state":"%s","headRefOid":"%s","headRefName":"%s","headRepositoryOwner":{"login":"%s"}}' \
    "$1" "${6:-$(origin_repo)}" "$1" "$2" "$3" "$4" "$5" "$branch" "$owner"
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

FAKE_GH_PR_JSON=$(pr_json 9 true main OPEN "$(git rev-parse HEAD)")
export FAKE_GH_PR_JSON
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
expect_fail "gh pr list error is fatal" "gh pr list for" --base main
expect_fail "gh pr list error names the sandbox" "outside the sandbox" --base main
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

FAKE_GH_PR_JSON=$(pr_json 4 false main MERGED "$(git rev-parse HEAD)")
export FAKE_GH_PR_JSON
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

# --- head publication guard -----------------------------------------------------------------
new_repo
feature feature/sync
sha=$(git rev-parse HEAD)
run_gather --base main
check "head sync: in sync" '.head_in_sync' true
check "head sync: status" '.head_status' in-sync
check "head sync: remote head reported" '.remote_head' "$sha"
run_gather --base main --no-network
check "head sync: unknown with --no-network" '.head_in_sync' null
check "head sync: status skipped with --no-network" '.head_status' skipped

echo more > more.txt
git add more.txt
git commit -q -m "local only"
run_gather --base main
check_no "head sync: local ahead is not in sync" '.head_in_sync'
check "head sync: local ahead status" '.head_status' local-ahead
git push -q origin feature/sync

# another clone pushes to the branch: remote ahead of the local HEAD
other_clone="$DIR/other2"
git clone -q "$DIR/origin.git" "$other_clone" 2> /dev/null
(cd "$other_clone" && git checkout -q feature/sync && echo remote > remote.txt && git add remote.txt && git commit -q -m "remote commit" && git push -q origin feature/sync)
run_gather --base main
check_no "head sync: remote ahead is not in sync" '.head_in_sync'
check "head sync: remote ahead status" '.head_status' remote-ahead
check "head sync: unpushed count stays 0 (the old blind spot)" '.unpushed_count' 0

# local HEAD reset to an ancestor of the remote head
git fetch -q origin
git reset -q --hard origin/feature/sync
git reset -q --hard HEAD~1
run_gather --base main
check "head sync: reset to an ancestor is caught" '.head_status' remote-ahead
check "head sync: reset keeps unpushed_count 0" '.unpushed_count' 0

# remote force-updated: neither side contains the other
git fetch -q origin
git reset -q --hard origin/feature/sync
(cd "$other_clone" && git reset -q --hard HEAD~1 && echo rewritten > rewritten.txt && git add rewritten.txt && git commit -q -m "rewritten" && git push -q --force origin feature/sync)
run_gather --base main
check "head sync: force-updated remote" '.head_status' diverged
check_no "head sync: diverged is not in sync" '.head_in_sync'

# remote branch deleted
git push -q origin --delete feature/sync
run_gather --base main
check "head sync: deleted remote head" '.head_status' remote-missing
# A git whose messages are not English must not change the answer: this wrapper translates the
# one sentence an English-text check would look for.
GERMAN_BIN="$WORK/german-bin"
mkdir -p "$GERMAN_BIN"
cat > "$GERMAN_BIN/git" << GERMAN_EOF
#!$BASH
err=\$(mktemp "\${TMPDIR:-/tmp}/german-git.XXXXXX")
"$(command -v git)" "\$@" 2> "\$err"
rc=\$?
sed -e "s/couldn't find remote ref/Remote-Referenz konnte nicht gefunden werden:/" "\$err" >&2
rm -f "\$err"
exit \$rc
GERMAN_EOF
chmod +x "$GERMAN_BIN/git"
run_gather_in_path "$GERMAN_BIN" --base main
check "head sync: deleted remote head under a non-English git" '.head_status' remote-missing
check "head sync: deleted remote head has no sha" '.remote_head' null
check_no "head sync: deleted is not in sync" '.head_in_sync'

# the PR head must match too
new_repo
feature feature/prhead
sha=$(git rev-parse HEAD)
FAKE_GH_PR_JSON=$(pr_json 5 false main OPEN "$sha")
export FAKE_GH_PR_JSON
run_gather
check "head sync: PR head matches" '.head_status' in-sync
FAKE_GH_PR_JSON=$(pr_json 5 false main OPEN 0000000000000000000000000000000000000000)
export FAKE_GH_PR_JSON
run_gather
check "head sync: PR head differs" '.head_status' pr-head-mismatch
check_no "head sync: PR head mismatch is not in sync" '.head_in_sync'
unset FAKE_GH_PR_JSON

# --- fork workflow: the base comes from the base repository, not from origin ----------------
new_fork() {
  DIR=$(mktemp -d "$WORK/f.XXXXXX")
  mkdir -p "$DIR/acme" "$DIR/me"
  git init -q --bare -b main "$DIR/acme/lib.git"
  git clone -q "$DIR/acme/lib.git" "$DIR/seed" 2> /dev/null
  (cd "$DIR/seed" && git checkout -q -b main && echo base > README.md && git add README.md && git commit -q -m "initial" && git push -q origin main)
  git clone -q --bare "$DIR/acme/lib.git" "$DIR/me/lib.git" 2> /dev/null
  git clone -q "$DIR/me/lib.git" "$DIR/repo" 2> /dev/null
  # upstream moves ahead; the fork's main stays stale
  (cd "$DIR/seed" && echo u1 > u1.txt && git add u1.txt && git commit -q -m "upstream one" && echo u2 > u2.txt && git add u2.txt && git commit -q -m "upstream two" && git push -q origin main)
  cd "$DIR/repo"
  git remote add upstream "$DIR/acme/lib.git"
  git fetch -q upstream
  git checkout -q -b feature/fork upstream/main
  git branch -q --unset-upstream
  echo own > own.txt
  git add own.txt
  git commit -q -m "own change"
  git push -q -u origin feature/fork
  : > "$FAKE_GH_LOG"
  unset FAKE_GH_PR_JSON FAKE_GH_PR_ERR FAKE_GH_DEFAULT
  export FAKE_GH_REPO_JSON='{"nameWithOwner":"me/lib","parent":{"name":"lib","owner":{"login":"acme"}},"defaultBranchRef":{"name":"main"}}'
  export FAKE_GH_PARENT_JSON='{"defaultBranchRef":{"name":"main"}}'
}

new_fork
run_gather
check "fork: base repo is the parent" '.base_repo' acme/lib
check "fork: head repo is origin" '.head_repo' me/lib
check "fork: base remote found by URL match" '.base_remote' upstream
check "fork: default branch comes from the parent" '.base' main
check "fork: only own commits (fork main is stale)" '.commit_count' 1
check "fork: files" '.files | join(",")' own.txt
check "fork: diff omits upstream files" '.diff | contains("u1.txt") or contains("u2.txt")' false
check "fork: no warnings" '.warnings | length' 0
check "fork: head in sync" '.head_in_sync' true
check "fork without a PR or default: target needs confirmation" '.base_repo_source' needs-confirmation

git remote remove upstream
run_gather
check "fork: no matching remote, fetched by URL" '.commit_count' 1
check "fork: base remote null without a match" '.base_remote' null
check "fork: warning names the fetch" '.warnings | map(select(contains("no local remote"))) | length' 1

git remote add upstream "$DIR/acme/lib.git"
git fetch -q upstream
FAKE_GH_PR_JSON=$(pr_json 3 false main OPEN "$(git rev-parse HEAD)" acme/lib)
export FAKE_GH_PR_JSON
unset FAKE_GH_REPO_JSON
run_gather
check "fork: base repo read from the PR URL" '.base_repo' acme/lib
check "fork: PR URL source" '.base_repo_source' pull-request
check "fork: PR base diff is right" '.commit_count' 1
unset FAKE_GH_PR_JSON

export FAKE_GH_REPO_JSON='{"nameWithOwner":"me/lib","parent":{"name":"lib","owner":{"login":"acme"}},"defaultBranchRef":{"name":"main"}}'
run_gather --no-network
check "fork: --no-network keeps the origin base" '.base_remote' origin
check "fork: --no-network has no base repo" '.base_repo' null
unset FAKE_GH_REPO_JSON FAKE_GH_PARENT_JSON

new_repo
feature feature/plain
export FAKE_GH_DEFAULT=main
run_gather
check "no fork: base repo equals head repo" '.base_repo == .head_repo' true
check "no fork: base remote is origin" '.base_remote' origin
check "no fork: base repo source is origin" '.base_repo_source' origin
unset FAKE_GH_DEFAULT

# --- gh without --repo resolves to the upstream remote: every lookup must name its repo -----
new_fork
sha=$(git rev-parse HEAD)
FAKE_GH_PR_JSON=$(pr_json 7 false main OPEN "$sha" me/lib me)
export FAKE_GH_PR_JSON
run_gather
check "upstream remote: PR in the fork is found without --repo" '.pr_lookup' found
check "upstream remote: PR number" '.pr.number' 7
check "upstream remote: base repo is the fork the PR is in" '.base_repo' me/lib
check "upstream remote: source is the PR" '.base_repo_source' pull-request
run_gather --repo me/lib
check "upstream remote: PR found with --repo me/lib" '.pr.number' 7
run_gather --repo acme/lib
check "upstream remote: a PR in the fork is not the PR into acme/lib" '.pr_lookup' none
check "upstream remote: --repo acme/lib is the argument" '.base_repo_source' argument
FAKE_GH_PR_JSON=$(pr_json 3 false main OPEN "$sha" acme/lib me)
export FAKE_GH_PR_JSON
run_gather
check "upstream remote: PR from the fork into the parent is found" '.pr.number' 3
check "upstream remote: its base repo is the parent" '.base_repo' acme/lib
FAKE_GH_PR_JSON=$(pr_json 4 false main OPEN "$sha" acme/lib someone-else)
export FAKE_GH_PR_JSON
run_gather
check "upstream remote: a PR from another fork with the same branch name is not ours" '.pr_lookup' none
unset FAKE_GH_PR_JSON
run_gather
check "upstream remote: no PR still needs confirmation" '.base_repo_source' needs-confirmation
check "upstream remote: every gh call names a repository" '[.] | length' 1
if grep -E '^(pr|repo view|issue)' "$FAKE_GH_LOG" | grep -vE -- '(--repo|-R) |^repo view [A-Za-z0-9._-]+/[A-Za-z0-9._-]+ '; then
  bad "gh calls: all name their repository" "no gh call without --repo or an explicit repo" "$(cat "$FAKE_GH_LOG")"
else
  ok "gh calls: all name their repository"
fi

# --- open PRs in both the fork and the parent: ask, never pick one --------------------------
new_fork
sha=$(git rev-parse HEAD)
fork_pr=$(pr_json 7 false main OPEN "$sha" me/lib me)
parent_pr=$(pr_json 42 false main OPEN "$sha" acme/lib me)
export FAKE_GH_PRS="[$fork_pr,$parent_pr]"
run_gather
check "two open PRs: ambiguous" '.pr_lookup' ambiguous
check "two open PRs: no pr is chosen" '.pr' null
check "two open PRs: both listed" '.open_prs | map(.number) | sort | join(",")' "7,42"
check "two open PRs: each names its repo" '.open_prs | map(.repo) | sort | join(",")' "acme/lib,me/lib"
check "two open PRs: base branch listed" '.open_prs | map(.baseRefName) | unique | join(",")' main
check "two open PRs: url listed" '.open_prs | map(.url | startswith("https://github.com/")) | all' true
run_gather --repo acme/lib
check "--repo parent narrows to the parent PR" '.pr_lookup' found
check "--repo parent: number" '.pr.number' 42
check "--repo parent: the full list is still reported" '.open_prs | length' 2
check "--repo parent: the PR left out is warned about" '.warnings | map(select(contains("not selected"))) | length' 1
run_gather --repo me/lib
check "--repo fork narrows to the fork PR" '.pr.number' 7
parent_merged=$(pr_json 42 false main MERGED "$sha" acme/lib me)
export FAKE_GH_PRS="[$fork_pr,$parent_merged]"
run_gather
check "one open and one merged PR: found" '.pr_lookup' found
check "one open and one merged PR: the open one" '.pr.number' 7
check "one open and one merged PR: only open PRs are listed" '.open_prs | length' 1
check "one open and one merged PR: merged one warned" '.warnings | map(select(contains("MERGED"))) | length' 1
export FAKE_GH_PRS='[]'
run_gather
check "no open PR: none" '.pr_lookup' none
check "no open PR: empty list" '.open_prs | length' 0
run_gather --no-network
check "no network: skipped and no list" '.open_prs | length' 0
unset FAKE_GH_PRS

# --- two open PRs from one branch in the same repository (different bases) ------------------
new_repo
feature feature/twobases
git push -q origin main:release
sha=$(git rev-parse HEAD)
pr_main=$(pr_json 7 false main OPEN "$sha")
pr_release=$(pr_json 8 false release OPEN "$sha")
export FAKE_GH_PRS="[$pr_main,$pr_release]"
run_gather
check "same repo, two bases: ambiguous" '.pr_lookup' ambiguous
check "same repo, two bases: both listed with their base" '.open_prs | map("\(.number):\(.baseRefName)") | sort | join(",")' "7:main,8:release"
run_gather --base release
check "--base never selects a PR: still ambiguous" '.pr_lookup' ambiguous
check "--base release: no PR is chosen" '.pr' null
check "--base release: both PRs are listed" '.open_prs | length' 2
run_gather --base main
check "--base main: still ambiguous" '.pr_lookup' ambiguous
run_gather --pr 7
check "--pr 7: found" '.pr_lookup' found
check "--pr 7: the PR" '.pr.number' 7
check "--pr 7: the full list is still reported" '.open_prs | length' 2
check "--pr 7: base repo from the PR" '.base_repo_source' pull-request
run_gather --pr 8 --base release
check "--pr 8 with --base release: found" '.pr.number' 8
run_gather --pr 8 --base main
check "--pr beats --base: the PR is chosen by number" '.pr.number' 8
expect_fail "--pr of a PR that is not open from this branch exits 2" "not an open PR from this branch" --pr 99
for bad in 0 -1 abc 1.5 ''; do
  expect_fail "--pr '$bad' is rejected" "positive integer" --pr "$bad"
done
export FAKE_GH_PRS="[$pr_main]"
run_gather --base release
check "--base alone does not hide a single PR (the PR base can change)" '.pr.number' 7
run_gather --pr 7 --no-network
check "--pr is ignored with --no-network" '.warnings | map(select(contains("--pr"))) | length' 1
unset FAKE_GH_PRS

# --- fork PR #7 (base main) and parent PR #42 (base release): --base must not pick one -------
new_fork
(cd "$DIR/seed" && git push -q origin main:release)
sha=$(git rev-parse HEAD)
fork_pr=$(pr_json 7 false main OPEN "$sha" me/lib me)
parent_pr=$(pr_json 42 false release OPEN "$sha" acme/lib me)
export FAKE_GH_PRS="[$fork_pr,$parent_pr]"
run_gather --base release
check "fork #7@main + parent #42@release, --base release: ambiguous" '.pr_lookup' ambiguous
check "--base release does not hide the fork PR" '.open_prs | map(.number) | sort | join(",")' "7,42"
check "--base release selects nothing" '.pr' null
run_gather --pr 42 --repo acme/lib
check "--pr 42 --repo parent: found" '.pr.number' 42
check "--pr 42 --repo parent: the other PR is still listed" '.open_prs | map(.number) | sort | join(",")' "7,42"
run_gather --pr 42 --repo acme/lib --base release
check "--pr 42 with --base release: the base is the argument" '.base_source' argument
unset FAKE_GH_PRS

# --- --repo: the warning names only the PRs left out; a renamed repository is canonicalized ---
new_fork
sha=$(git rev-parse HEAD)
fork_pr=$(pr_json 7 false main OPEN "$sha" me/lib me)
parent_pr=$(pr_json 42 false main OPEN "$sha" acme/lib me)
export FAKE_GH_PRS="[$fork_pr,$parent_pr]"
run_gather --repo acme/lib
check "--repo parent: warning names the fork PR" '.warnings | map(select(contains("not selected") and contains("#7 "))) | length' 1
check "--repo parent: warning does not name the selected PR" '.warnings | map(select(contains("not selected") and contains("#42"))) | length' 0
run_gather --repo me/lib
check "--repo fork: warning names the parent PR" '.warnings | map(select(contains("not selected") and contains("#42"))) | length' 1
check "--repo fork: warning does not name the selected PR" '.warnings | map(select(contains("not selected") and contains("#7 "))) | length' 0
export FAKE_GH_REDIRECT_FROM=oldacme/lib FAKE_GH_REDIRECT_TO=acme/lib
run_gather --repo oldacme/lib
check "--repo with a renamed repository's old name: found" '.pr_lookup' found
check "--repo old name: the PR in the new name" '.pr.number' 42
check "--repo old name: base repo is the canonical name" '.base_repo' acme/lib
check "--repo old name: the open PR fixes the base repo" '.base_repo_source' pull-request
check "--repo old name: the rename is warned about" '.warnings | map(select(contains("is now named acme/lib"))) | length' 1
run_gather --pr 42 --repo oldacme/lib
check "--pr with --repo old name: found" '.pr.number' 42
check "--pr with --repo old name: base repo" '.base_repo' acme/lib
unset FAKE_GH_REDIRECT_FROM FAKE_GH_REDIRECT_TO
export FAKE_GH_MISSING="nope/missing"
expect_fail "--repo that does not exist exits 2" "could not find" --repo nope/missing
unset FAKE_GH_MISSING FAKE_GH_PRS

# --- the result cap must not hide an open PR ------------------------------------------------
new_repo
feature feature/capped
sha=$(git rev-parse HEAD)
me_pr=$(pr_json 7 false main OPEN "$sha")
origin_name=$(origin_repo)
# 60 newer closed PRs from other forks with this branch name, then mine
others=$(jq -nc --arg repo "$origin_name" --arg b feature/capped '
  [range(0; 60) | {number: (2000 + .), url: "https://github.com/\($repo)/pull/\(2000 + .)", title: "x", body: "", isDraft: false, baseRefName: "main", headRefOid: "0", headRefName: $b, headRepositoryOwner: {login: "closer\(.)"}, state: "CLOSED"}]')
FAKE_GH_PRS=$(jq -c --argjson mine "$me_pr" '. + [$mine]' <<< "$others")
export FAKE_GH_PRS
run_gather
check "cap: an open PR behind 60 closed ones is found" '.pr.number' 7
# 101 open PRs from other forks, then mine
others_open=$(jq -nc --arg repo "$origin_name" --arg b feature/capped '
  [range(0; 101) | {number: (3000 + .), url: "https://github.com/\($repo)/pull/\(3000 + .)", title: "x", body: "", isDraft: false, baseRefName: "main", headRefOid: "0", headRefName: $b, headRepositoryOwner: {login: "forker\(.)"}, state: "OPEN"}]')
FAKE_GH_PRS=$(jq -c --argjson mine "$me_pr" '. + [$mine]' <<< "$others_open")
export FAKE_GH_PRS
expect_fail "cap: a full page is never treated as complete" "too many PRs for this branch name"
run_gather --pr 7
check "cap: --pr finds the PR without listing" '.pr.number' 7
check "cap: --pr gives found" '.pr_lookup' found
expect_fail "cap: --pr of a PR that does not exist exits 2" "not an open PR from this branch" --pr 9999
unset FAKE_GH_PRS

# --- a failed lookup in any candidate repository stops the run ------------------------------
new_fork
sha=$(git rev-parse HEAD)
FAKE_GH_PRS="[$(pr_json 7 false main OPEN "$sha" me/lib me)]"
export FAKE_GH_PRS
export FAKE_GH_FAIL_REPOS="acme/lib"
expect_fail "only the second repository fails: exit 2" "gh pr list for acme/lib failed"
run_gather --no-network
check "--no-network skips the lookups, so no failure" '.pr_lookup' skipped
unset FAKE_GH_FAIL_REPOS FAKE_GH_PRS

# --- origin transferred to another owner: the head owner is the canonical one ----------------
new_repo
feature feature/transferred
sha=$(git rev-parse HEAD)
old_owner=$(origin_repo | cut -d/ -f1)
repo_name=$(origin_repo | cut -d/ -f2)
export FAKE_GH_REPO_JSON="{\"nameWithOwner\":\"neworg/$repo_name\",\"parent\":null,\"defaultBranchRef\":{\"name\":\"main\"}}"
FAKE_GH_PRS="[$(pr_json 5 false main OPEN "$sha" "neworg/$repo_name" neworg)]"
export FAKE_GH_PRS
run_gather
check "origin transfer: the PR from the new owner is found" '.pr.number' 5
check "origin transfer: head repo is the canonical name" '.head_repo' "neworg/$repo_name"
check "origin transfer: warned about the URL" ".warnings | map(select(contains(\"neworg/$repo_name\") and contains(\"$old_owner\"))) | length" 1
run_gather --pr 5
check "origin transfer: --pr finds it too" '.pr.number' 5
check "origin transfer: base repo is origin's repository" '.base_repo' "neworg/$repo_name"
unset FAKE_GH_REPO_JSON FAKE_GH_PRS

# --- the fork base ref is private to the run and gone afterwards ----------------------------
new_fork
REAL_GIT=$(command -v git)
LOGGIT="$WORK/loggit"
mkdir -p "$LOGGIT"
cat > "$LOGGIT/git" << LOGGIT_EOF
#!$BASH
printf '%s\\n' "\$*" >> "$WORK/git-calls.log"
exec "$REAL_GIT" "\$@"
LOGGIT_EOF
chmod +x "$LOGGIT/git"
: > "$WORK/git-calls.log"
run_gather_in_path "$LOGGIT"
check "private base ref: the run sees only its own commit" '.commit_count' 1
run_gather_in_path "$LOGGIT"
refs=$(grep -o ':refs/autopr/[A-Za-z0-9_-]*' "$WORK/git-calls.log" | sort -u)
expect "private base ref: two runs used two different refs" 2 "$(printf '%s\n' "$refs" | grep -c .)"
if printf '%s\n' "$refs" | grep -qx ':refs/autopr/base'; then bad "private base ref: no shared name" "no refs/autopr/base" "$refs"; else ok "private base ref: no shared name"; fi
expect "private base ref: nothing is left after the runs" "" "$(git for-each-ref refs/autopr)"

# --- SSH failures say so, and say how to get past them --------------------------------------
new_repo
feature feature/sshfail
SSHFAIL="$WORK/sshfail-bin"
mkdir -p "$SSHFAIL"
cat > "$SSHFAIL/git" << SSHFAIL_EOF
#!$BASH
# Fails fetch (or ls-remote, when FAKE_SSH_FAIL=ls-remote) like a broken ssh-agent does.
cmd="\$1"
if [ "\$cmd" = "-c" ]; then cmd="\$3"; fi
if [ "\$cmd" = "\${FAKE_SSH_FAIL:-fetch}" ]; then
  echo 'sign_and_send_pubkey: signing failed for RSA "/home/u/.ssh/id_rsa" from agent: communication with agent failed' >&2
  echo 'git@github.com: Permission denied (publickey).' >&2
  echo 'fatal: Could not read from remote repository.' >&2
  exit 128
fi
exec "$(command -v git)" "\$@"
SSHFAIL_EOF
chmod +x "$SSHFAIL/git"
expect_fail_in_path "$SSHFAIL" "ssh failure on the base fetch: names SSH" "SSH" --base main
expect_fail_in_path "$SSHFAIL" "ssh failure: suggests the ssh-agent" "ssh-agent" --base main
expect_fail_in_path "$SSHFAIL" "ssh failure: shows the HTTPS rewrite" "GIT_CONFIG_COUNT=2 GIT_CONFIG_KEY_0=url.https://github.com/.insteadOf GIT_CONFIG_VALUE_0=git@github.com: GIT_CONFIG_KEY_1=credential.helper GIT_CONFIG_VALUE_1='!gh auth git-credential'" --base main
expect_fail_in_path "$SSHFAIL" "ssh failure: says it is per command, not a config edit" "this command only" --base main
FAKE_SSH_FAIL=ls-remote expect_fail_in_path "$SSHFAIL" "ssh failure on the head check: names SSH" "SSH" --base main
FAKE_SSH_FAIL=ls-remote expect_fail_in_path "$SSHFAIL" "ssh failure on the head check: names ls-remote" "ls-remote" --base main
# a dead local remote is not an SSH problem
git remote set-url origin "$DIR/missing.git"
expect_fail "a dead local remote does not mention SSH" "git fetch origin main failed" --base main
if grep -q "SSH" "$ERR"; then bad "a dead local remote: no SSH hint" "no SSH hint" "$(cat "$ERR")"; else ok "a dead local remote: no SSH hint"; fi

# --- a stale extra remote must not break every run -------------------------------------------
new_repo
feature feature/stale
sha=$(git rev-parse HEAD)
git remote add stale "$DIR/gone/proj.git"
export FAKE_GH_NOTFOUND_REPOS="gone/proj"
run_gather
check "stale remote, repo not found: the run continues" '.pr_lookup' none
check "stale remote: one warning names the remote" '.warnings | map(select(contains("remote '"'"'stale'"'"' points at gone/proj"))) | length' 1
check "stale remote: the warning says how to fix it" '.warnings | map(select(contains("git remote remove stale") and contains("cannot find or you cannot see"))) | length' 1
FAKE_GH_PRS="[$(pr_json 7 false main OPEN "$sha")]"
export FAKE_GH_PRS
run_gather
check "stale remote with an open PR: found" '.pr.number' 7
check "stale remote with an open PR: still warned" '.warnings | map(select(contains("remote '"'"'stale'"'"'"))) | length' 1
run_gather --pr 7
check "stale remote with --pr: found" '.pr.number' 7
check "stale remote with --pr: still warned" '.warnings | map(select(contains("remote '"'"'stale'"'"'"))) | length' 1
FAKE_GH_DEFAULT=main run_gather --repo "$(origin_repo)"
check "stale remote with --repo: the run continues (--repo does not hide the warning)" '.pr.number' 7
unset FAKE_GH_NOTFOUND_REPOS
export FAKE_GH_FAIL_REPOS="gone/proj"
expect_fail "stale remote, transient error: exit 2" "remote 'stale'"
expect_fail "stale remote, transient error: says how to fix it" "git remote remove stale"
unset FAKE_GH_FAIL_REPOS FAKE_GH_PRS
# origin's own repository, its parent and --repo stay strict, whatever the error
new_fork
export FAKE_GH_NOTFOUND_REPOS="acme/lib"
expect_fail "parent not found: exit 2" "gh pr list for acme/lib failed"
unset FAKE_GH_NOTFOUND_REPOS
export FAKE_GH_NOTFOUND_REPOS="me/lib"
expect_fail "origin repo not found: exit 2" "gh pr list for me/lib failed"
unset FAKE_GH_NOTFOUND_REPOS
new_repo
feature feature/argrepo
export FAKE_GH_NOTFOUND_REPOS="gone/proj"
expect_fail "--repo candidate not found: exit 2" "gh pr list for gone/proj failed" --repo gone/proj
unset FAKE_GH_NOTFOUND_REPOS

# --- the same PR number in the fork and the parent: --pr needs --repo -----------------------
new_fork
sha=$(git rev-parse HEAD)
fork_pr=$(pr_json 7 false main OPEN "$sha" me/lib me)
parent_pr=$(pr_json 7 false main OPEN "$sha" acme/lib me)
export FAKE_GH_PRS="[$fork_pr,$parent_pr]"
expect_fail "--pr in two repositories needs --repo" "several repositories" --pr 7
run_gather --pr 7 --repo acme/lib
check "--pr with --repo: the parent's PR" '.pr.url' https://github.com/acme/lib/pull/7
unset FAKE_GH_PRS

# --- a renamed repository redirects: the same PR must not count twice -----------------------
new_fork
sha=$(git rev-parse HEAD)
git remote set-url upstream "$DIR/oldacme/lib.git"
export FAKE_GH_REDIRECT_FROM=oldacme/lib FAKE_GH_REDIRECT_TO=acme/lib
FAKE_GH_PRS="[$(pr_json 42 false main OPEN "$sha" acme/lib me)]"
export FAKE_GH_PRS
run_gather
check "renamed repo: one PR, not ambiguous" '.pr_lookup' found
check "renamed repo: listed once" '.open_prs | length' 1
check "renamed repo: canonical repo name from the URL" '.open_prs[0].repo' acme/lib
check "renamed repo: the PR" '.pr.number' 42
unset FAKE_GH_PRS FAKE_GH_REDIRECT_FROM FAKE_GH_REDIRECT_TO

# --- which repository a fork PR targets: PR, --repo, gh default, then the parent (confirm) ----
new_fork
run_gather --repo acme/lib
check "--repo: source is the argument" '.base_repo_source' argument
check "--repo: base repo" '.base_repo' acme/lib
check "--repo: only own commits" '.commit_count' 1
run_gather --repo me/lib
check "--repo of the fork itself: base repo" '.base_repo' me/lib
check "--repo of the fork itself: base remote is origin" '.base_remote' origin
check "--repo of the fork itself: source" '.base_repo_source' argument
export FAKE_GH_SET_DEFAULT=acme/lib
run_gather
check "gh default repo is honored" '.base_repo' acme/lib
check "gh default repo: source" '.base_repo_source' gh-default
check "gh default repo: only own commits" '.commit_count' 1
export FAKE_GH_SET_DEFAULT=me/lib
run_gather
check "gh default repo can be the fork" '.base_repo_source' gh-default
check "gh default fork: base repo" '.base_repo' me/lib
unset FAKE_GH_SET_DEFAULT
run_gather --repo acme/lib --no-network
check "--no-network ignores --repo: base repo unknown" '.base_repo' null
check "--no-network ignores --repo: warned" '.warnings | map(select(contains("--repo"))) | length' 1
expect_fail "--repo with a bad shape is rejected" "owner/name" --repo 'acme/lib;x'
for bad in a ../x -x/y .x/y x/.y x/-y /x x/ a/b/c 'a b/c'; do
  expect_fail "--repo '$bad' is rejected" "owner/name" --repo "$bad"
done
run_gather --no-network --repo octo-org/my.repo_1
check "--repo octo-org/my.repo_1 is accepted" '.warnings | map(select(contains("--repo is ignored"))) | length' 1
expect_fail "--repo needs a value" "--repo needs" --repo

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
