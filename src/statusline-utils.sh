#!/usr/bin/env bash
# statusline-utils.sh - Utility functions for official Anthropic weekly reset tracking
# This file provides ccusage_r scheme support for matching official console reset schedule

# Constants
readonly WEEK_DURATION_SECONDS=604800  # 7 days
readonly DAY_DURATION_SECONDS=86400    # 24 hours

# Convert Unix timestamp to ISO 8601 format
# Usage: timestamp_to_iso <timestamp>
# Returns: ISO 8601 string like "2025-10-01T15:00:00Z"
timestamp_to_iso() {
    local timestamp="${1:?Missing timestamp}"
    date -u -r "$timestamp" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || \
        date -u -d "@$timestamp" +"%Y-%m-%dT%H:%M:%SZ"
}

# Convert ISO 8601 timestamp to Unix timestamp
# Usage: iso_to_timestamp <iso_string>
# Returns: Unix timestamp (seconds since epoch)
iso_to_timestamp() {
    local iso_string="${1:?Missing ISO timestamp}"
    # macOS (BSD date) - using -j prevents setting system time, -f specifies input format
    date -j -f "%Y-%m-%dT%H:%M:%S%z" "$iso_string" "+%s" 2>/dev/null || \
        # GNU date - simpler syntax
        date -d "$iso_string" "+%s"
}

# Calculate current Anthropic weekly period boundaries
# Anthropic uses fixed reset cycles (e.g., Wed 3pm → Wed 3pm in America/Vancouver timezone)
# Usage: get_anthropic_period <next_reset_timestamp>
# Returns: JSON with period start, end, and progress percentage
get_anthropic_period() {
    local next_reset="${1:?Missing next_reset timestamp}"
    local current_ts=$(date +%s)

    # If we're past the reset time, calculate the next period
    if [[ $current_ts -ge $next_reset ]]; then
        # Calculate how many weeks past the reset we are
        local weeks_past=$(( (current_ts - next_reset) / WEEK_DURATION_SECONDS ))
        next_reset=$(( next_reset + (weeks_past + 1) * WEEK_DURATION_SECONDS ))
    # If we're before the reset, we might need to go back to find the current period
    elif [[ $current_ts -lt $(( next_reset - WEEK_DURATION_SECONDS )) ]]; then
        # Go back to find the right period
        while [[ $current_ts -lt $(( next_reset - WEEK_DURATION_SECONDS )) ]]; do
            next_reset=$(( next_reset - WEEK_DURATION_SECONDS ))
        done
    fi

    # Current period: [reset - 7 days, reset)
    local period_start=$(( next_reset - WEEK_DURATION_SECONDS ))
    local period_end=$next_reset

    # Calculate progress
    local elapsed=$(( current_ts - period_start ))
    local percent=$(( elapsed * 100 / WEEK_DURATION_SECONDS ))

    printf '{"start":%d,"end":%d,"percent":%d}\n' \
        "$period_start" "$period_end" "$percent"
}

# Calculate current daily period based on reset time
# Daily periods reset at the same time each day (e.g., 3pm daily for a 3pm weekly reset)
# Usage: get_daily_period <next_reset_timestamp>
# Returns: JSON with period start and current time
get_daily_period() {
    local next_reset="${1:?Missing next_reset timestamp}"
    local current_ts=$(date +%s)

    # Extract the time-of-day from the reset timestamp
    # Strategy: Get the hour offset from midnight in the reset's timezone

    # First, get the weekly period to understand the reset schedule
    local weekly_period=$(get_anthropic_period "$next_reset")
    local weekly_start=$(echo "$weekly_period" | jq -r '.start')

    # Calculate seconds since start of week (day-of-week offset)
    local week_offset=$(( (current_ts - weekly_start) % WEEK_DURATION_SECONDS ))

    # Calculate today's reset time by finding the last occurrence of the daily reset hour
    # Start from the weekly reset time and add days until we're close to now
    local daily_reset=$weekly_start

    # Fast forward to approximately today (within this week)
    while [[ $((daily_reset + DAY_DURATION_SECONDS)) -le $current_ts ]]; do
        daily_reset=$((daily_reset + DAY_DURATION_SECONDS))
    done

    # If we're before today's reset time, use yesterday's reset
    if [[ $current_ts -lt $daily_reset ]]; then
        daily_reset=$((daily_reset - DAY_DURATION_SECONDS))
    fi

    printf '{"start":%d,"end":%d}\n' "$daily_reset" "$current_ts"
}

# Calculate daily cost using ccusage blocks
# Filters blocks from today's baseline reset time to current time
# Usage: get_daily_cost <next_reset_timestamp> [cache_duration_seconds]
# Returns: Total cost for current daily period
get_daily_cost() {
    local next_reset="${1:?Missing next_reset timestamp}"
    local cache_duration="${2:-300}"  # Default 5 minutes, configurable

    # Get script directory (when sourced, use caller's directory)
    local utils_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local cache_file="$utils_dir/../data/.daily_cache"
    local cache_duration_minutes=$((cache_duration / 60))

    # Get current daily period boundaries
    local period_data=$(get_daily_period "$next_reset")
    local period_start=$(echo "$period_data" | jq -r '.start')
    local period_end=$(echo "$period_data" | jq -r '.end')

    # Check if cache exists and is fresh
    if [[ -f "$cache_file" ]]; then
        local cache_age=$(find "$cache_file" -mmin -${cache_duration_minutes} 2>/dev/null | wc -l | tr -d ' ')
        if [[ $cache_age -gt 0 ]]; then
            # Read cache and validate format: timestamp|period_start|period_end|daily_cost
            local cache_content=$(cat "$cache_file")
            local cached_period_start=$(echo "$cache_content" | cut -d'|' -f2)
            local cached_cost=$(echo "$cache_content" | cut -d'|' -f4)

            # Validate: same period AND valid number
            if [[ "$cached_period_start" == "$period_start" ]] && [[ "$cached_cost" =~ ^[0-9]+\.?[0-9]*$ ]]; then
                echo "$cached_cost"
                return 0
            fi
            # Cache invalid (wrong period or corrupted) - fall through to recalculate
        fi
    fi

    # Convert period start to ISO 8601 format for comparison with ccusage
    local start_iso=$(timestamp_to_iso "$period_start")

    # Get all blocks from ccusage
    local blocks_data=$(cd ~ && npx --yes ccusage blocks --json --offline 2>/dev/null | awk '/^{/,0')

    if [[ -z "$blocks_data" || "$blocks_data" == "null" ]]; then
        echo "0.00"
        return
    fi

    # Filter blocks where startTime >= period_start OR blocks that overlap the period
    # For overlapping blocks, include the full cost (conservative estimate)
    local period_end_iso=$(timestamp_to_iso "$period_end")
    local daily_cost=$(echo "$blocks_data" | jq -r --arg start_iso "$start_iso" --arg end_iso "$period_end_iso" '
        [.blocks[] |
         select(
           # Block starts within daily period
           (.startTime >= $start_iso) or
           # OR block is active and overlaps with daily period (endTime > period_start)
           (.endTime > $start_iso and .startTime < $end_iso)
         ) |
         .costUSD
        ] | add // 0
    ')

    # Format to 2 decimal places
    daily_cost=$(printf "%.2f" "$daily_cost")

    # Atomic cache write with period metadata
    # Format: timestamp|period_start|period_end|daily_cost
    local current_ts=$(date +%s)
    echo "${current_ts}|${period_start}|${period_end}|${daily_cost}" > "${cache_file}.tmp"
    mv "${cache_file}.tmp" "$cache_file"

    echo "$daily_cost"
}

# Calculate official Anthropic weekly cost (matches console reset schedule)
# Uses ccusage blocks data filtered by official reset period
# Usage: get_official_weekly_cost <next_reset_timestamp> [cache_duration_seconds]
# Returns: Total cost for current Anthropic weekly period
get_official_weekly_cost() {
    local next_reset="${1:?Missing next_reset timestamp}"
    local cache_duration="${2:-300}"  # Default 5 minutes, configurable

    # Get script directory (when sourced, use caller's directory)
    local utils_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local cache_file="$utils_dir/../data/.official_weekly_cache"
    local cache_duration_minutes=$((cache_duration / 60))

    # Get current Anthropic period boundaries
    local period_data=$(get_anthropic_period "$next_reset")
    local period_start=$(echo "$period_data" | jq -r '.start')
    local period_end=$(echo "$period_data" | jq -r '.end')

    # Check if cache exists and is fresh
    if [[ -f "$cache_file" ]]; then
        # Fix: Use -mmin (minutes) instead of -mtime (days)
        local cache_age=$(find "$cache_file" -mmin -${cache_duration_minutes} 2>/dev/null | wc -l | tr -d ' ')
        if [[ $cache_age -gt 0 ]]; then
            # Read cache and validate format: timestamp|period_start|period_end|weekly_cost
            local cache_content=$(cat "$cache_file")
            local cached_period_start=$(echo "$cache_content" | cut -d'|' -f2)
            local cached_cost=$(echo "$cache_content" | cut -d'|' -f4)

            # Validate: same period AND valid number
            if [[ "$cached_period_start" == "$period_start" ]] && [[ "$cached_cost" =~ ^[0-9]+\.?[0-9]*$ ]]; then
                echo "$cached_cost"
                return 0
            fi
            # Cache invalid (wrong period or corrupted) - fall through to recalculate
        fi
    fi

    # Convert period start to ISO 8601 format for comparison with ccusage
    local start_iso=$(timestamp_to_iso "$period_start")

    # Get all blocks from ccusage
    local blocks_data=$(cd ~ && npx --yes ccusage blocks --json --offline 2>/dev/null | awk '/^{/,0')

    if [[ -z "$blocks_data" || "$blocks_data" == "null" ]]; then
        echo "0.00"
        return
    fi

    # Filter blocks where startTime >= period_start and sum costs
    local weekly_cost=$(echo "$blocks_data" | jq -r --arg start_iso "$start_iso" '
        [.blocks[] |
         select(.startTime >= $start_iso) |
         .costUSD
        ] | add // 0
    ')

    # Format to 2 decimal places
    weekly_cost=$(printf "%.2f" "$weekly_cost")

    # Atomic cache write with period metadata
    # Format: timestamp|period_start|period_end|weekly_cost
    local current_ts=$(date +%s)
    echo "${current_ts}|${period_start}|${period_end}|${weekly_cost}" > "${cache_file}.tmp"
    mv "${cache_file}.tmp" "$cache_file"

    echo "$weekly_cost"
}

# Calculate weekly recommended usage based on cycle start
# Returns static value for current cycle: weekly_avail_at_cycle_start / ceil(cycles_left_from_cycle_start)
# Usage: get_weekly_recommend <next_reset_timestamp> <weekly_limit> <weekly_baseline_pct> [cache_duration_seconds]
# Returns: Recommended daily usage percentage
get_weekly_recommend() {
    local next_reset="${1:?Missing next_reset timestamp}"
    local weekly_limit="${2:?Missing weekly_limit}"
    local weekly_baseline_pct="${3:-0}"
    local cache_duration="${4:-300}"

    # Cache file per cycle
    local cache_file="${CACHE_DIR:-.}/.weekly_recommend_cache"

    # Get current cycle period
    local period_data=$(get_daily_period "$next_reset")
    local cycle_start=$(echo "$period_data" | jq -r '.start')

    # Check cache validity
    if [[ -f "$cache_file" ]]; then
        IFS='|' read -r cached_ts cached_cycle_start cached_value < "$cache_file"
        local current_ts=$(date +%s)

        # Cache valid if: same cycle AND within cache duration
        if [[ "$cached_cycle_start" == "$cycle_start" ]] && \
           [[ $((current_ts - cached_ts)) -lt $cache_duration ]] && \
           [[ "$cached_value" =~ ^[0-9]+$ ]]; then
            echo "$cached_value"
            return 0
        fi
    fi

    # Get weekly cost at cycle start by filtering blocks
    local cycle_start_iso=$(timestamp_to_iso "$cycle_start")
    local weekly_period=$(get_anthropic_period "$next_reset")
    local period_start=$(echo "$weekly_period" | jq -r '.start')
    local period_start_iso=$(timestamp_to_iso "$period_start")

    # Get blocks and filter up to cycle start
    local blocks_data=$(cd ~ && npx --yes ccusage blocks --json --offline 2>/dev/null | awk '/^{/,0')

    if [[ -z "$blocks_data" || "$blocks_data" == "null" ]]; then
        echo "0"
        return
    fi

    # Calculate weekly cost at cycle start (from blocks before cycle started)
    local weekly_cost_at_cycle_start=$(echo "$blocks_data" | jq -r --arg start_iso "$period_start_iso" --arg end_iso "$cycle_start_iso" '
        [.blocks[] |
         select(
           (.startTime >= $start_iso) and
           (.startTime < $end_iso)
         ) |
         .costUSD
        ] | add // 0
    ')

    # Apply baseline offset (same as current week calculation)
    if [ "$(awk "BEGIN {print ($weekly_baseline_pct != 0)}")" = "1" ]; then
        local baseline_cost=$(awk "BEGIN {printf \"%.2f\", ($weekly_limit * $weekly_baseline_pct) / 100}")
        weekly_cost_at_cycle_start=$(awk "BEGIN {printf \"%.2f\", $weekly_cost_at_cycle_start + $baseline_cost}")
    fi

    # Calculate available budget at cycle start
    local avail_cost_at_start=$(awk "BEGIN {printf \"%.2f\", $weekly_limit - $weekly_cost_at_cycle_start}")
    local avail_pct_at_start=$(awk "BEGIN {printf \"%.2f\", ($avail_cost_at_start / $weekly_limit) * 100}")

    # Calculate cycles left from cycle start to reset
    local time_from_cycle_start_to_reset=$((next_reset - cycle_start))
    local cycles_left=$(awk "BEGIN {hours = $time_from_cycle_start_to_reset / 3600; cycles = hours / 24; print (cycles == int(cycles)) ? int(cycles) : int(cycles) + 1}")

    # Calculate recommend value
    local recommend_value=0
    if [ "$cycles_left" -gt 0 ]; then
        recommend_value=$(awk "BEGIN {printf \"%.0f\", $avail_pct_at_start / $cycles_left}")
    fi

    # Cache the result
    local current_ts=$(date +%s)
    echo "${current_ts}|${cycle_start}|${recommend_value}" > "${cache_file}.tmp"
    mv "${cache_file}.tmp" "$cache_file"

    echo "$recommend_value"
}

# Export functions for use in other scripts
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    export -f timestamp_to_iso
    export -f iso_to_timestamp
    export -f get_anthropic_period
    export -f get_daily_period
    export -f get_daily_cost
    export -f get_official_weekly_cost
    export -f get_weekly_recommend
fi
