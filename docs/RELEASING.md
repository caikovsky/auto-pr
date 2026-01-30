# Releasing

This document describes how to release new versions of `autopr`.

## Versioning

We follow [Semantic Versioning](https://semver.org/):

```
MAJOR.MINOR.PATCH (e.g., 2.1.0)
```

| Type | When to bump | Example |
|------|--------------|---------|
| **MAJOR** | Breaking changes (CLI flags removed, config format changed) | 2.0.0 → 3.0.0 |
| **MINOR** | New features, backwards compatible | 2.0.0 → 2.1.0 |
| **PATCH** | Bug fixes, documentation | 2.0.0 → 2.0.1 |

### What Counts as Breaking?

- Removing or renaming CLI flags
- Changing config file format in incompatible ways
- Changing default behavior users depend on
- Removing features

### What's NOT Breaking?

- Adding new CLI flags
- Adding new config options (with defaults)
- Bug fixes
- Performance improvements
- New AI provider support

## Release Checklist

### 1. Prepare the Release

```bash
# Ensure you're on main and up to date
git checkout main
git pull origin main

# Run tests
uv run pytest
uv run mypy auto_pr
uv run ruff check auto_pr
```

### 2. Update Version

Edit `pyproject.toml`:

```toml
[project]
version = "2.1.0"  # Update this
```

### 3. Update CHANGELOG.md

Move items from `[Unreleased]` to the new version section:

```markdown
## [Unreleased]

## [2.1.0] - 2025-02-15

### Added
- New feature X

### Fixed
- Bug Y
```

Update the comparison links at the bottom:

```markdown
[Unreleased]: https://github.com/caikovsky/auto-pr/compare/v2.1.0...HEAD
[2.1.0]: https://github.com/caikovsky/auto-pr/compare/v2.0.0...v2.1.0
```

### 4. Commit the Release

```bash
git add pyproject.toml CHANGELOG.md
git commit -m "release: v2.1.0"
```

### 5. Tag the Release

```bash
# Create annotated tag
git tag -a v2.1.0 -m "Release v2.1.0"

# Push commit and tag
git push origin main
git push origin v2.1.0
```

### 6. Create GitHub Release

```bash
# Extract release notes from CHANGELOG for this version
gh release create v2.1.0 \
  --title "v2.1.0" \
  --notes "See [CHANGELOG.md](https://github.com/caikovsky/auto-pr/blob/main/CHANGELOG.md#210---2025-02-15) for details."
```

Or create via GitHub UI:
1. Go to https://github.com/caikovsky/auto-pr/releases/new
2. Choose the tag `v2.1.0`
3. Set title to `v2.1.0`
4. Copy release notes from CHANGELOG.md
5. Publish

## User Upgrade Path

Users install and upgrade via:

```bash
# Install
pipx install git+https://github.com/caikovsky/auto-pr.git

# Upgrade to latest
pipx upgrade autopr

# Force reinstall (if upgrade doesn't work)
pipx install --force git+https://github.com/caikovsky/auto-pr.git

# Install specific version
pipx install git+https://github.com/caikovsky/auto-pr.git@v2.1.0
```

## CHANGELOG Format

Follow [Keep a Changelog](https://keepachangelog.com/):

```markdown
## [X.Y.Z] - YYYY-MM-DD

### Added
- New features

### Changed
- Changes to existing functionality

### Deprecated
- Features to be removed in future

### Removed
- Removed features

### Fixed
- Bug fixes

### Security
- Security fixes
```

**Guidelines:**
- Write for users, not developers
- Focus on "what changed" not "how"
- Use imperative mood ("Add feature" not "Added feature")
- Link to issues/PRs when relevant: `Fixed crash on empty diff (#42)`

## Quick Release Script

For convenience, here's a one-liner (after updating files manually):

```bash
VERSION="2.1.0" && \
git add pyproject.toml CHANGELOG.md && \
git commit -m "release: v$VERSION" && \
git tag -a "v$VERSION" -m "Release v$VERSION" && \
git push origin main && \
git push origin "v$VERSION" && \
gh release create "v$VERSION" --title "v$VERSION" --notes "See CHANGELOG.md for details."
```
