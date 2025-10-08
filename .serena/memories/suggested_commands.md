# Suggested Commands

## Development Commands

### Testing
```bash
# Test statusline manually (simulate Claude Code input)
echo '{"workspace":{"current_dir":"~"},"transcript_path":""}' | src/statusline.sh

# Test with specific directory
echo '{"workspace":{"current_dir":"/path/to/project"},"transcript_path":""}' | src/statusline.sh

# Test daily tracking functions (interactive)
source src/statusline-utils.sh
get_daily_cost "2025-10-08T15:00:00-07:00"
get_daily_period "2025-10-08T15:00:00-07:00"

# Test weekly cost function
get_official_weekly_cost "2025-10-08T15:00:00-07:00" 300
```

### Installation
```bash
# Run installer (recommended)
./install.sh

# Manual installation (create shim)
cat > ~/.claude/statusline.sh << 'EOF'
#!/bin/bash
exec "$HOME/Projects/cc-statusline/src/statusline.sh" "$@"
EOF
chmod +x ~/.claude/statusline.sh

# Copy and edit config
cp config/config.example.json config/config.json
nano config/config.json
```

### Configuration
```bash
# Edit user config
nano config/config.json

# View example config
cat config/config.example.json

# Validate JSON syntax
jq empty config/config.json && echo "Valid JSON" || echo "Invalid JSON"
```

### Debugging
```bash
# Check ccusage installation
npm list -g ccusage

# Test ccusage directly
ccusage blocks --active

# Check cache files
ls -lah data/
cat data/.daily_cache
cat data/.official_weekly_cache

# View shim script
cat ~/.claude/statusline.sh

# Check Claude Code settings
cat ~/.claude/settings.json | jq '.statusLine'
```

### Dependencies
```bash
# Install jq (macOS)
brew install jq

# Install jq (Linux)
sudo apt-get install jq

# Install ccusage globally
npm install -g ccusage@17.1.0

# Check dependency versions
jq --version
npm list -g ccusage
bash --version
```

## Git Commands

### Standard Workflow
```bash
# Check status
git status

# View current branch
git branch

# Create feature branch
git checkout -b feature-name

# Stage changes
git add .

# Commit with conventional prefix
git commit -m "feat: add new feature"
git commit -m "fix: resolve bug"
git commit -m "refactor: reorganize code"
git commit -m "docs: update documentation"

# Push to remote
git push origin feature-name
```

### Development Remotes
```bash
# View remotes
git remote -v

# Dev fork (for testing)
git push origin feature-name

# Production (stable releases)
# Usually done via PR/merge
```

## System Utilities (macOS)

```bash
# List files
ls -lah

# Find files
find . -name "*.sh"

# Search content
grep -r "pattern" src/

# Check running Claude Code processes
ps aux | grep claude

# Monitor file changes
ls -l ~/.claude/statusline.sh
stat src/statusline.sh

# Date utilities (macOS BSD)
date +%s                           # Unix timestamp
date -r 1234567890                 # Format timestamp
date -u -r 1234567890 +"%Y-%m-%d"  # UTC formatting
```

## When Task is Completed

### No automated testing or linting
This project does not have:
- Unit tests
- Integration tests
- Linting (shellcheck, etc.)
- Formatting tools (shfmt, etc.)
- CI/CD pipelines

### Manual verification steps
1. **Test manually**: Run statusline with echo command
2. **Visual check**: Restart Claude Code and verify statusline appears
3. **Config validation**: Ensure JSON is valid with `jq`
4. **Commit changes**: Use conventional commit prefixes
5. **Update docs**: Keep README.md and CLAUDE.md in sync if needed

### Restart Claude Code
After making changes to statusline.sh or config.json:
- Quit and restart Claude Code application
- Changes to the shim (~/.claude/statusline.sh) also require restart
