# Auto-PR: AI-Powered Pull Request Generator

A CLI tool that uses **AI (Gemini)** to automatically create intelligent, insightful GitHub Pull Requests. It analyzes your code changes, compares them to Jira ticket requirements, and generates comprehensive PR descriptions that give reviewers the context they need.

## What It Does

Instead of manually writing PR descriptions, this tool:

1. **Extracts the Jira ticket** from your branch name
2. **Fetches ticket details** (title, description, requirements) via Atlassian CLI
3. **Analyzes your git changes** (commits, diff, modified files)
4. **Uses AI to understand** what you implemented and how it relates to the ticket
5. **Generates an insightful PR description** with:
   - Summary of changes and how they fulfill the ticket requirements
   - Technical approach explanation
   - Impacted areas of the codebase
   - Key files reviewers should focus on
   - Testing considerations

## Example Output

```markdown
## Summary
This PR implements the user authentication flow as specified in PROJ-123. 
It adds OAuth2 integration with the identity provider and handles token 
refresh automatically.

## What Changed
- Added AuthenticationService with OAuth2 support
- Implemented token refresh mechanism in TokenManager
- Added secure storage for credentials using Keychain
- Updated LoginViewController to use new auth flow

## Technical Approach
The implementation uses the AppAuth library for OAuth2 compliance. Tokens 
are securely stored in the iOS Keychain and automatically refreshed when 
expired. The auth state is observed via Combine publishers.

## Impacted Areas
- Authentication module
- Network layer (added auth interceptor)
- Login/Signup flows

## Key Files to Review
- `AuthenticationService.swift` - Core auth logic, verify OAuth2 flow
- `TokenManager.swift` - Token refresh logic, check edge cases
- `KeychainStorage.swift` - Secure storage, verify encryption

## Testing Considerations
- Test login with valid/invalid credentials
- Verify token refresh after expiration
- Test logout clears all stored tokens
- Check deep link handling during auth

## Jira Ticket
https://company.atlassian.net/browse/PROJ-123
```

## Prerequisites

```bash
# Install required tools
brew install gh jq
brew install atlassian-labs/tap/acli

# Install an AI CLI (any one of these)
brew install gemini-cli   # Google Gemini (recommended)
# OR
brew install llm          # Simon Willison's LLM
# OR  
brew install mods         # Charmbracelet Mods
# OR
brew install ollama       # Local models

# Authenticate
gh auth login
acli auth login
```

## Setup

The tool auto-detects installed AI CLI tools. Supported:

| CLI | Install | Notes |
|-----|---------|-------|
| `gemini` | `brew install gemini-cli` | Google Gemini (recommended) |
| `claude` | Anthropic CLI | Claude models |
| `llm` | `brew install llm` | Multiple providers |
| `mods` | `brew install mods` | Charmbracelet |
| `ollama` | `brew install ollama` | Local models |

Run setup to see detected tools:
```bash
auto-pr --setup
```

### 3. Add to PATH

Add to `~/.zshrc`:
```bash
export PATH="$PATH:/path/to/automate-pr"
```

## Usage

```bash
cd /path/to/your/repo

# Create a feature branch with Jira ticket
git checkout -b task/PROJ-123-add-feature

# Make your changes and commit
git add .
git commit -m "feat: implement feature X"

# Preview the AI-generated PR
auto-pr --dry-run

# Create the PR
auto-pr

# Create as draft
auto-pr --draft
```

## Options

| Option | Description |
|--------|-------------|
| `--dry-run` | Preview PR without creating |
| `--draft`, `-d` | Create as draft PR |
| `--base`, `-b` | Base branch (default: main) |
| `--setup` | Configure Gemini API key |
| `--setup-help` | Show full setup instructions |
| `--help`, `-h` | Show help |

## How the AI Analysis Works

The tool sends the following context to Gemini AI:

1. **Jira ticket info**: Title, description, type, requirements
2. **Git commits**: All commit messages in your branch
3. **Changed files**: List of modified files
4. **Code diff**: Actual code changes (truncated if large)

The AI then:
- Understands what the ticket asked for
- Analyzes what your code actually does
- Identifies the relationship between requirements and implementation
- Highlights important changes for reviewers
- Suggests testing approaches

## Branch Naming

The tool extracts Jira tickets from branch names:

| Branch | Extracted Ticket |
|--------|-----------------|
| `task/TLAB-2023` | TLAB-2023 |
| `feature/PROJ-123-login` | PROJ-123 |
| `bugfix/ABC-456` | ABC-456 |

## Configuration

Config is stored at `~/.config/auto-pr/config`:

```bash
AI_CLI="gemini"  # or claude, llm, mods, ollama
```

## Troubleshooting

### "No AI CLI tool found"
Install one of the supported AI CLIs:
```bash
brew install gemini-cli
```

### "Atlassian CLI is not authenticated"
```bash
acli auth login
```

### "Could not extract Jira ticket"
Ensure your branch name contains a ticket ID like `PROJ-123`.

### AI output not relevant
- Make sure you have commits on your branch
- The more code changes, the better the analysis
- Check that Jira ticket has a description

## Privacy

- Code diffs are sent to Google's Gemini API
- Jira data is fetched locally via acli
- No data is stored by this tool beyond the API key

## License

MIT
