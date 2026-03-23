# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [1.1.0] - 2026-03-23

### Added
- Strip bracketed tags (e.g. `[AN]`, `[SPIKE]`, `[Android]`, `[PoC]`) from Jira ticket titles in PR titles

### Changed
- PR title format now uses dash separator: `[KEY] - Title`

### Removed
- Legacy bash script (`auto-pr`)

## [1.0.0] - 2025-02-02

### Added
- Initial Python release
- AI-powered PR description generation (Gemini, GitHub Copilot, Cursor Agent)
- Jira integration via Atlassian CLI
- Git context analysis (commits, diffs, changed files)
- PR template support
- AI provider comparison mode

[Unreleased]: https://github.com/caikovsky/auto-pr/compare/v1.1.0...HEAD
[1.1.0]: https://github.com/caikovsky/auto-pr/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/caikovsky/auto-pr/releases/tag/v1.0.0
