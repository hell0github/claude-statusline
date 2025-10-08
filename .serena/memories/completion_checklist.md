# Task Completion Checklist

## When a Development Task is Completed

This project **does not have**:
- ❌ Automated unit tests
- ❌ Integration tests
- ❌ Linting tools (shellcheck, etc.)
- ❌ Code formatting tools (shfmt, etc.)
- ❌ CI/CD pipelines
- ❌ Pre-commit hooks

Therefore, completion relies on **manual verification**.

## Completion Steps

### 1. Manual Testing
```bash
# Test the statusline directly
echo '{"workspace":{"current_dir":"~"},"transcript_path":""}' | src/statusline.sh

# Verify output format
# Expected: Should see formatted statusline with sections

# Test with actual Claude Code project directory
echo '{"workspace":{"current_dir":"~/Projects/cc-statusline"},"transcript_path":""}' | src/statusline.sh
```

### 2. Validate Configuration (if config changed)
```bash
# Check JSON syntax
jq empty config/config.json && echo "✓ Valid JSON" || echo "✗ Invalid JSON"

# Verify config values load correctly
jq '.user.plan' config/config.json
jq '.sections.show_daily' config/config.json
```

### 3. Test Utility Functions (if utils changed)
```bash
# Source utilities
source src/statusline-utils.sh

# Test date functions
get_daily_period "2025-10-08T15:00:00-07:00"

# Test cost functions (requires ccusage)
get_daily_cost "2025-10-08T15:00:00-07:00"
```

### 4. Visual Verification
```bash
# Restart Claude Code application
# Check that statusline appears correctly
# Verify colors, formatting, sections enabled/disabled as expected
```

### 5. Documentation Updates
- [ ] Update README.md if user-facing changes
- [ ] Update CLAUDE.md if development guidelines changed
- [ ] Update config.example.json if new config options added
- [ ] Keep documentation in sync with code

### 6. Git Commit

**Follow git conventions**:
```bash
# Stage changes
git add [files]

# Commit with conventional prefix
# IMPORTANT: NO Claude Code co-authorship!
git commit -m "feat: description"
git commit -m "fix: description"
git commit -m "refactor: description"
git commit -m "docs: description"

# Verify commit message
git log -1
```

**Reminder**: Do NOT include:
- ❌ `🤖 Generated with [Claude Code](...)`
- ❌ `Co-Authored-By: Claude <noreply@anthropic.com>`

### 7. Push (if ready)
```bash
# Check current branch
git branch

# Push to dev fork for testing
git push origin feature-branch-name

# Production push (after validation)
# Usually done via PR/merge process
```

## Common Verification Scenarios

### Feature Addition
- [ ] Test new feature manually
- [ ] Verify it doesn't break existing features
- [ ] Check config.example.json has new options (if applicable)
- [ ] Update README with feature documentation
- [ ] Test with feature enabled and disabled

### Bug Fix
- [ ] Verify bug is actually fixed
- [ ] Test edge cases
- [ ] Ensure fix doesn't introduce regressions
- [ ] Document fix if non-obvious

### Refactoring
- [ ] Verify behavior is unchanged
- [ ] Test all affected code paths
- [ ] Confirm performance characteristics
- [ ] Update comments if structure changed

### Documentation
- [ ] Verify accuracy of information
- [ ] Check for broken links
- [ ] Ensure examples are up-to-date
- [ ] Validate code snippets actually work

## Integration Verification

### After Installation Changes
```bash
# Run installer in test mode
./install.sh

# Verify shim is created
cat ~/.claude/statusline.sh

# Check shim is executable
ls -l ~/.claude/statusline.sh

# Test shim directly
echo '{"workspace":{"current_dir":"~"},"transcript_path":""}' | ~/.claude/statusline.sh
```

### After Config Changes
```bash
# Validate JSON
jq empty config/config.json

# Check all referenced colors exist
# Check all threshold percentages are valid (0-100)
# Verify paths are accessible
```

## Final Checklist

Before considering task complete:
- [ ] Manual testing passed
- [ ] Documentation updated (if needed)
- [ ] Config validated (if changed)
- [ ] Git commit follows conventions
- [ ] No Claude Code co-authorship in commit
- [ ] Changes tested in actual Claude Code environment (if feasible)
- [ ] No broken functionality
- [ ] Code follows project style conventions
