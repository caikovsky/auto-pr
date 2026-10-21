#!/usr/bin/env bash
# The version is written in three places: .claude-plugin/plugin.json, the SKILL.md frontmatter
# (metadata.version) and the newest version heading of CHANGELOG.md. They must agree, and the
# version must be valid SemVer. A "## Unreleased" heading is skipped: the files then still name
# the last released version. Needs bash and jq.
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO=$(cd "$HERE/.." && pwd)

SEMVER='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$'

PASS=0
FAIL=0

# versions <root>: prints the three versions, one per line: plugin, skill, changelog.
versions() {
  local root="$1" skill
  jq -r '.version // ""' "$root/.claude-plugin/plugin.json"
  skill=$(sed -n 's/^  version: "\(.*\)"$/\1/p' "$root/skills/autopr/SKILL.md" | head -n 1)
  printf '%s\n' "$skill"
  sed -n 's/^## \([0-9][0-9]*\.[0-9][^ ]*\).*$/\1/p' "$root/CHANGELOG.md" | head -n 1
}

# problems <root>: prints one line per problem; nothing when the versions agree and are SemVer.
problems() {
  local root="$1" plugin skill changelog all
  all=$(versions "$root")
  plugin=$(printf '%s\n' "$all" | sed -n 1p)
  skill=$(printf '%s\n' "$all" | sed -n 2p)
  changelog=$(printf '%s\n' "$all" | sed -n 3p)
  [ -n "$plugin" ] || echo "plugin.json has no version"
  [ -n "$skill" ] || echo "SKILL.md has no metadata.version"
  [ -n "$changelog" ] || echo "CHANGELOG.md has no version heading"
  [ "$plugin" = "$skill" ] || echo "plugin.json ($plugin) and SKILL.md ($skill) differ"
  [ "$plugin" = "$changelog" ] || echo "plugin.json ($plugin) and the newest CHANGELOG.md heading ($changelog) differ"
  if [ -n "$plugin" ] && ! [[ $plugin =~ $SEMVER ]]; then echo "version '$plugin' is not valid SemVer"; fi
  if [ -f "$root/.claude-plugin/marketplace.json" ]; then
    jq -r '.plugins[]? | select(.version != null) | "\(.name) \(.version)"' "$root/.claude-plugin/marketplace.json" | while read -r name v; do
      [ "$v" = "$plugin" ] || echo "marketplace.json lists $name $v, not $plugin"
    done
  fi
}

# expect_ok <name> <root>   /   expect_problem <name> <root> <substring>
expect_ok() {
  local out
  out=$(problems "$2")
  if [ -z "$out" ]; then PASS=$((PASS + 1)); echo "ok   $1"; else FAIL=$((FAIL + 1)); echo "FAIL $1: $out"; fi
}
expect_problem() {
  local out
  out=$(problems "$2")
  case "$out" in
    *"$3"*) PASS=$((PASS + 1)); echo "ok   $1" ;;
    *) FAIL=$((FAIL + 1)); echo "FAIL $1: expected a problem containing [$3], got [$out]" ;;
  esac
}

# fixture <dir> <plugin version> <skill version> <changelog heading lines...>
fixture() {
  local dir="$1" plugin="$2" skill="$3"
  shift 3
  mkdir -p "$dir/.claude-plugin" "$dir/skills/autopr"
  printf '{"name":"autopr","version":"%s"}\n' "$plugin" > "$dir/.claude-plugin/plugin.json"
  printf -- '---\nname: autopr\nmetadata:\n  version: "%s"\n---\n' "$skill" > "$dir/skills/autopr/SKILL.md"
  { echo "# Changelog"; echo; for h in "$@"; do echo "## $h"; echo; echo "- entry"; echo; done; } > "$dir/CHANGELOG.md"
}

WORK=$(mktemp -d "${TMPDIR:-/tmp}/autopr-version-test.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

# --- the checker itself ---
fixture "$WORK/ok" 1.2.3 1.2.3 1.2.3 1.2.2
expect_ok "agreeing versions pass" "$WORK/ok"
fixture "$WORK/unreleased" 1.2.3 1.2.3 Unreleased 1.2.3 1.2.2
expect_ok "an Unreleased heading is skipped" "$WORK/unreleased"
fixture "$WORK/plugin" 1.2.4 1.2.3 1.2.3
expect_problem "plugin.json ahead of SKILL.md fails" "$WORK/plugin" "differ"
fixture "$WORK/skill" 1.2.3 1.2.4 1.2.3
expect_problem "SKILL.md ahead of plugin.json fails" "$WORK/skill" "differ"
fixture "$WORK/changelog" 1.2.3 1.2.3 1.2.4 1.2.3
expect_problem "a newer CHANGELOG heading fails" "$WORK/changelog" "newest CHANGELOG.md heading (1.2.4)"
fixture "$WORK/notsemver" 1.2 1.2 1.2
expect_problem "a version that is not SemVer fails" "$WORK/notsemver" "not valid SemVer"
fixture "$WORK/leadingzero" 01.2.3 01.2.3 01.2.3
expect_problem "a leading zero is not SemVer" "$WORK/leadingzero" "not valid SemVer"
fixture "$WORK/prerelease" 1.2.3-rc.1 1.2.3-rc.1 1.2.3-rc.1
expect_ok "a pre-release version is SemVer" "$WORK/prerelease"
fixture "$WORK/market" 1.2.3 1.2.3 1.2.3
printf '{"plugins":[{"name":"autopr","version":"1.2.0"}]}\n' > "$WORK/market/.claude-plugin/marketplace.json"
expect_problem "a marketplace version that differs fails" "$WORK/market" "marketplace.json lists autopr 1.2.0"

# --- this repository ---
expect_ok "this repository's versions agree and are SemVer" "$REPO"
echo "version: $(versions "$REPO" | sed -n 1p)"

echo
echo "passed: $PASS, failed: $FAIL"
[ "$FAIL" -eq 0 ]
