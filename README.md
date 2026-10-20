# autopr

An agent skill for Claude Code and Codex that creates and updates GitHub pull requests. A bundled script gathers the git context against the up-to-date base branch. The skill fetches the Jira ticket named in the branch via acli, fills the PR template, writes the PR description, and creates or updates the PR with the gh CLI. It never commits or pushes.

## Requirements

- git
- gh
- jq
- acli (optional: without it the Jira lookup is skipped)

## Install

### Claude Code

```bash
claude plugin marketplace add caikovsky/auto-pr
claude plugin install autopr@auto-pr
```

In a session, use `/plugin marketplace add caikovsky/auto-pr` and `/plugin install autopr@auto-pr`.

### Codex and other agents

```bash
npx skills add caikovsky/auto-pr --global --agent codex
```

This installs the skill to `~/.agents/skills/autopr`.

## Usage

The skill triggers on requests such as "autopr", "create pr", "push and open PR" and "ship it". The instructions are in `skills/autopr/SKILL.md`; the release-notes rules are in `skills/autopr/references/release-notes.md`. See `CHANGELOG.md` for the version history.

## Validate

```bash
bash tests/gather.test.sh
shellcheck skills/autopr/scripts/*.sh tests/*.sh
claude plugin validate --strict .
npx skills add . --list
uvx --from skills-ref agentskills validate skills/autopr
```

## Former Python CLI

This repo held a Python CLI before it became a skill. The last release tag of the CLI is `v1.1.0`. Check it out with `git checkout v1.1.0`.
