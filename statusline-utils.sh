#!/usr/bin/env bash
# statusline-utils.sh - Utility functions for official Anthropic weekly reset tracking
# This file provides ccusage_r scheme support for matching official console reset schedule

# Constants
readonly WEEK_DURATION_SECONDS=604800  # 7 days

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

# Calculate official Anthropic weekly cost (matches console reset schedule)
# Uses ccusage blocks data filtered by official reset period
# Usage: get_official_weekly_cost <next_reset_timestamp>
# Returns: Total cost for current Anthropic weekly period
get_official_weekly_cost() {
    local next_reset="${1:?Missing next_reset timestamp}"
    local cache_file="$HOME/.claude/.official_weekly_cache"
    local cache_duration=300  # 5 minutes

    # Check if cache exists and is fresh
    if [[ -f "$cache_file" ]]; then
        local cache_age=$(find "$cache_file" -mtime -5m 2>/dev/null | wc -l | tr -d ' ')
        if [[ $cache_age -gt 0 ]]; then
            cat "$cache_file"
            return 0
        fi
    fi

    # Get current Anthropic period boundaries
    local period_data=$(get_anthropic_period "$next_reset")
    local period_start=$(echo "$period_data" | jq -r '.start')

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

    # Cache result
    echo "$weekly_cost" > "$cache_file"
    echo "$weekly_cost"
}

# Export functions for use in other scripts
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    export -f timestamp_to_iso
    export -f get_anthropic_period
    export -f get_official_weekly_cost
fi
