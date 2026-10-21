#!/usr/bin/env bash
# Collect the git and GitHub context for one PR and print it as a single JSON object.
#
# Usage: gather.sh [--base <branch>] [--repo <owner/name>] [--no-network] [--max-diff-lines <n>]
#   --base <branch>        base branch; overrides the existing PR and the repo default
#   --repo <owner/name>    repository the PR targets (a fork PR targets the parent); ignored when an
#                          open PR already fixes it, and with --no-network
#   --no-network           skip git fetch and every gh call (also AUTOPR_NO_NETWORK=1)
#   --max-diff-lines <n>   cut the diff after n lines (default 1200, also AUTOPR_MAX_DIFF_LINES)
#
# Read-only: never commits, pushes or edits files. Exit 2 on a fatal error (message on stderr):
# no repo, no origin, detached HEAD, a gh or git fetch failure, or no merge base with the base branch.
# Network runs fetch refs: origin/<base> (or refs/autopr/base for a fork PR) and origin/<branch>.
# A shell pipe that closes early (| head) kills the writer with SIGPIPE under pipefail, so every
# command with long output goes through a temp file instead.
set -euo pipefail

BASE_ARG=""
REPO_ARG=""
NO_NETWORK="${AUTOPR_NO_NETWORK:-0}"
MAX_DIFF_LINES="${AUTOPR_MAX_DIFF_LINES:-1200}"
MAX_DIFF_BYTES=200000
MAX_STAT_LINES=100

die() {
  echo "gather.sh: $*" >&2
  exit 2
}

# True for owner/name: exactly one slash, both parts non-empty, GitHub name characters
# (letters, digits, . _ -), no part starting with - or . (also what keeps it safe in a command).
valid_repo() {
  local LC_ALL=C owner name
  case "$1" in
    */*/* | */ | /* | '') return 1 ;;
    */*) ;;
    *) return 1 ;;
  esac
  owner="${1%%/*}"
  name="${1#*/}"
  case "$owner$name" in
    *[!A-Za-z0-9._-]*) return 1 ;;
  esac
  case "$owner" in -* | .*) return 1 ;; esac
  case "$name" in -* | .*) return 1 ;; esac
  return 0
}

while [ $# -gt 0 ]; do
  case "$1" in
    --base)
      [ $# -ge 2 ] || die "--base needs a branch name"
      BASE_ARG="$2"
      shift 2
      ;;
    --repo)
      [ $# -ge 2 ] || die "--repo needs an owner/name value"
      REPO_ARG="$2"
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

if [ -n "$REPO_ARG" ] && ! valid_repo "$REPO_ARG"; then
  die "--repo must look like owner/name (letters, digits, . _ -)"
fi
case "$MAX_DIFF_LINES" in
  '' | *[!0-9]*) die "--max-diff-lines must be a positive integer" ;;
esac
[ "$MAX_DIFF_LINES" -ge 1 ] || die "--max-diff-lines must be a positive integer"

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

# owner/repo from a remote URL (scp-like, https or a local path ending in owner/repo[.git]).
repo_of_url() {
  printf '%s' "$1" | sed -E -e 's#^.*[:/]([^/:]+)/([^/]+)$#\1/\2#' -e 's#\.git$##'
}

lower() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

# git with unescaped non-ASCII paths in names and diff headers.
qgit() {
  git -c core.quotePath=false "$@"
}

# Branch and base names end up in commands run by the skill. Git allows `$`, backticks and
# backslashes in names, an unquoted leading `#` starts a shell comment and a leading `-` reads as
# a flag, so refuse anything outside a conservative set. LC_ALL=C keeps the ranges ASCII.
require_safe_name() { # <kind> <name>
  local LC_ALL=C
  case "$2" in
    '' | -* | '#'* | *[!A-Za-z0-9._/@+#%,:=~-]*)
      die "unsafe $1 name '$2': allowed characters are ASCII letters, digits and ._/@+#%,:=~- (not starting with # or -). Rename the branch or pass another base."
      ;;
  esac
}

BRANCH=$(git branch --show-current)
[ -n "$BRANCH" ] || die "detached HEAD: check out the branch first"
require_safe_name branch "$BRANCH"
git remote get-url origin > /dev/null 2>&1 || die "no remote named origin: add it or run from a clone"
# head_repo comes from the origin URL itself, never from gh's resolution (gh may resolve a fork
# clone with an upstream remote to the upstream repository).
ORIGIN_URL=$(git remote get-url origin)
HEAD_REPO=$(repo_of_url "$ORIGIN_URL")
if ! valid_repo "$HEAD_REPO"; then
  warn "origin URL does not name an owner/repo: fork detection is off"
  HEAD_REPO=""
fi

# Ticket candidate: first KEY-123 token at a word edge (two or more leading letters, digits not
# followed by a dot), upper-cased. Branch names such as update-deps-2024 also match, so the
# skill must confirm the key with acli before it uses it.
TICKET=""
if [[ $BRANCH =~ (^|[^A-Za-z0-9])([A-Za-z]{2,}[A-Za-z0-9]*-[0-9]+)([^.0-9]|$) ]]; then
  TICKET=$(printf '%s' "${BASH_REMATCH[2]}" | tr '[:lower:]' '[:upper:]')
fi

# pr_lookup: found (open PR), none (gh answered: no open PR), skipped (gh was not asked).
# With "skipped", pr is null because it is unknown, not because it does not exist.
PR_LOOKUP=skipped
HAVE_GH=0
if [ "$NO_NETWORK" != 1 ]; then
  if command -v gh > /dev/null 2>&1; then
    HAVE_GH=1
  else
    warn "gh is not installed: PR and default-branch lookups skipped"
  fi
fi

# gh picks a repository from the remotes when it is not told (a remote named upstream wins over
# origin), so every gh call here names its repository. The one exception is `gh repo set-default
# --view`, which has no --repo flag: it reads the default the user stored.
echo null > "$TMP/pr.json"
PR_BASE=""
VIEW_REPO=""
VIEW_PARENT=""
VIEW_DEFAULT=""
REPO_VIEW_FAILED=""
CANDIDATES=()
add_candidate() { # <owner/repo>: append once, case-insensitively, when it is a valid name
  local c
  valid_repo "$1" || return 0
  for c in "${CANDIDATES[@]+"${CANDIDATES[@]}"}"; do
    [ "$(lower "$c")" = "$(lower "$1")" ] && return 0
  done
  CANDIDATES+=("$1")
}
if [ "$HAVE_GH" = 1 ]; then
  [ -n "$HEAD_REPO" ] || die "origin URL '$ORIGIN_URL' does not name an owner/repo: the GitHub lookups need it"
  if GH_PROMPT_DISABLED=1 gh repo view "$HEAD_REPO" --json nameWithOwner,parent,defaultBranchRef \
    > "$TMP/repo.json" 2> "$TMP/repo.err"; then
    VIEW_REPO=$(jq -r '.nameWithOwner // empty' "$TMP/repo.json")
    VIEW_PARENT=$(jq -r 'if .parent then "\(.parent.owner.login)/\(.parent.name)" else empty end' "$TMP/repo.json")
    VIEW_DEFAULT=$(jq -r '.defaultBranchRef.name // empty' "$TMP/repo.json")
  else
    REPO_VIEW_FAILED=$(head -n 1 "$TMP/repo.err")
  fi

  # Where could this branch's PR live? --repo fixes it. Otherwise: the repository of origin, its
  # parent, and the repository of every other remote (upstream). `gh pr list --head` is the
  # documented filter by head branch name; it cannot take owner:branch, and `gh pr view <branch>`
  # may return a PR from another fork with the same branch name, so the head owner is checked here.
  if [ -n "$REPO_ARG" ]; then
    add_candidate "$REPO_ARG"
  else
    add_candidate "$HEAD_REPO"
    add_candidate "$VIEW_PARENT"
    while IFS= read -r remote; do
      [ "$remote" = origin ] || add_candidate "$(repo_of_url "$(git remote get-url "$remote")")"
    done < <(git remote)
  fi
  HEAD_OWNER="${HEAD_REPO%%/*}"
  FIRST_CANDIDATE=1
  PR_LOOKUP=none
  for candidate in "${CANDIDATES[@]}"; do
    if GH_PROMPT_DISABLED=1 gh pr list --repo "$candidate" --head "$BRANCH" --state all --limit 50 \
      --json number,url,title,body,isDraft,baseRefName,headRefOid,headRefName,headRepositoryOwner,state \
      > "$TMP/pr.list" 2> "$TMP/pr.err"; then
      jq -c --arg b "$BRANCH" --arg o "$(lower "$HEAD_OWNER")" \
        '[.[] | select(.headRefName == $b and ((.headRepositoryOwner.login // "") | ascii_downcase) == $o)]' \
        "$TMP/pr.list" > "$TMP/pr.mine"
      OPEN_PR=$(jq -c '[.[] | select(.state == "OPEN")] | first // empty' "$TMP/pr.mine")
      if [ -n "$OPEN_PR" ] && [ "$PR_LOOKUP" = found ]; then
        warn "another open PR from this branch exists in $candidate: using the first one found"
      elif [ -n "$OPEN_PR" ]; then
        printf '%s\n' "$OPEN_PR" | jq -c '{number, url, title, body, isDraft, baseRefName, headRefOid}' > "$TMP/pr.json"
        PR_BASE=$(jq -r .baseRefName "$TMP/pr.json")
        PR_LOOKUP=found
      else
        OTHER_STATE=$(jq -r 'first | .state // empty' "$TMP/pr.mine")
        [ -z "$OTHER_STATE" ] || warn "latest PR for this branch in $candidate is $OTHER_STATE: treated as no existing PR"
      fi
    elif [ "$FIRST_CANDIDATE" = 1 ]; then
      die "gh pr list for $candidate failed: $(head -n 1 "$TMP/pr.err"). Run this outside the sandbox (a sandbox blocks the GitHub network and keyring) and log in with gh auth login."
    else
      warn "could not list PRs in $candidate: $(head -n 1 "$TMP/pr.err")"
    fi
    FIRST_CANDIDATE=0
  done
fi

# Base repository: the repo the PR targets, with where that answer came from
# (base_repo_source): pull-request (the URL of the open PR), argument (--repo), gh-default
# (gh repo set-default), origin (gh says origin's own repository is the target), or
# needs-confirmation (a repository other than origin's: the parent of a fork, or whatever gh
# resolved: a guess, and the skill must ask before it publishes there). Unknown (null) without gh.
BASE_REPO=""
BASE_REPO_SOURCE=""
REPO_DEFAULT=""
if [ -n "$REPO_ARG" ] && [ "$NO_NETWORK" = 1 ]; then
  warn "--repo is ignored with --no-network: the base repository is not resolved"
fi
if [ "$PR_LOOKUP" = found ]; then
  BASE_REPO=$(jq -r .url "$TMP/pr.json" | sed -nE 's#^https?://[^/]+/([^/]+/[^/]+)/pull/[0-9]+.*$#\1#p')
  BASE_REPO_SOURCE="pull-request"
elif [ "$HAVE_GH" = 1 ]; then
  GH_DEFAULT=$(GH_PROMPT_DISABLED=1 gh repo set-default --view 2> /dev/null || true)
  GH_DEFAULT=${GH_DEFAULT%%$'\n'*}
  if [ -n "$REPO_ARG" ]; then
    BASE_REPO="$REPO_ARG"
    BASE_REPO_SOURCE="argument"
  elif valid_repo "$GH_DEFAULT"; then
    BASE_REPO="$GH_DEFAULT"
    BASE_REPO_SOURCE="gh-default"
  elif [ -n "$VIEW_PARENT" ] && valid_repo "$VIEW_PARENT"; then
    BASE_REPO="$VIEW_PARENT"
    BASE_REPO_SOURCE="needs-confirmation"
  elif [ -n "$VIEW_REPO" ]; then
    BASE_REPO="$VIEW_REPO"
    if [ -n "$HEAD_REPO" ] && [ "$(lower "$VIEW_REPO")" = "$(lower "$HEAD_REPO")" ]; then
      BASE_REPO_SOURCE="origin"
    else
      BASE_REPO_SOURCE="needs-confirmation"
    fi
  fi
  # The default branch of the chosen repository, only needed when nothing else names the base.
  if [ -z "$BASE_ARG" ] && [ -n "$BASE_REPO" ] && valid_repo "$BASE_REPO"; then
    if [ "$(lower "$BASE_REPO")" = "$(lower "$VIEW_REPO")" ]; then
      REPO_DEFAULT="$VIEW_DEFAULT"
    elif GH_PROMPT_DISABLED=1 gh repo view "$BASE_REPO" --json defaultBranchRef > "$TMP/parent.json" 2> /dev/null; then
      REPO_DEFAULT=$(jq -r '.defaultBranchRef.name // empty' "$TMP/parent.json")
    fi
  fi
fi
if [ -n "$BASE_REPO" ] && ! valid_repo "$BASE_REPO"; then
  warn "ignoring base repository '$BASE_REPO': not an owner/repo name"
  BASE_REPO=""
  BASE_REPO_SOURCE=""
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
if [ -z "$BASE" ] && [ -n "$REPO_DEFAULT" ]; then
  BASE="$REPO_DEFAULT"
  BASE_SOURCE="gh-default-branch"
fi
if [ -z "$BASE" ] && [ -n "$REPO_VIEW_FAILED" ]; then
  warn "gh repo view failed: $REPO_VIEW_FAILED"
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
require_safe_name base "$BASE"

# Fetch the base. Normally origin holds it (the explicit refspec also stores origin/<base> in
# single-branch clones). When the PR targets another repository (a fork PR: origin is the fork),
# fetch the base from a remote that points at that repository, or by URL, into refs/autopr/base,
# so a stale fork branch never shapes the diff.
BASE_REMOTE=origin
BASE_REF="origin/$BASE"
if [ "$NO_NETWORK" != 1 ] && [ -n "$BASE_REPO" ] && [ -n "$HEAD_REPO" ] && [ "$(lower "$BASE_REPO")" != "$(lower "$HEAD_REPO")" ]; then
  BASE_REMOTE=""
  while IFS= read -r remote; do
    if [ "$(lower "$(repo_of_url "$(git remote get-url "$remote")")")" = "$(lower "$BASE_REPO")" ]; then
      BASE_REMOTE="$remote"
      break
    fi
  done < <(git remote)
  if [ -n "$BASE_REMOTE" ]; then
    FETCH_FROM="$BASE_REMOTE"
  else
    FETCH_FROM=$(printf '%s' "$ORIGIN_URL" | sed -E "s#^(.*[:/])[^/:]+/[^/]+\$#\1$BASE_REPO.git#")
    warn "no local remote points at $BASE_REPO: fetched $BASE from $FETCH_FROM"
  fi
  git fetch --quiet "$FETCH_FROM" "+refs/heads/$BASE:refs/autopr/base" 2> "$TMP/fetch.err" \
    || die "git fetch $FETCH_FROM $BASE failed: $(head -n 1 "$TMP/fetch.err"). Run this outside the sandbox and check the network and the remote."
  BASE_REF="refs/autopr/base"
elif [ "$NO_NETWORK" != 1 ]; then
  git fetch --quiet origin "+refs/heads/$BASE:refs/remotes/origin/$BASE" 2> "$TMP/fetch.err" \
    || die "git fetch origin $BASE failed: $(head -n 1 "$TMP/fetch.err"). Run this outside the sandbox and check the network and the remote."
fi
git rev-parse --verify --quiet "$BASE_REF^{commit}" > /dev/null \
  || die "$BASE_REF not found: fetch it or pass a different --base"
if ! git merge-base "$BASE_REF" HEAD > /dev/null 2>&1; then
  if [ "$(git rev-parse --is-shallow-repository)" = true ]; then
    die "no merge base with $BASE_REF in this shallow clone: run git fetch --unshallow, then run again"
  fi
  die "no merge base between HEAD and $BASE_REF: the branches share no history, check --base"
fi

RANGE="$BASE_REF...HEAD"

qgit log --no-decorate --format='%h %s' "$BASE_REF..HEAD" | lines_json > "$TMP/commits.json"
# Issues the branch closes: "closes|fixes|resolves #N" (any tense, optional colon, digits must end
# at a word boundary) in its commit messages. Bare #N is ignored: it is usually a PR number, as in
# "Add feature (#7)".
git log --format=%B "$BASE_REF..HEAD" > "$TMP/messages.txt"
{ grep -Eio '(^|[^[:alnum:]])(close[sd]?|fix(e[sd])?|resolve[sd]?):? +#[0-9]+([^[:alnum:]]|$)' "$TMP/messages.txt" || true; } \
  | { grep -Eo '#[0-9]+' || true; } | tr -d '#' | sort -nu \
  | jq -Rn '[inputs | select(length > 0) | tonumber]' > "$TMP/linked.json"
qgit diff --no-renames --name-only "$RANGE" | lines_json > "$TMP/files.json"
qgit diff --no-renames --stat=120 "$RANGE" > "$TMP/stat.full"
if [ "$(wc -l < "$TMP/stat.full" | tr -d ' ')" -le "$MAX_STAT_LINES" ]; then
  cp "$TMP/stat.full" "$TMP/stat.txt"
else
  { head -n $((MAX_STAT_LINES - 1)) "$TMP/stat.full"; tail -n 1 "$TMP/stat.full"; } > "$TMP/stat.txt"
fi
qgit diff --no-renames --numstat "$RANGE" > "$TMP/numstat.txt"
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
qgit diff --no-renames --name-only "$RANGE" -- "${INCLUDE_SPECS[@]}" | lines_json > "$TMP/excluded.json"

qgit diff --no-renames --no-color "$RANGE" -- . "${EXCLUDE_SPECS[@]}" > "$TMP/diff.full"
DIFF_LINES=$(wc -l < "$TMP/diff.full" | tr -d ' ')
TRUNCATED=false
head -n "$MAX_DIFF_LINES" "$TMP/diff.full" > "$TMP/diff.txt"
[ "$DIFF_LINES" -gt "$MAX_DIFF_LINES" ] && TRUNCATED=true
if [ "$(wc -c < "$TMP/diff.txt" | tr -d ' ')" -gt "$MAX_DIFF_BYTES" ]; then
  head -c "$MAX_DIFF_BYTES" "$TMP/diff.txt" > "$TMP/diff.cut"
  mv "$TMP/diff.cut" "$TMP/diff.txt"
  TRUNCATED=true
fi

# Publication guard: is the head the PR shows the head this checkout describes? Fetch the head
# branch, then compare the remote tip with HEAD (and with the PR's head when a PR exists).
# head_in_sync is true, false, or null when the network was skipped.
HEAD_SHA=$(git rev-parse HEAD)
REMOTE_HEAD=""
HEAD_STATUS="skipped"
if [ "$NO_NETWORK" != 1 ]; then
  # ls-remote tells whether the branch exists without parsing git's (translated) messages.
  if git ls-remote --heads origin "refs/heads/$BRANCH" > "$TMP/ls-remote.txt" 2> "$TMP/ls-remote.err"; then
    BRANCH_ON_REMOTE=$(awk -F'\t' -v ref="refs/heads/$BRANCH" '$2 == ref { found = 1 } END { print found + 0 }' "$TMP/ls-remote.txt")
  else
    die "git ls-remote origin failed: $(head -n 1 "$TMP/ls-remote.err"). Run this outside the sandbox and check the network and the remote."
  fi
  if [ "$BRANCH_ON_REMOTE" = 0 ]; then
    HEAD_STATUS="remote-missing"
  elif git fetch --quiet origin "+refs/heads/$BRANCH:refs/remotes/origin/$BRANCH" 2> "$TMP/fetch-head.err"; then
    REMOTE_HEAD=$(git rev-parse "refs/remotes/origin/$BRANCH")
    PR_HEAD=$(jq -r '.headRefOid // empty' "$TMP/pr.json")
    if [ "$REMOTE_HEAD" = "$HEAD_SHA" ]; then
      if [ -n "$PR_HEAD" ] && [ "$PR_HEAD" != "$HEAD_SHA" ]; then
        HEAD_STATUS="pr-head-mismatch"
      else
        HEAD_STATUS="in-sync"
      fi
    elif git merge-base --is-ancestor "$HEAD_SHA" "$REMOTE_HEAD"; then
      HEAD_STATUS="remote-ahead"
    elif git merge-base --is-ancestor "$REMOTE_HEAD" "$HEAD_SHA"; then
      HEAD_STATUS="local-ahead"
    else
      HEAD_STATUS="diverged"
    fi
  else
    die "git fetch origin $BRANCH failed: $(head -n 1 "$TMP/fetch-head.err"). Run this outside the sandbox and check the network and the remote."
  fi
fi

# Upstream status. has_upstream is true only when the configured upstream is a branch of origin
# with the name of the local branch: `git checkout -b feat origin/main` sets upstream origin/main
# and `git push` would not publish feat; an upstream on another remote (fork/feat) is not where
# `gh pr create --head feat` looks. upstream always reports the configured upstream (or null).
HAS_UPSTREAM=false
UPSTREAM=""
UNPUSHED=null
if UPSTREAM=$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2> /dev/null); then
  UPSTREAM_REF=$(git config --get "branch.$BRANCH.merge" || true)
  UPSTREAM_REMOTE=$(git config --get "branch.$BRANCH.remote" || true)
  if [ "$UPSTREAM_REMOTE" != origin ]; then
    warn "upstream is $UPSTREAM on remote $UPSTREAM_REMOTE, but the PR head is read from origin: publish it with git push -u origin $BRANCH"
  elif [ "${UPSTREAM_REF#refs/heads/}" = "$BRANCH" ]; then
    HAS_UPSTREAM=true
    UNPUSHED=$(git rev-list --count '@{u}..HEAD')
  else
    warn "upstream is $UPSTREAM, not a branch named $BRANCH: publish it with git push -u origin $BRANCH"
  fi
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
  --slurpfile linked "$TMP/linked.json" \
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
  --arg pr_lookup "$PR_LOOKUP" \
  --arg base_repo "$BASE_REPO" \
  --arg base_repo_source "$BASE_REPO_SOURCE" \
  --arg head_repo "$HEAD_REPO" \
  --arg base_remote "$BASE_REMOTE" \
  --arg head_status "$HEAD_STATUS" \
  --arg remote_head "$REMOTE_HEAD" \
  --slurpfile warnings "$TMP/warnings.json" \
  '{
    branch: $branch,
    ticket_candidate: (if $ticket == "" then null else $ticket end),
    base: $base,
    base_source: $base_source,
    base_repo: (if $base_repo == "" then null else $base_repo end),
    base_repo_source: (if $base_repo_source == "" then null else $base_repo_source end),
    head_repo: (if $head_repo == "" then null else $head_repo end),
    base_remote: (if $base_remote == "" then null else $base_remote end),
    linked_issues: $linked[0],
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
    head_in_sync: (if $head_status == "skipped" then null else $head_status == "in-sync" end),
    head_status: $head_status,
    remote_head: (if $remote_head == "" then null else $remote_head end),
    has_upstream: $has_upstream,
    upstream: (if $upstream == "" then null else $upstream end),
    unpushed_count: $unpushed,
    uncommitted: $uncommitted,
    template: (if $template_path == "" then null else {path: $template_path, content: $template_content} end),
    other_templates: $other_templates[0],
    pr: $pr[0],
    pr_lookup: $pr_lookup,
    warnings: $warnings[0]
  }'
