# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [2.0.0] - 2025-01-30

### Added
- Full Python rewrite with CLEAN architecture
- Multiple AI provider support: Gemini, GitHub Copilot, Cursor Agent
- Auto-detection of available AI providers
- PR update support with `--update` / `-u` flag
- Comparison mode (`--test`) to evaluate AI providers side-by-side
- Configuration file support (`~/.config/autopr/config.toml`)
- Customizable AI prompts via config
- Rich CLI output with colors and formatting
- Draft PR support with `--draft` flag
- Verbose mode with `--verbose` flag

### Changed
- Migrated from bash script to Python package
- CLI command changed from `auto-pr` to `autopr`
- Configuration is now the single source of truth (no hardcoded defaults)

### Removed
- Legacy bash script

## [1.0.0] - 2024-xx-xx

### Added
- Initial bash script implementation
- Basic PR creation with AI-generated descriptions
- Jira ticket integration via Atlassian CLI
- GitHub CLI integration for PR creation

[Unreleased]: https://github.com/caikovsky/auto-pr/compare/v2.0.0...HEAD
[2.0.0]: https://github.com/caikovsky/auto-pr/compare/v1.0.0...v2.0.0
[1.0.0]: https://github.com/caikovsky/auto-pr/releases/tag/v1.0.0
