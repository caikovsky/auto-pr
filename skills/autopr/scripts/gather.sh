#!/usr/bin/env bash
# Collect the git and GitHub context for one PR and print it as a single JSON object.
#
# Usage: gather.sh [--base <branch>] [--repo <owner/name>] [--pr <number>] [--no-network] [--max-diff-lines <n>]
#   --base <branch>        base branch; overrides the existing PR and the repo default
#   --repo <owner/name>    repository the PR targets (a fork PR targets the parent); ignored when an
#                          open PR already fixes it, and with --no-network
#   --pr <number>          pick this open PR from the branch when several are open (an error when it
#                          is not one of them); with --repo the number is read in that repository
#   --no-network           skip git fetch and every gh call (also AUTOPR_NO_NETWORK=1)
#   --max-diff-lines <n>   cut the diff after n lines (default 1200, also AUTOPR_MAX_DIFF_LINES)
#
# Read-only: never commits, pushes or edits files. Exit 2 on a fatal error (message on stderr):
# no repo, no origin, detached HEAD, a gh or git fetch failure, or no merge base with the base branch.
# Network runs fetch refs: origin/<base> (or a private refs/autopr/base-<pid>-<n> for a fork PR,
# deleted on exit) and origin/<branch>.
# A shell pipe that closes early (| head) kills the writer with SIGPIPE under pipefail, so every
# command with long output goes through a temp file instead.
set -euo pipefail

BASE_ARG=""
REPO_ARG=""
PR_ARG=""
PR_GIVEN=0
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
    --pr)
      [ $# -ge 2 ] || die "--pr needs a PR number"
      PR_ARG="$2"
      PR_GIVEN=1
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
if [ "$PR_GIVEN" = 1 ]; then
  case "$PR_ARG" in
    '' | 0* | *[!0-9]*) die "--pr must be a positive integer (no leading zero)" ;;
  esac
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
PRIVATE_REF=""
trap 'rm -rf "$TMP"; if [ -n "$PRIVATE_REF" ]; then git update-ref -d "$PRIVATE_REF" > /dev/null 2>&1 || true; fi' EXIT
trap 'exit 1' INT TERM HUP
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

# die_git <what> <error file> <remote url>: exit 2 for a failed git network command. An SSH
# failure (a broken ssh-agent, a missing key) gets its own message with the way past it.
HTTPS_REWRITE="GIT_CONFIG_COUNT=2 GIT_CONFIG_KEY_0=url.https://github.com/.insteadOf GIT_CONFIG_VALUE_0=git@github.com: GIT_CONFIG_KEY_1=credential.helper GIT_CONFIG_VALUE_1='!gh auth git-credential'"
die_git() {
  local what="$1" errfile="$2" url="$3" first
  first=$(head -n 1 "$errfile")
  if grep -qE 'Permission denied \(publickey|signing failed|Host key verification failed|ssh: ' "$errfile" \
    || { grep -q 'Could not read from remote repository' "$errfile" && [[ $url =~ ^(ssh://|[A-Za-z0-9._-]+@[^/:]+:) ]]; }; then
    die "$what failed over SSH: $first. Check the ssh-agent (ssh-add -l) and the key's access to GitHub, or run this with an HTTPS rewrite set through the environment for this command only (no git config is edited): $HTTPS_REWRITE"
  fi
  die "$what failed: $first. Run this outside the sandbox and check the network and the remote."
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

# pr_lookup: found (exactly one open PR), none (gh answered: no open PR), ambiguous (open PRs in
# more than one place: none is chosen, open_prs lists them), skipped (gh was not asked).
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
CANDIDATE_REMOTES=() # per candidate: the extra remote it came from, or "" when it is origin's repo, its parent or --repo
add_candidate() { # <owner/repo> [extra remote name]: append once, case-insensitively, when it is a valid name
  local c
  valid_repo "$1" || return 0
  for c in "${CANDIDATES[@]+"${CANDIDATES[@]}"}"; do
    [ "$(lower "$c")" = "$(lower "$1")" ] && return 0
  done
  CANDIDATES+=("$1")
  CANDIDATE_REMOTES+=("${2:-}")
}

# A failed lookup stops the run. The one exception is a repository that only an extra remote
# points at and that GitHub cannot find or the user cannot see (a stale remote): that is a
# warning naming the remote, and the search goes on. Origin's repository, its parent and --repo
# never get the exception, and neither does any other kind of error (network, auth, rate limit).
# lookup_failed <candidate> <remote or ""> <what> <error file>: returns 0 when the run may go on.
lookup_failed() {
  local candidate="$1" remote="$2" what="$3" errfile="$4" first
  first=$(head -n 1 "$errfile")
  if [ -n "$remote" ]; then
    if grep -q 'Could not resolve to a Repository' "$errfile"; then
      warn "remote '$remote' points at $candidate, which GitHub cannot find or you cannot see: skipped (remove it with git remote remove $remote or fix its URL)"
      return 0
    fi
    die "$what for $candidate failed: $first. This repository comes from the remote '$remote': fix access to it, or remove the remote with git remote remove $remote or fix its URL. Otherwise run this outside the sandbox (a sandbox blocks the GitHub network and keyring) and log in with gh auth login."
  fi
  die "$what for $candidate failed: $first. Run this outside the sandbox (a sandbox blocks the GitHub network and keyring), log in with gh auth login, and check access to $candidate."
}
if [ "$HAVE_GH" = 1 ]; then
  [ -n "$HEAD_REPO" ] || die "origin URL '$ORIGIN_URL' does not name an owner/repo: the GitHub lookups need it"
  # --repo may carry the old name of a renamed repository: GitHub redirects it, but the PR URLs
  # carry the canonical name, so compare and report that one.
  if [ -n "$REPO_ARG" ]; then
    if CANONICAL=$(GH_PROMPT_DISABLED=1 gh repo view "$REPO_ARG" --json nameWithOwner --jq .nameWithOwner 2> "$TMP/canon.err") \
      && valid_repo "$CANONICAL"; then
      [ "$(lower "$CANONICAL")" = "$(lower "$REPO_ARG")" ] || warn "--repo $REPO_ARG is now named $CANONICAL: using that"
      REPO_ARG="$CANONICAL"
    else
      die "gh could not find the repository $REPO_ARG: $(head -n 1 "$TMP/canon.err"). Check the name, or run this outside the sandbox."
    fi
  fi
  if GH_PROMPT_DISABLED=1 gh repo view "$HEAD_REPO" --json nameWithOwner,parent,defaultBranchRef \
    > "$TMP/repo.json" 2> "$TMP/repo.err"; then
    VIEW_REPO=$(jq -r '.nameWithOwner // empty' "$TMP/repo.json")
    VIEW_PARENT=$(jq -r 'if .parent then "\(.parent.owner.login)/\(.parent.name)" else empty end' "$TMP/repo.json")
    VIEW_DEFAULT=$(jq -r '.defaultBranchRef.name // empty' "$TMP/repo.json")
    # GitHub's name for origin is the truth: after a transfer or rename the old URL still works
    # through a redirect, but PRs carry the new owner.
    if valid_repo "$VIEW_REPO" && [ "$(lower "$VIEW_REPO")" != "$(lower "$HEAD_REPO")" ]; then
      warn "origin URL names $HEAD_REPO but GitHub says $VIEW_REPO (transferred or renamed): using $VIEW_REPO"
      HEAD_REPO="$VIEW_REPO"
    fi
  else
    REPO_VIEW_FAILED=$(head -n 1 "$TMP/repo.err")
  fi

  # Where could this branch's PR live? The repository of origin, its parent, the repository of
  # every other remote (upstream), and --repo when it names another one. Every open PR found is
  # reported in open_prs; --repo and --pr only choose among them. `gh pr list --head` is the
  # documented filter by head branch name; it cannot take owner:branch, and `gh pr view <branch>`
  # may return a PR from another fork with the same branch name, so the head owner is checked here.
  [ -z "$REPO_ARG" ] || add_candidate "$REPO_ARG"
  add_candidate "$HEAD_REPO"
  add_candidate "$VIEW_PARENT"
  while IFS= read -r remote; do
    [ "$remote" = origin ] || add_candidate "$(repo_of_url "$(git remote get-url "$remote")")" "$remote"
  done < <(git remote)
  HEAD_OWNER="${HEAD_REPO%%/*}"
  PR_LOOKUP=none
  : > "$TMP/open-all.ndjson"
  PR_FIELDS=number,url,title,body,isDraft,baseRefName,headRefOid,headRefName,headRepositoryOwner,state
  PR_LIST_LIMIT=100
  candidate_index=-1
  for candidate in "${CANDIDATES[@]}"; do
    candidate_index=$((candidate_index + 1))
    candidate_remote="${CANDIDATE_REMOTES[$candidate_index]}"
    # Any candidate that cannot be searched stops the run (see lookup_failed): an incomplete search could report
    # none or found while a second PR exists, or let a create go out unchecked.
    if [ "$PR_GIVEN" = 1 ]; then
      # An exact number needs no listing: a listing is capped and could hide the PR.
      if GH_PROMPT_DISABLED=1 gh pr view "$PR_ARG" --repo "$candidate" --json "$PR_FIELDS" \
        > "$TMP/pr.one" 2> "$TMP/pr.err"; then
        jq -c '[.]' "$TMP/pr.one" > "$TMP/pr.list"
      elif grep -qiE 'Could not resolve to a PullRequest|no pull requests found' "$TMP/pr.err"; then
        echo '[]' > "$TMP/pr.list"
      else
        lookup_failed "$candidate" "$candidate_remote" "gh pr view" "$TMP/pr.err"
        continue
      fi
      jq -c --arg b "$BRANCH" --arg o "$(lower "$HEAD_OWNER")" \
        '.[] | select(.state == "OPEN" and .headRefName == $b and ((.headRepositoryOwner.login // "") | ascii_downcase) == $o) | {number, url, title, body, isDraft, baseRefName, headRefOid}' \
        "$TMP/pr.list" >> "$TMP/open-all.ndjson"
    fi
    # The listing of open PRs from this branch. With --pr it only fills open_prs, so a full page
    # is a warning; without --pr it decides the result, so a full page is an error.
    if ! GH_PROMPT_DISABLED=1 gh pr list --repo "$candidate" --head "$BRANCH" --state open --limit "$PR_LIST_LIMIT" \
      --json "$PR_FIELDS" > "$TMP/pr.list" 2> "$TMP/pr.err"; then
      lookup_failed "$candidate" "$candidate_remote" "gh pr list" "$TMP/pr.err"
      continue
    fi
    if [ "$(jq length "$TMP/pr.list")" -ge "$PR_LIST_LIMIT" ]; then
      if [ "$PR_GIVEN" = 1 ]; then
        warn "$PR_LIST_LIMIT open PRs came back for this branch name in $candidate: open_prs may be incomplete"
      else
        die "too many PRs for this branch name in $candidate: $PR_LIST_LIMIT open PRs came back, so the list may be incomplete. Pass --pr <number>."
      fi
    fi
    jq -c --arg b "$BRANCH" --arg o "$(lower "$HEAD_OWNER")" \
      '[.[] | select(.state == "OPEN" and .headRefName == $b and ((.headRepositoryOwner.login // "") | ascii_downcase) == $o)]' \
      "$TMP/pr.list" > "$TMP/pr.mine"
    jq -c '.[] | {number, url, title, body, isDraft, baseRefName, headRefOid}' "$TMP/pr.mine" >> "$TMP/open-all.ndjson"
    if [ "$PR_GIVEN" != 1 ] && [ "$(jq length "$TMP/pr.mine")" = 0 ]; then
      # Informational only: the latest PR of this branch that is not open (a small query, never
      # used to decide anything).
      if GH_PROMPT_DISABLED=1 gh pr list --repo "$candidate" --head "$BRANCH" --state all --limit 20 \
        --json "$PR_FIELDS" > "$TMP/pr.all" 2> /dev/null; then
        OTHER_STATE=$(jq -r --arg b "$BRANCH" --arg o "$(lower "$HEAD_OWNER")" \
          '[.[] | select(.headRefName == $b and ((.headRepositoryOwner.login // "") | ascii_downcase) == $o)] | first | .state // empty' "$TMP/pr.all")
        [ -z "$OTHER_STATE" ] || warn "latest PR for this branch in $candidate is $OTHER_STATE: treated as no existing PR"
      fi
    fi
  done
  # A renamed repository redirects, so the same PR can come back from two candidates: keep one
  # per URL. open_prs is that full list. Several open PRs from one branch (the fork and the
  # parent, or two bases in one repository) are ambiguous. Only the user's explicit choice picks
  # one: --pr <number> (the number, in --repo's repository when it is given) or --repo alone (the
  # PR in that repository). --base never selects a PR: it sets the base of the diff and of a new
  # PR, and changes the base of the one PR that is selected.
  jq -sc 'unique_by(.url)' "$TMP/open-all.ndjson" > "$TMP/open-all.json"
  jq -c --arg r "$(lower "$REPO_ARG")" --argjson n "${PR_ARG:-0}" '
    [.[] | select(($r == "" or ((.url | sub("^https?://[^/]+/"; "") | sub("/pull/.*$"; "") | ascii_downcase) == $r))
                  and ($n == 0 or .number == $n))]' "$TMP/open-all.json" > "$TMP/open-sel.json"
  if [ "$PR_GIVEN" = 1 ]; then
    case "$(jq length "$TMP/open-sel.json")" in
      0) die "PR #$PR_ARG is not an open PR from this branch${REPO_ARG:+ in $REPO_ARG} (open: $(jq -r '[.[] | "#\(.number) in \(.url | sub("^https?://[^/]+/"; "") | sub("/pull/.*$"; ""))"] | join(", ") | if . == "" then "none" else . end' "$TMP/open-all.json"))" ;;
      1) ;;
      *) die "PR #$PR_ARG exists in several repositories: add --repo <owner/name>" ;;
    esac
  elif [ -n "$REPO_ARG" ] && [ "$(jq length "$TMP/open-sel.json")" -lt "$(jq length "$TMP/open-all.json")" ]; then
    warn "open PRs from this branch outside $REPO_ARG are not selected: $(jq -r --slurpfile sel "$TMP/open-sel.json" '[.[] | . as $p | select(($sel[0] | map(.url) | index($p.url)) == null) | "#\(.number) \(.url)"] | join(", ")' "$TMP/open-all.json")"
  fi
  OPEN_COUNT=$(jq length "$TMP/open-sel.json")
  if [ "$OPEN_COUNT" = 1 ]; then
    jq -c '.[0]' "$TMP/open-sel.json" > "$TMP/pr.json"
    PR_BASE=$(jq -r .baseRefName "$TMP/pr.json")
    PR_LOOKUP=found
  elif [ "$OPEN_COUNT" -gt 1 ]; then
    PR_LOOKUP=ambiguous
    warn "$OPEN_COUNT open PRs come from this branch: none is chosen, see open_prs (--pr <number> picks one)"
  fi
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
if [ "$PR_GIVEN" = 1 ] && [ "$NO_NETWORK" = 1 ]; then
  warn "--pr is ignored with --no-network: no PR lookup was made"
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
# fetch the base from a remote that points at that repository, or by URL, into a ref private to
# this run (removed on exit), so a stale fork branch never shapes the diff and parallel runs in
# one checkout cannot overwrite each other's base.
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
  PRIVATE_REF="refs/autopr/base-$$-$RANDOM"
  git fetch --quiet "$FETCH_FROM" "+refs/heads/$BASE:$PRIVATE_REF" 2> "$TMP/fetch.err" \
    || die_git "git fetch $FETCH_FROM $BASE" "$TMP/fetch.err" "$FETCH_FROM"
  BASE_REF="$PRIVATE_REF"
elif [ "$NO_NETWORK" != 1 ]; then
  git fetch --quiet origin "+refs/heads/$BASE:refs/remotes/origin/$BASE" 2> "$TMP/fetch.err" \
    || die_git "git fetch origin $BASE" "$TMP/fetch.err" "$ORIGIN_URL"
fi
git rev-parse --verify --quiet "$BASE_REF^{commit}" > /dev/null \
  || die "$BASE_REF not found: fetch it or pass a different --base"
# Pin the commit: every later log and diff uses this id, whatever happens to the ref meanwhile.
BASE_SHA=$(git rev-parse --verify "$BASE_REF^{commit}")
if ! git merge-base "$BASE_SHA" HEAD > /dev/null 2>&1; then
  if [ "$(git rev-parse --is-shallow-repository)" = true ]; then
    die "no merge base with $BASE_REF in this shallow clone: run git fetch --unshallow, then run again"
  fi
  die "no merge base between HEAD and $BASE_REF: the branches share no history, check --base"
fi

RANGE="$BASE_SHA...HEAD"

qgit log --no-decorate --format='%h %s' "$BASE_SHA..HEAD" | lines_json > "$TMP/commits.json"
# Issues the branch closes: "closes|fixes|resolves #N" (any tense, optional colon, digits must end
# at a word boundary) in its commit messages. Bare #N is ignored: it is usually a PR number, as in
# "Add feature (#7)".
git log --format=%B "$BASE_SHA..HEAD" > "$TMP/messages.txt"
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
    die_git "git ls-remote origin" "$TMP/ls-remote.err" "$ORIGIN_URL"
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
    die_git "git fetch origin $BRANCH" "$TMP/fetch-head.err" "$ORIGIN_URL"
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
if [ -s "$TMP/open-all.json" ]; then
  jq -c '[.[] | {number, url, repo: (.url | sub("^https?://[^/]+/"; "") | sub("/pull/.*$"; "")), baseRefName}]' "$TMP/open-all.json" > "$TMP/open-prs.json"
else
  echo '[]' > "$TMP/open-prs.json"
fi

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
  --slurpfile open_prs "$TMP/open-prs.json" \
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
    open_prs: $open_prs[0],
    warnings: $warnings[0]
  }'
