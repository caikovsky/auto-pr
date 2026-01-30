# Session State

> Read this first when resuming. Keep under 50 lines.

## Current Status

**MIGRATION COMPLETE + ENHANCEMENTS** - PR #2 open for review

## Features Implemented

- ✅ Full Python CLI (`autopr`)
- ✅ AI providers: Gemini, Copilot, Agent
- ✅ PR update support (detect existing, prompt user)
- ✅ Prompt customization via config file
- ✅ All 8 migration phases complete

## Key Commands

```bash
uv run autopr --help           # Full CLI
uv run autopr --dry-run        # Preview
uv run autopr --update         # Update existing PR
uv run autopr --test           # Compare AI providers
```

## Config File

`~/.config/autopr/config.toml` - single source of truth for:
- AI provider preference
- Base branch
- Prompt instructions (customizable)
- Output rules (customizable)

## Design Rules

- **Single source of truth**: Config file, no hardcoded fallbacks
- **User choice**: Always prompt before destructive actions
- **Immutable entities**: All domain models are frozen

## Branch

`feature/python-migration` on `caikovsky/auto-pr`
PR #2: https://github.com/caikovsky/auto-pr/pull/2
