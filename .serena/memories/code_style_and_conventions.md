# Code Style and Conventions

## Bash Scripting Style

### Variable Naming
- **UPPERCASE** for constants and configuration variables
  - Examples: `SCRIPT_DIR`, `CONFIG_FILE`, `WEEKLY_LIMIT`, `BAR_LENGTH`
- **snake_case** for function names
  - Examples: `get_daily_cost()`, `get_anthropic_period()`, `timestamp_to_iso()`
- **lowercase** for local loop variables
  - Examples: `i`, `timestamp`, `cache_age`

### File Organization
- **Shebang**: Always start with `#!/bin/bash`
- **Set flags**: Use `set -e` for error handling where appropriate
- **Script directory detection**: 
  ```bash
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  ```

### Path Conventions
**CRITICAL**: Always use relative paths from `$SCRIPT_DIR`
- Config path: `$SCRIPT_DIR/../config/config.json`
- Data cache: `$SCRIPT_DIR/../data/filename`
- Utils sourcing: `source "$SCRIPT_DIR/statusline-utils.sh"`

### Configuration Loading
- Load JSON config with jq
- Provide defaults for optional values
- Validate required fields (e.g., `official_reset_date` for daily tracking)

### Code Structure
1. Variable initialization (config loading)
2. Helper functions (if needed)
3. Main logic with conditional sections
4. Output construction
5. Final echo to stdout

### Comments
- Use comments to explain **why**, not **what**
- Mark major sections with clear headers
- Document complex calculations (e.g., multi-layer multipliers)
- Explain date/time manipulation logic

### Error Handling
- Silent failures for optional features (e.g., missing ccusage returns "Window tracking unavailable")
- Exit with error codes in install scripts
- Validate critical dependencies before use

### Performance Considerations
- Cache expensive operations (ccusage calls)
- Use conditional rendering - skip disabled sections entirely
- Avoid redundant calculations
- Minimize subshells where possible
