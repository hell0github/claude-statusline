# Key Design Patterns and Implementation Details

## 1. Shim Architecture Pattern

**Problem**: Plugin code needs to be updateable without changing Claude Code configuration.

**Solution**: Two-layer indirection
```
Claude Code config points to: ~/.claude/statusline.sh (shim)
                              ↓
                              Delegates to: ~/Projects/cc-statusline/src/statusline.sh
```

**Benefits**:
- Stable interface for Claude Code
- Flexible implementation reorganization
- Easy development without touching ~/.claude/ repeatedly

## 2. Multi-Layer Progress Visualization

**Concept**: Different visual scaling at different usage thresholds for better feedback.

**Implementation**:
- **Layer 1** (0-30%): Slower visual progression (multiplier < 1)
- **Layer 2** (30-50%): Medium visual progression
- **Layer 3** (50-100%): Faster visual progression (multiplier > 1)

**Auto-calculated multipliers**: System automatically calculates display speed multipliers to ensure smooth visual transitions between layers.

**Color coding**: Each layer has configurable color (green/orange/red) to provide visual urgency feedback.

## 3. Dual Tracking Schemes

**ccusage** (Default)
- Uses ISO week boundaries (Monday-Sunday)
- Simple, standard calendar weeks
- May not match Anthropic console percentages

**ccusage_r** (Official Reset Alignment)
- Filters ccusage blocks by official reset schedule
- Requires `official_reset_date` configuration
- Matches Anthropic console percentages exactly
- Enables daily usage tracking

## 4. Caching Strategy

**Problem**: ccusage calls are expensive (read all transcript files).

**Solution**: Time-based caching with period validation.

**Daily cache** (`data/.daily_cache`):
- Format: `period_start|cost`
- Invalidated when period changes or cache age exceeds duration
- Prevents redundant ccusage calls within same day

**Weekly cache** (`data/.official_weekly_cache`):
- Format: `period_start|cost`
- Used for ccusage_r scheme
- Default TTL: 5 minutes (configurable)

**Cache validation**:
- Check if period_start matches current period
- Check file modification time (age)
- Regenerate if stale or period mismatch

## 5. Conditional Section Rendering

**Performance optimization**: Only compute sections that are enabled.

**Implementation**:
```bash
if [ "$SHOW_DAILY" = "true" ]; then
  # Only calculate daily cost if section is enabled
  DAILY_COST=$(get_daily_cost "$OFFICIAL_RESET_DATE_ISO")
fi
```

**Benefits**:
- Skips expensive ccusage calls for disabled features
- Reduces latency for statusline rendering
- User controls performance vs feature tradeoff

## 6. Daily Projection Algorithm

**Goal**: Project end-of-day cost using 5-hour window data.

**Formula**:
```
daily_projected = daily_cost - window_cost + projected_window_cost
```

**Rationale**:
- `daily_cost` includes current window cost
- Subtract current window cost to avoid double-counting
- Add projected window cost (linear extrapolation to 5-hour end)

**Display**: Shows both current daily % and projected daily % on progress bar.

## 7. Path Resolution Pattern

**Principle**: Always resolve paths relative to script location.

**Pattern**:
```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/../config/config.json"
DATA_DIR="$SCRIPT_DIR/../data"
```

**Why**: Ensures script works regardless of:
- Where it's invoked from
- Symlinks
- Different installation paths

## 8. Progressive Bar Rendering with Projection

**Visual representation**: Current usage + projected usage on same bar.

**Implementation**:
- Calculate filled blocks for current usage
- Calculate projected position
- Render current blocks in one color
- Render projection block(s) in dimmed/different color
- Fill remaining with empty blocks

**Color logic**:
- Determine layer based on percentage
- Apply appropriate color from configuration
- Use dimmed variant for projection

## 9. Date/Time Handling for Reset Periods

**Key functions** (in statusline-utils.sh):

**`get_anthropic_period()`**:
- Takes `next_reset` ISO timestamp
- Calculates current period boundaries
- Returns start/end timestamps and elapsed percentage

**`get_daily_period()`**:
- Calculates daily reset within weekly cycle
- Aligns to same time as weekly reset
- Returns daily period boundaries

**Platform consideration**:
- Uses macOS BSD `date` command syntax
- Careful with timezone handling
- ISO 8601 format for all timestamps

## 10. Configuration-Driven Architecture

**Centralized config**: Single JSON file (`config/config.json`)

**Config structure**:
- User preferences (plan, limits)
- Display settings (bar length, colors)
- Feature toggles (section visibility)
- Tracking options (scheme, reset date)

**Loading pattern**:
```bash
CONFIG=$(cat "$CONFIG_FILE")
VALUE=$(echo "$CONFIG" | jq -r '.path.to.value // "default"')
```

**Benefits**:
- No hardcoded values in implementation
- Easy customization without code changes
- Validation at single point
- Template (config.example.json) for documentation
