# Claude Statusline - Development Guide

## Project Overview

Real-time usage tracking statusline for Claude Code using shim architecture.

**Repository**: `~/Projects/cc-statusline`
**Active Branch**: `feature-daily-usage`
**Remotes**:
- Dev fork: `git@github.com:hell0github/claude-statusline-dev.git`
- Production: `https://github.com/hell0github/claude-statusline.git`

## Development Principles

### Open-Closed Principle
**All configuration values MUST be loaded from config files. NEVER hardcode values in scripts or comments.**

**Rules:**
1. **No hardcoded config values in code**
   - ❌ `LAYER1_THRESHOLD=14.29`
   - ✅ `LAYER1_THRESHOLD=$(calculate from config multiplier)`

2. **No hardcoded values in comments**
   - ❌ `# Layer 1: 0-14.29% actual`
   - ✅ `# Layer 1: 0-1.0×base threshold`

3. **Config-driven thresholds**
   - All layer thresholds use `threshold_multiplier` notation
   - Base thresholds calculated at runtime from limits or dynamic values
   - Formula: `layer_threshold = base_threshold × threshold_multiplier`

4. **Examples:**
   ```bash
   # 5-hour window: base = COST_LIMIT
   LAYER1_THRESHOLD=$(awk "BEGIN {print $COST_LIMIT * $LAYER1_THRESHOLD_MULT}")

   # Daily static: base = weekly_limit / 7
   DAILY_BASE=$(awk "BEGIN {print ($WEEKLY_LIMIT / 7.0) / $WEEKLY_LIMIT * 100}")

   # Daily dynamic: base = recommend value
   DAILY_BASE=$WEEKLY_DISPLAY_VALUE

   # Context: base = CONTEXT_LIMIT
   CTX_LAYER1=$(awk "BEGIN {print $CONTEXT_LIMIT * $CTX_LAYER1_THRESHOLD_MULT}")
   ```

**Benefits:**
- Single source of truth (config files)
- Easy to adjust thresholds without code changes
- Consistent behavior across all sections
- Self-documenting through config structure

## File Structure

```
~/Projects/cc-statusline/
├── src/
│   ├── statusline.sh              # Main implementation
│   └── statusline-utils.sh        # Daily/weekly tracking utilities
├── tools/
│   └── calibrate_weekly_usage.sh  # Weekly usage calibration tool
├── config/
│   ├── config.json                # User config (gitignored)
│   └── config.example.json        # Template with defaults
├── data/                           # Runtime cache (gitignored)
│   ├── .daily_cache
│   └── .official_weekly_cache
├── install.sh
├── README.md
├── CLAUDE.md
└── .gitignore

~/.claude/
└── statusline.sh                   # 2-line shim → delegates to src/statusline.sh
```

## Features

### Core Features
- **5-hour window tracker** - Current session cost with projection
- **Daily usage tracker** - 24-hour cycle aligned with weekly reset (2-layer: normal/exceeding)
- **Weekly usage tracker** - Full week percentage
- **Context window tracker** - Token usage monitoring
- **Timer** - Countdown to next reset

### Key Implementations
- **Shim architecture** - Stable interface (`~/.claude/statusline.sh`) delegates to implementation
- **Multi-layer progress bars** - Auto-scaled visualization (different multipliers per threshold)
- **ccusage_r scheme** - Matches Anthropic console % (filters by official reset schedule)
- **Daily cost tracking** - `get_daily_cost()` with caching, aligned to weekly reset time
- **Daily projection** - Uses 5-hour window: `daily_cost - window_cost + projected_window_cost`
- **Conditional rendering** - Only computes enabled sections for performance
- **Configurable colors** - Per-layer color customization

## Configuration

**Path**: `config/config.json`

**Key settings**:
- `user.plan` - pro/max5x/max20x
- `limits.weekly`, `limits.cost` - Usage limits
- `multi_layer` - 3-layer thresholds + colors for weekly/5-hour window
- `daily_layer` - 2-layer thresholds + colors (14.29% normal, 21.44% exceeding)
- `sections.show_*` - Toggle individual sections
- `tracking.weekly_scheme` - "ccusage" (ISO week) or "ccusage_r" (official reset)
- `tracking.official_reset_date` - Required for ccusage_r and daily tracking

## Tools

### Weekly Usage Calibrator

**Path**: `tools/calibrate_weekly_usage.sh`

Aligns statusline weekly tracking with Anthropic's official usage percentage.

**Purpose**: Compensates for untracked costs:
- Deleted/compacted transcripts (clear/compact commands)
- Extended context usage (Sonnet 4 [1m] pricing differences)
- Any costs not captured by ccusage

**Requirements**:
- `tracking.weekly_scheme` must be set to `"ccusage_r"`
- `tracking.official_reset_date` must be configured

**Usage**:

**Option 1: Slash Command (Recommended)**
```bash
# Global slash command available in all Claude Code sessions
/calibrate_weekly_usage_baseline 18.5
```

**Option 2: Direct Script**
```bash
# Run script directly from project root
tools/calibrate_weekly_usage.sh 18.5

# Example output:
#   Official Usage (Anthropic): 18.5%
#   Tracked Usage (ccusage_r):  12.3%
#   Gap (untracked costs):      6.2%
#
#   Baseline updated: 10% → 6.2%
#   Statusline will now show: 18.5%
```

**When to calibrate**:
- After weekly reset (to zero out baseline if needed)
- When you notice drift between statusline and console
- After significant transcript cleanup operations
- Weekly as a maintenance routine

**Slash Command Setup**:
The calibrator is available as a global slash command in `~/.claude/commands/calibrate_weekly_usage_baseline.md`. This makes it accessible from any Claude Code session without needing to navigate to the project directory.

## Development

### Testing
```bash
# Test manually
echo '{"workspace":{"current_dir":"~"},"transcript_path":""}' | src/statusline.sh

# Test daily functions
source src/statusline-utils.sh
get_daily_cost "2025-10-08T15:00:00-07:00"

# Test calibrator
tools/calibrate_weekly_usage.sh 15.0
```

### Path Conventions
- Always use relative paths from `$SCRIPT_DIR`
- Config: `$SCRIPT_DIR/../config/config.json`
- Data: `$SCRIPT_DIR/../data/filename`

### Git Workflow

**IMPORTANT: Commit Authorship Policy**
- **DO NOT** include Claude Code co-authorship in commit messages
- **DO NOT** add `🤖 Generated with [Claude Code](...)` footer
- **DO NOT** add `Co-Authored-By: Claude <noreply@anthropic.com>` trailer
- Keep commits clean and professional

**Commit conventions**:
- `feat:` New features
- `fix:` Bug fixes
- `refactor:` Code reorganization
- `docs:` Documentation
- `chore:` Maintenance

### Recent Updates

**v2.2** (2025-10-06) - Weekly Usage Calibration Tool
- `tools/calibrate_weekly_usage.sh` - Aligns tracking with official usage
- Compensates for untracked costs (deleted transcripts, extended context)
- Interactive baseline adjustment with safety validations

**v2.1** (2025-10-05) - Daily Usage Tracking
- Two-layer daily system (14.29% normal, 21.44% exceeding)
- 5-hour window projection integration
- `get_daily_cost()` with caching

**v2.0** (2025-10-05) - Daily Foundation
- `get_daily_period()` function
- Conditional section rendering
- Configurable layer colors

**v1.5** (2025-10-02) - Project Reorganization
- src/, config/, data/ structure
- 2-line shim architecture

---

**Last Updated**: 2025-10-06
