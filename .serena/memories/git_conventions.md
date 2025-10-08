# Git Conventions

## CRITICAL: Commit Authorship Policy

**⚠️ DO NOT include Claude Code co-authorship in commit messages**

This project has an explicit policy against AI co-authorship attribution:
- **NO** `🤖 Generated with [Claude Code](...)` footer
- **NO** `Co-Authored-By: Claude <noreply@anthropic.com>` trailer
- **Keep commits clean and professional**

This is explicitly documented in CLAUDE.md and must be followed.

## Commit Message Format

### Conventional Commit Prefixes
Use these prefixes for all commits:

- `feat:` - New features
  - Example: `feat: Add daily usage tracking with 5-hour projection`
  
- `fix:` - Bug fixes
  - Example: `fix: Correct percentage calculation in multi-layer display`
  
- `refactor:` - Code reorganization without behavior change
  - Example: `refactor: Simplify token rate format to [number]/min`
  
- `docs:` - Documentation changes
  - Example: `docs: Update README to document daily usage tracker feature`
  
- `chore:` - Maintenance tasks (dependencies, configs)
  - Example: `chore: Update ccusage version to 17.1.0`

### Commit Message Style
- **First line**: Brief summary (50-72 chars)
- **No period** at end of first line
- **Imperative mood**: "Add feature" not "Added feature" or "Adds feature"
- **Lowercase** after colon: `feat: add feature` not `feat: Add feature`
- **Body** (optional): Detailed explanation after blank line

### Examples of Good Commits
```
feat: Add burn-rate projection and token rate tracking
refactor: Simplify token rate format to [number]/min
docs: Update README to document daily usage tracker feature
fix: Handle missing official_reset_date gracefully
```

## Branch Strategy

### Active Branch
- `feature-daily-usage` - Current development branch for daily tracking features

### Branch Naming
- `feature-*` - New features
- `fix-*` - Bug fixes
- `refactor-*` - Code reorganization
- `docs-*` - Documentation updates

## Remotes

### Production Repository
- URL: `https://github.com/hell0github/claude-statusline.git`
- Purpose: Stable public releases
- Branch: `main` (typically)

### Development Fork
- URL: `git@github.com:hell0github/claude-statusline-dev.git`
- Purpose: Testing and development
- Active work happens here first

## Workflow

1. **Work on feature branch**: `feature-daily-usage`, `feature-xyz`
2. **Commit with conventional prefix**: `feat:`, `fix:`, etc.
3. **Push to dev fork**: For testing
4. **Merge to production**: After validation

## Recent Commit History (for reference)
```
0599e67 refactor: Simplify token rate format to [number]/min
3eac312 feat: Add burn-rate projection and token rate tracking
b06bbb9 docs: Update README to document daily usage tracker feature
68f252c feat: Simplify daily usage to two-layer system with 5-hour window projection
55debba feat: Add daily cost tracking and conditional section rendering
```

This shows the project follows the documented conventions consistently.
