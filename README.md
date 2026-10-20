# autopr

A Claude skill that creates and updates GitHub pull requests. It gathers git context, fetches the Jira ticket named in the branch via acli, finds the PR template, writes the PR description, and creates or updates the PR with the gh CLI. It posts a review request to Slack only when asked.

## Requirements

- git
- gh
- acli
- jq

## Usage

The skill triggers on requests such as "autopr", "create pr" and "pr description". The instructions are in `SKILL.md`.

## Former Python CLI

This repo held a Python CLI before it became a skill. The last release tag of the CLI is `v1.1.0`. Check it out with `git checkout v1.1.0`.
