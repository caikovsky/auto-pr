#!/usr/bin/env bash
# The version is written in three places: .claude-plugin/plugin.json, the SKILL.md frontmatter
# (metadata.version) and the newest version heading of CHANGELOG.md. They must agree, and the
# version must be valid SemVer. A "## Unreleased" heading is skipped: the files then still name
# the last released version. Needs bash and jq.
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO=$(cd "$HERE/.." && pwd)

# valid_semver <version>: SemVer 2.0.0. Each dot-separated pre-release identifier is non-empty,
# uses [0-9A-Za-z-] and, when purely numeric, has no leading zero; each build identifier is
# non-empty and uses [0-9A-Za-z-] (leading zeros are allowed there). Works in bash 3.2.
valid_semver() {
  local v="$1" core pre="" build="" has_pre=0 has_build=0 id ids
  case "$v" in *+*) has_build=1; build="${v#*+}"; v="${v%%+*}" ;; esac
  case "$v" in *-*) has_pre=1; pre="${v#*-}"; v="${v%%-*}" ;; esac
  core="$v"
  [[ $core =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || return 1
  if [ "$has_pre" = 1 ]; then
    [ -n "$pre" ] || return 1
    case "$pre" in .* | *. | *..*) return 1 ;; esac
    ids=$(printf '%s' "$pre" | tr '.' ' ')
    for id in $ids; do
      [[ $id =~ ^[0-9A-Za-z-]+$ ]] || return 1
      if [[ $id =~ ^[0-9]+$ ]] && [[ $id =~ ^0[0-9] ]]; then return 1; fi
    done
  fi
  if [ "$has_build" = 1 ]; then
    [ -n "$build" ] || return 1
    case "$build" in .* | *. | *..*) return 1 ;; esac
    ids=$(printf '%s' "$build" | tr '.' ' ')
    for id in $ids; do
      [[ $id =~ ^[0-9A-Za-z-]+$ ]] || return 1
    done
  fi
  return 0
}

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
  if [ -n "$plugin" ] && ! valid_semver "$plugin"; then echo "version '$plugin' is not valid SemVer"; fi
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

# SemVer identifiers: no empty ones, no leading zeros in numeric pre-release identifiers, build
# identifiers use letters, digits and hyphens only (leading zeros are allowed there).
for bad in 1.2.3-01 1.2.3-rc..1 1.2.3+build..1 1.2.3- 1.2.3+ 1.2.3-rc. 1.2.3-.rc 1.2.3-rc_1 1.2.3+b_1 1.2.3-1.02 1.2.3-rc+ 1.2.3+a+b; do
  fixture "$WORK/bad-$bad" "$bad" "$bad" "$bad"
  expect_problem "invalid SemVer $bad is rejected" "$WORK/bad-$bad" "not valid SemVer"
done
for good in 1.2.3-rc.1 1.2.3-0.3.7 1.2.3+001 1.2.3-alpha-1+build.5 1.2.3-0 1.2.3-a.0.b 1.2.3-1a 1.2.3-x.7.z.92 1.2.3+20130313144700 1.2.3-beta+exp.sha.5114f85; do
  fixture "$WORK/good-$good" "$good" "$good" "$good"
  expect_ok "valid SemVer $good is accepted" "$WORK/good-$good"
done

# --- this repository ---
expect_ok "this repository's versions agree and are SemVer" "$REPO"
echo "version: $(versions "$REPO" | sed -n 1p)"

echo
echo "passed: $PASS, failed: $FAIL"
[ "$FAIL" -eq 0 ]
