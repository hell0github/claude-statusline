# File Structure

## Directory Layout

```
~/Projects/cc-statusline/          # Installation directory
├── src/                           # Source code
│   ├── statusline.sh             # Main implementation (entry point)
│   └── statusline-utils.sh       # Daily/weekly tracking utilities
├── config/                        # Configuration
│   ├── config.json               # User settings (gitignored)
│   └── config.example.json       # Template with defaults
├── data/                          # Runtime data (gitignored)
│   ├── .daily_cache              # Daily cost cache
│   ├── .official_weekly_cache    # Weekly cost cache (ccusage_r)
│   └── statusline-data.json      # Legacy cache (deprecated)
├── example/                       # Example screenshot
│   └── statusline.png
├── install.sh                     # Automated installer
├── README.md                      # User documentation
├── CLAUDE.md                      # Development guide (gitignored)
├── LICENSE                        # MIT license
└── .gitignore                     # Git exclusions

~/.claude/
└── statusline.sh                 # Shim script (delegates to src/)
```

## Key Files

### src/statusline.sh
- **Purpose**: Main entry point for statusline rendering
- **Input**: JSON from stdin (workspace info, transcript path)
- **Output**: Formatted statusline to stdout
- **Responsibilities**:
  - Config loading
  - 5-hour window tracking
  - Context window calculation
  - Multi-layer progress bar rendering
  - Section assembly (directory, context, cost, daily, weekly, timer, sessions)

### src/statusline-utils.sh
- **Purpose**: Utility functions for date/time and cost tracking
- **Key Functions**:
  - `get_anthropic_period()` - Calculate official reset period boundaries
  - `get_daily_period()` - Calculate daily reset boundaries
  - `get_daily_cost()` - Fetch daily cost with caching
  - `get_official_weekly_cost()` - Fetch weekly cost for ccusage_r scheme
  - `timestamp_to_iso()` - Convert Unix timestamp to ISO format

### config/config.example.json
- **Purpose**: Template configuration with all options documented
- **Structure**:
  - `user` - Plan selection (pro/max5x/max20x)
  - `limits` - Weekly/context/cost limits per plan
  - `display` - Bar length, performance tuning
  - `colors` - ANSI color codes
  - `multi_layer` - 3-layer thresholds for 5-hour window
  - `daily_layer` - 2-layer thresholds for daily tracking
  - `sections` - Toggle visibility of each section
  - `tracking` - Weekly scheme, reset date, baseline, caching

### ~/.claude/statusline.sh (Shim)
- **Purpose**: Stable interface between Claude Code and implementation
- **Content**: 2-line script that delegates to src/statusline.sh
- **Benefit**: Allows implementation reorganization without changing Claude Code config

## Gitignored Items
- `config/config.json` - User-specific settings
- `data/` - Runtime cache files
- `CLAUDE.md` - Development guide (private)
- `*.log` - Log files
- `*.backup.*` - Backup files
