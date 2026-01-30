# Session State

> Read this first when resuming. Keep under 50 lines.

## Current Phase

**Phase 4: Application Layer** (next)

## Progress

| Phase | Status |
|-------|--------|
| 1. Project Setup | ✅ Done |
| 2. Domain Layer | ✅ Done |
| 3. Infrastructure | ✅ Done |
| 4. Application | ⏳ Next |
| 5-8. Remaining | 🔲 Pending |

## What's Been Built

```
auto_pr/
├── cli/app.py                    # Basic CLI (uv run auto-pr --help)
├── domain/
│   ├── entities/                 # JiraTicket, GitContext, PRDescription
│   ├── interfaces/               # AIProvider, JiraClient, GitClient, PRClient
│   └── exceptions.py             # Full error hierarchy
└── infrastructure/
    ├── subprocess_runner.py      # check_tool_exists, run_command
    ├── git/client.py             # GitClientImpl
    ├── jira/acli_client.py       # AcliJiraClient
    ├── ai/{gemini,copilot,agent} # AI providers
    └── github/gh_client.py       # GhPRClient
```

## Next Action

**Phase 4**: Application layer (use cases + services):
1. `services/prompt_builder.py` - Build AI prompt from ticket + context
2. `services/ai_selector.py` - Auto-detect or select AI provider
3. `use_cases/generate_pr.py` - Main use case
4. `use_cases/compare_ai.py` - --test comparison mode
5. `use_cases/create_pr.py` - Create PR via gh

## Quick Commands

```bash
cd /Users/caique-maurano/Script/automate-pr
uv run auto-pr --help
uv run python -c "from auto_pr.infrastructure import *; print('OK')"
```

## Branch

`feature/python-migration` on `caikovsky/auto-pr`
