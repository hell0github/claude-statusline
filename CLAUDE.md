# Claude Statusline - Development Guide

## Project Overview

**cc-statusline** is a real-time usage tracking statusline plugin for Claude Code that uses a shim architecture for clean separation of interface and implementation.

**Repository**: `~/Projects/cc-statusline` (serves as both development and deployment location)
**Branch**: `ccusage_reset` (active development)
**Remote**: `git@github.com:hell0github/claude-statusline-dev.git`

## Architecture

### Two-Layer Design

**Layer 1: Interface (Shim)**
- Location: `~/.claude/statusline.sh`
- Purpose: Lightweight wrapper that Claude Code calls
- Implementation: 2-line bash script that delegates to actual implementation
- Stable: Rarely changes, provides consistent interface

**Layer 2: Implementation**
- Location: `~/Projects/cc-statusline/src/statusline.sh`
- Purpose: Actual statusline logic and rendering
- Flexible: Can be reorganized, updated without affecting interface

```
Claude Code
    ↓
~/.claude/statusline.sh (2 lines)
    ↓
~/Projects/cc-statusline/src/statusline.sh (main logic)
    ↓ (optionally sources)
~/Projects/cc-statusline/src/statusline-utils.sh (ccusage_r support)
```

## File Structure

```
~/Projects/cc-statusline/          # Git repository (dev + deploy combined)
├── src/                           # Source code
│   ├── statusline.sh             # Main implementation (~460 lines)
│   └── statusline-utils.sh       # Optional: Official reset tracking (~100 lines)
├── config/                        # Configuration files
│   ├── config.json               # User configuration (gitignored)
│   └── config.example.json       # Template with defaults
├── data/                          # Runtime data (gitignored)
│   ├── .official_weekly_cache    # Cache for ccusage_r calculations
│   ├── .statusline_prev_projection
│   ├── statusline-data.json
│   └── statusline-data.json.backup
├── .claude/                       # Project-specific Claude Code settings
│   └── settings.local.json       # Permissions & output style
├── screenshots/                   # Documentation assets
│   └── statusline.png
├── install.sh                     # Installation script
├── README.md                      # User-facing documentation
├── CLAUDE.md                      # This file (development guide)
├── LICENSE
└── .gitignore                     # Excludes config/config.json, data/*

~/.claude/                         # User's Claude Code directory
└── statusline.sh                 # 2-line shim (created by install.sh)
```

## Key Components

### Main Script (src/statusline.sh)

**Path Resolution**:
```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/../config/config.json"
```

**Responsibilities**:
- Parse JSON input from Claude Code (stdin)
- Load and apply user configuration
- Query ccusage for usage data
- Calculate multi-layer progress visualization
- Render formatted statusline output

### Utilities (src/statusline-utils.sh)

**Optional module for ccusage_r scheme**:
- `timestamp_to_iso()` - Convert Unix timestamp to ISO 8601
- `get_anthropic_period()` - Calculate current Anthropic weekly period
- `get_official_weekly_cost()` - Sum costs within official reset period

**Usage**: Sourced conditionally when `tracking.weekly_scheme = "ccusage_r"`

### Configuration (config/config.json)

**User-specific settings** (gitignored):
- Subscription plan (pro/max5x/max20x)
- Usage limits (weekly, context, cost)
- Display preferences (bar length, colors)
- Multi-layer thresholds
- Optional: Official reset date for ccusage_r tracking

## Development Guidelines

### Testing Changes

1. **Test shim delegation**:
```bash
# Verify shim points to correct location
cat ~/.claude/statusline.sh

# Test execution manually
echo '{"workspace":{"current_dir":"~"},"transcript_path":""}' | ~/Projects/cc-statusline/src/statusline.sh
```

2. **Test with Claude Code**:
```bash
# Restart Claude Code to reload statusline
# Verify output appears correctly
```

3. **Test ccusage_r (if enabled)**:
```bash
# Source utils and test period calculation
source ~/Projects/cc-statusline/src/statusline-utils.sh
get_anthropic_period 1728417600  # Example timestamp
```

### Path Reference Conventions

**Always use relative paths from SCRIPT_DIR**:
- Config: `$SCRIPT_DIR/../config/config.json`
- Utils: `$SCRIPT_DIR/statusline-utils.sh`
- Data: `$SCRIPT_DIR/../data/filename`

**Never hardcode**:
- ❌ `~/.claude/statusline-config.json`
- ❌ `$HOME/.claude/.official_weekly_cache`
- ✅ `$SCRIPT_DIR/../config/config.json`
- ✅ `$utils_dir/../data/.official_weekly_cache`

### Git Workflow

**Current branch**: `ccusage_reset`
- Contains ccusage_r scheme implementation
- Contains reorganization (src/, config/, data/)

**Commit conventions**:
- `feat:` - New features
- `fix:` - Bug fixes
- `refactor:` - Code reorganization
- `docs:` - Documentation updates
- `config:` - Configuration changes

**Before committing**:
```bash
# Verify gitignore works
git status  # Should NOT show config/config.json or data/*

# Stage changes
git add src/ config/config.example.json .gitignore README.md CLAUDE.md

# Commit with descriptive message
git commit -m "type: Description"
```

## Key Features Explained

### Multi-Layer Progress Visualization

**Concept**: Display shows different scales based on usage level
- Layer 1 (0-50%): Green, each bar segment = 5% actual usage
- Layer 2 (50-100%): Orange, each bar segment = 5% actual usage
- Layer 3 (100-105%+): Red, compressed scale for overage

**Configuration**: Thresholds in `config.json`
**Implementation**: Multipliers auto-calculated from thresholds (src/statusline.sh:46-48)

### ccusage_r Scheme (Official Reset Tracking)

**Problem**: ccusage uses ISO weeks (Mon-Sun), Anthropic uses custom cycles (e.g., Wed-Wed)

**Solution**: Optional tracking scheme that:
1. Accepts official reset date from Anthropic console
2. Calculates current period boundaries
3. Filters ccusage blocks by official period
4. Matches console percentage exactly

**When to use**: If you need weekly % to match Anthropic console for limit monitoring

### Shim Architecture Benefits

1. **Stability**: `~/.claude/settings.json` never changes
2. **Flexibility**: Reorganize implementation freely
3. **Development**: Easy to swap implementations for testing
4. **Updates**: `git pull` in implementation dir, shim unchanged

## Recent Changes

### Commit 88bcb35 (2025-10-02): Project Reorganization

**Changes**:
- Moved scripts → `src/`
- Moved configs → `config/`
- Created `data/` for runtime files
- Updated all path references to use relative paths
- Created 2-line shim in `~/.claude/statusline.sh`

**Migration**: Existing users need to:
1. Pull latest changes
2. Run `install.sh` to create new shim
3. Config automatically migrated to new location

### Commit 469077c: ccusage_r Scheme

**Added**: Optional official Anthropic reset schedule tracking
**Files**: `src/statusline-utils.sh` (new), config option `tracking.weekly_scheme`

### Commit 6856be8: Projection Separator Fix

**Fixed**: Off-by-one bug where projection separator disappeared at bar end position
**Impact**: Cross-layer projections now visible correctly

## Contributing

When making changes:
1. Update this CLAUDE.md if architecture changes
2. Update README.md if user-facing behavior changes
3. Test both with and without ccusage_r enabled
4. Verify .gitignore excludes user data
5. Use descriptive commit messages

---

**Last Updated**: 2025-10-02
**Active Branch**: ccusage_reset
