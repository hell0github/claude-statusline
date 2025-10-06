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

# Export functions for use in other scripts
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    export -f timestamp_to_iso
    export -f get_anthropic_period
    export -f get_daily_period
    export -f get_daily_cost
    export -f get_official_weekly_cost
fi
