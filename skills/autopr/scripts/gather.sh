#!/usr/bin/env bash
# Collect the git and GitHub context for one PR and print it as a single JSON object.
#
# Usage: gather.sh [--base <branch>] [--no-network] [--max-diff-lines <n>]
#   --base <branch>        base branch; overrides the existing PR and the repo default
#   --no-network           skip git fetch and every gh call (also AUTOPR_NO_NETWORK=1)
#   --max-diff-lines <n>   cut the diff after n lines (default 1200, also AUTOPR_MAX_DIFF_LINES)
#
# Read-only: never commits, pushes or edits files. Exit 2 on a fatal error (message on stderr).
set -euo pipefail

BASE_ARG=""
NO_NETWORK="${AUTOPR_NO_NETWORK:-0}"
MAX_DIFF_LINES="${AUTOPR_MAX_DIFF_LINES:-1200}"
MAX_DIFF_BYTES=200000
MAX_STAT_LINES=100

die() {
  echo "gather.sh: $*" >&2
  exit 2
}

while [ $# -gt 0 ]; do
  case "$1" in
    --base)
      [ $# -ge 2 ] || die "--base needs a branch name"
      BASE_ARG="$2"
      shift 2
      ;;
    --no-network)
      NO_NETWORK=1
      shift
      ;;
    --max-diff-lines)
      [ $# -ge 2 ] || die "--max-diff-lines needs a number"
      MAX_DIFF_LINES="$2"
      shift 2
      ;;
    *) die "unknown argument: $1" ;;
  esac
done

case "$MAX_DIFF_LINES" in
  '' | *[!0-9]*) die "--max-diff-lines must be a positive integer" ;;
esac

command -v git > /dev/null 2>&1 || die "git is not installed"
command -v jq > /dev/null 2>&1 || die "jq is not installed"
ROOT=$(git rev-parse --show-toplevel 2> /dev/null) || die "not inside a git repository"
cd "$ROOT"

TMP=$(mktemp -d "${TMPDIR:-/tmp}/autopr-gather.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
: > "$TMP/warnings"

warn() {
  printf '%s\n' "$*" >> "$TMP/warnings"
}

lines_json() {
  jq -Rn '[inputs | select(length > 0)]'
}

# Succeeds when directory $1 holds an entry named exactly $2 (case-sensitive, also on macOS).
has_exact() {
  local entry
  [ -d "$1" ] || return 1
  for entry in "$1"/* "$1"/.[!.]*; do
    [ -e "$entry" ] && [ "${entry##*/}" = "$2" ] && return 0
  done
  return 1
}

BRANCH=$(git branch --show-current)
[ -n "$BRANCH" ] || die "detached HEAD: check out the branch first"

# Ticket key: first case-insensitive KEY-123 token that starts at a word edge, upper-cased.
TICKET=""
if [[ $BRANCH =~ (^|[^A-Za-z0-9])([A-Za-z][A-Za-z0-9]+-[0-9]+) ]]; then
  TICKET=$(printf '%s' "${BASH_REMATCH[2]}" | tr '[:lower:]' '[:upper:]')
fi

HAVE_GH=0
if [ "$NO_NETWORK" != 1 ]; then
  if command -v gh > /dev/null 2>&1; then
    HAVE_GH=1
  else
    warn "gh is not installed: PR and default-branch lookups skipped"
  fi
fi

# Existing PR for the current branch (gh resolves fork PRs; no argument).
echo null > "$TMP/pr.json"
PR_BASE=""
if [ "$HAVE_GH" = 1 ]; then
  if GH_PROMPT_DISABLED=1 gh pr view --json number,url,title,body,isDraft,baseRefName,state \
    > "$TMP/pr.raw" 2> "$TMP/pr.err"; then
    PR_STATE=$(jq -r .state "$TMP/pr.raw")
    if [ "$PR_STATE" = OPEN ]; then
      jq -c 'del(.state)' "$TMP/pr.raw" > "$TMP/pr.json"
      PR_BASE=$(jq -r .baseRefName "$TMP/pr.json")
    else
      warn "latest PR for this branch is $PR_STATE: treated as no existing PR"
    fi
  elif ! grep -qi 'no pull requests found' "$TMP/pr.err"; then
    warn "gh pr view failed: $(head -n 1 "$TMP/pr.err")"
  fi
fi

# Base branch: --base > existing PR > repo default (gh) > origin/HEAD > main/master/develop.
BASE=""
BASE_SOURCE=""
if [ -n "$BASE_ARG" ]; then
  BASE="$BASE_ARG"
  BASE_SOURCE="argument"
elif [ -n "$PR_BASE" ]; then
  BASE="$PR_BASE"
  BASE_SOURCE="pull-request"
fi
if [ -z "$BASE" ] && [ "$HAVE_GH" = 1 ]; then
  if BASE=$(GH_PROMPT_DISABLED=1 gh repo view --json defaultBranchRef --jq .defaultBranchRef.name 2> "$TMP/repo.err") \
    && [ -n "$BASE" ]; then
    BASE_SOURCE="gh-default-branch"
  else
    BASE=""
    warn "gh repo view failed: $(head -n 1 "$TMP/repo.err")"
  fi
fi
if [ -z "$BASE" ]; then
  if HEAD_REF=$(git symbolic-ref --short refs/remotes/origin/HEAD 2> /dev/null); then
    BASE="${HEAD_REF#origin/}"
    BASE_SOURCE="origin-head"
  fi
fi
if [ -z "$BASE" ]; then
  for candidate in main master develop; do
    if git show-ref --verify --quiet "refs/remotes/origin/$candidate"; then
      BASE="$candidate"
      BASE_SOURCE="common-name"
      break
    fi
  done
fi
[ -n "$BASE" ] || die "cannot determine the base branch: pass --base <branch>"

git remote get-url origin > /dev/null 2>&1 || die "no remote named origin"

if [ "$NO_NETWORK" != 1 ]; then
  if ! git fetch --quiet origin "$BASE" 2> "$TMP/fetch.err"; then
    warn "git fetch origin $BASE failed, using the last known origin/$BASE: $(head -n 1 "$TMP/fetch.err")"
  fi
fi
git rev-parse --verify --quiet "refs/remotes/origin/$BASE^{commit}" > /dev/null \
  || die "origin/$BASE not found: fetch it or pass a different --base"

RANGE="origin/$BASE...HEAD"

git log --no-decorate --format='%h %s' "origin/$BASE..HEAD" | lines_json > "$TMP/commits.json"
git diff --no-renames --name-only "$RANGE" | lines_json > "$TMP/files.json"
git diff --no-renames --stat=120 "$RANGE" | head -n "$MAX_STAT_LINES" > "$TMP/stat.txt"
git diff --no-renames --numstat "$RANGE" > "$TMP/numstat.txt"
INSERTIONS=$(awk '$1 ~ /^[0-9]+$/ { n += $1 } END { print n + 0 }' "$TMP/numstat.txt")
DELETIONS=$(awk '$2 ~ /^[0-9]+$/ { n += $2 } END { print n + 0 }' "$TMP/numstat.txt")

# Lockfiles and generated files stay in the file list but not in the diff.
EXCLUDE_GLOBS=(
  '**/*.lock' '**/*.lockfile' '**/package-lock.json' '**/npm-shrinkwrap.json' '**/pnpm-lock.yaml'
  '**/*.min.js' '**/*.min.css' '**/*.map' '**/generated/**' '**/*.pb.go' '**/*_pb2.py'
)
INCLUDE_SPECS=()
EXCLUDE_SPECS=()
for g in "${EXCLUDE_GLOBS[@]}"; do
  INCLUDE_SPECS+=(":(glob)$g")
  EXCLUDE_SPECS+=(":(exclude,glob)$g")
done
git diff --no-renames --name-only "$RANGE" -- "${INCLUDE_SPECS[@]}" | lines_json > "$TMP/excluded.json"

git diff --no-renames --no-color "$RANGE" -- . "${EXCLUDE_SPECS[@]}" > "$TMP/diff.full"
DIFF_LINES=$(wc -l < "$TMP/diff.full" | tr -d ' ')
TRUNCATED=false
head -n "$MAX_DIFF_LINES" "$TMP/diff.full" > "$TMP/diff.txt"
[ "$DIFF_LINES" -gt "$MAX_DIFF_LINES" ] && TRUNCATED=true
if [ "$(wc -c < "$TMP/diff.txt" | tr -d ' ')" -gt "$MAX_DIFF_BYTES" ]; then
  head -c "$MAX_DIFF_BYTES" "$TMP/diff.txt" > "$TMP/diff.cut"
  mv "$TMP/diff.cut" "$TMP/diff.txt"
  TRUNCATED=true
fi

# Upstream status of the current branch.
HAS_UPSTREAM=false
UPSTREAM=""
UNPUSHED=null
if UPSTREAM=$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2> /dev/null); then
  HAS_UPSTREAM=true
  UNPUSHED=$(git rev-list --count '@{u}..HEAD')
else
  UPSTREAM=""
fi

UNCOMMITTED=false
[ -n "$(git status --porcelain)" ] && UNCOMMITTED=true

# PR template: first match in a fixed order; other .github/PULL_REQUEST_TEMPLATE/*.md listed separately.
TEMPLATE_PATH=""
for dir in .github . docs; do
  for name in pull_request_template.md PULL_REQUEST_TEMPLATE.md; do
    if has_exact "$dir" "$name"; then
      if [ "$dir" = . ]; then TEMPLATE_PATH="$name"; else TEMPLATE_PATH="$dir/$name"; fi
      break 2
    fi
  done
done
: > "$TMP/templates.list"
if has_exact .github PULL_REQUEST_TEMPLATE; then
  for f in .github/PULL_REQUEST_TEMPLATE/*.md; do
    [ -f "$f" ] && printf '%s\n' "$f" >> "$TMP/templates.list"
  done
fi
if [ -z "$TEMPLATE_PATH" ] && [ -s "$TMP/templates.list" ]; then
  TEMPLATE_PATH=$(head -n 1 "$TMP/templates.list")
fi
if [ -n "$TEMPLATE_PATH" ]; then
  cp "$TEMPLATE_PATH" "$TMP/template.md"
else
  : > "$TMP/template.md"
fi
grep -Fxv -- "$TEMPLATE_PATH" "$TMP/templates.list" | lines_json > "$TMP/other-templates.json" || echo '[]' > "$TMP/other-templates.json"
lines_json < "$TMP/warnings" > "$TMP/warnings.json"

jq -n \
  --arg branch "$BRANCH" \
  --arg ticket "$TICKET" \
  --arg base "$BASE" \
  --arg base_source "$BASE_SOURCE" \
  --slurpfile commits "$TMP/commits.json" \
  --slurpfile files "$TMP/files.json" \
  --slurpfile excluded "$TMP/excluded.json" \
  --rawfile stat "$TMP/stat.txt" \
  --rawfile diff "$TMP/diff.txt" \
  --argjson diff_lines "$DIFF_LINES" \
  --argjson truncated "$TRUNCATED" \
  --argjson insertions "$INSERTIONS" \
  --argjson deletions "$DELETIONS" \
  --argjson has_upstream "$HAS_UPSTREAM" \
  --arg upstream "$UPSTREAM" \
  --argjson unpushed "$UNPUSHED" \
  --argjson uncommitted "$UNCOMMITTED" \
  --arg template_path "$TEMPLATE_PATH" \
  --rawfile template_content "$TMP/template.md" \
  --slurpfile other_templates "$TMP/other-templates.json" \
  --slurpfile pr "$TMP/pr.json" \
  --slurpfile warnings "$TMP/warnings.json" \
  '{
    branch: $branch,
    ticket: (if $ticket == "" then null else $ticket end),
    base: $base,
    base_source: $base_source,
    commit_count: ($commits[0] | length),
    commits: $commits[0],
    file_count: ($files[0] | length),
    files: $files[0],
    insertions: $insertions,
    deletions: $deletions,
    stat: $stat,
    diff: $diff,
    diff_lines: $diff_lines,
    truncated: $truncated,
    diff_excluded_files: $excluded[0],
    has_upstream: $has_upstream,
    upstream: (if $upstream == "" then null else $upstream end),
    unpushed_count: $unpushed,
    uncommitted: $uncommitted,
    template: (if $template_path == "" then null else {path: $template_path, content: $template_content} end),
    other_templates: $other_templates[0],
    pr: $pr[0],
    warnings: $warnings[0]
  }'
