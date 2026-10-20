# autopr

A Claude skill that creates and updates GitHub pull requests. It gathers git context, fetches the Jira ticket named in the branch via acli, finds the PR template, writes the PR description, and creates or updates the PR with the gh CLI.

## Requirements

- git
- gh
- acli
- jq

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

The skill triggers on requests such as "autopr", "create pr" and "pr description". The instructions are in `skills/autopr/SKILL.md`.

## Validate

```bash
claude plugin validate --strict .
npx skills add . --list
uvx --from skills-ref agentskills validate skills/autopr
```

## Former Python CLI

This repo held a Python CLI before it became a skill. The last release tag of the CLI is `v1.1.0`. Check it out with `git checkout v1.1.0`.
