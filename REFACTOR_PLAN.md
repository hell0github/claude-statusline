# Statusline Refactoring Plan

## Current Problem
All calculations run regardless of toggle settings. Toggles only control display, not computation.

## Target Structure

```bash
# ============================================================================
# SECTION 1: ccusage blocks (shared by COST and TIMER)
# ============================================================================
if [ "$SHOW_COST" = "true" ] || [ "$SHOW_TIMER" = "true" ]; then
    WINDOW_DATA=$(ccusage blocks ...)
    BLOCK=$(...)

    if [ -n "$BLOCK" ]; then
        # COST SECTION calculations
        if [ "$SHOW_COST" = "true" ]; then
            COST=$(...)
            PROJECTED_COST=$(...)
            # Calculate actual_pct, visual_pct, layers, multipliers
            # Build PROGRESS_BAR with projection separator
        fi

        # TIMER SECTION calculations
        if [ "$SHOW_TIMER" = "true" ]; then
            REMAINING_MINS=$(...)
            END_TIME=$(...)
            # Format TIME_LEFT, RESET_TIME
        fi
    fi
fi

# ============================================================================
# SECTION 2: CONTEXT (independent)
# ============================================================================
if [ "$SHOW_CONTEXT" = "true" ] && [ -f "$TRANSCRIPT_PATH" ]; then
    # Parse transcript for tokens
    TOKEN_DATA=$(tail ... | grep ... | awk ...)
    CACHED_TOKENS=$(...)
    FRESH_TOKENS=$(...)
    CONTEXT_TOKENS=$(...)
    # Build CTX_PROGRESS_BAR
fi

# ============================================================================
# SECTION 3: WEEKLY (independent)
# ============================================================================
if [ "$SHOW_WEEKLY" = "true" ]; then
    if [ "$WEEKLY_SCHEME" = "ccusage_r" ] && ...; then
        WEEK_COST=$(get_official_weekly_cost ...)
    else
        WEEKLY_DATA=$(ccusage weekly ...)
        WEEK_COST=$(...)
    fi

    # Apply baseline offset
    WEEKLY_PCT=$(...)
fi

# ============================================================================
# SECTION 4: DAILY (independent, already correct)
# ============================================================================
if [ "$SHOW_DAILY" = "true" ] && [ -n "$OFFICIAL_RESET_DATE" ]; then
    DAILY_COST=$(get_daily_cost ...)
    # Calculate projection, layers, progress bar
fi

# ============================================================================
# SECTION 5: SESSIONS (independent)
# ============================================================================
if [ "$SHOW_SESSIONS" = "true" ]; then
    ACTIVE_SESSIONS=$(find ... | wc -l)
fi

# ============================================================================
# DISPLAY ASSEMBLY
# ============================================================================
STATUSLINE_SECTIONS=()
[[ "$SHOW_DIRECTORY" == "true" ]] && STATUSLINE_SECTIONS+=(...)
[[ "$SHOW_CONTEXT" == "true" ]] && STATUSLINE_SECTIONS+=(...)
[[ "$SHOW_COST" == "true" ]] && STATUSLINE_SECTIONS+=(...)
[[ "$SHOW_DAILY" == "true" ]] && [...] && STATUSLINE_SECTIONS+=(...)
[[ "$SHOW_WEEKLY" == "true" ]] && STATUSLINE_SECTIONS+=(...)
[[ "$SHOW_TIMER" == "true" ]] && STATUSLINE_SECTIONS+=(...)
[[ "$SHOW_SESSIONS" == "true" ]] && STATUSLINE_SECTIONS+=(...)
```

## Dependencies Resolved
- COST and TIMER share ccusage blocks call - conditional on (SHOW_COST || SHOW_TIMER)
- CONTEXT is independent - conditional on SHOW_CONTEXT
- WEEKLY is independent - conditional on SHOW_WEEKLY
- DAILY is independent (already done) - conditional on SHOW_DAILY
- SESSIONS is independent - conditional on SHOW_SESSIONS
