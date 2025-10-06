#!/bin/bash
set -euo pipefail
input=$(cat)

# Configuration file path
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/../config/config.json"

# Source utility functions for ccusage_r support (optional)
if [ -f "$SCRIPT_DIR/statusline-utils.sh" ]; then
    source "$SCRIPT_DIR/statusline-utils.sh"
fi

# Load configuration from JSON file if it exists
if [ -f "$CONFIG_FILE" ]; then
    CONFIG=$(cat "$CONFIG_FILE")

    # User Configuration
    USER_PLAN=$(echo "$CONFIG" | jq -r '.user.plan // "max5x"')

    # Limits
    WEEKLY_LIMIT_PRO=$(echo "$CONFIG" | jq -r '.limits.weekly.pro // 300')
    WEEKLY_LIMIT_MAX5X=$(echo "$CONFIG" | jq -r '.limits.weekly.max5x // 500')
    WEEKLY_LIMIT_MAX20X=$(echo "$CONFIG" | jq -r '.limits.weekly.max20x // 850')
    CONTEXT_LIMIT=$(echo "$CONFIG" | jq -r '.limits.context // 168')
    COST_LIMIT=$(echo "$CONFIG" | jq -r '.limits.cost // 140')
    TOKEN_LIMIT=$(echo "$CONFIG" | jq -r '.limits.token // 220000')

    # Paths
    CLAUDE_PROJECTS_PATH=$(echo "$CONFIG" | jq -r '.paths.claude_projects // "~/.claude/projects/"')

    # Display settings
    BAR_LENGTH=$(echo "$CONFIG" | jq -r '.display.bar_length // 10')
    TRANSCRIPT_TAIL_LINES=$(echo "$CONFIG" | jq -r '.display.transcript_tail_lines // 200')
    SESSION_ACTIVITY_THRESHOLD=$(echo "$CONFIG" | jq -r '.display.session_activity_threshold_minutes // 5')

    # ccusage version
    CCUSAGE_VERSION=$(echo "$CONFIG" | jq -r '.ccusage_version // "17.1.0"')

    # Multi-layer settings - load thresholds and colors
    LAYER1_THRESHOLD=$(echo "$CONFIG" | jq -r '.multi_layer.layer1.threshold_percent // 30')
    LAYER2_THRESHOLD=$(echo "$CONFIG" | jq -r '.multi_layer.layer2.threshold_percent // 50')
    LAYER3_THRESHOLD=$(echo "$CONFIG" | jq -r '.multi_layer.layer3.threshold_percent // 100')

    LAYER1_COLOR=$(echo "$CONFIG" | jq -r '.multi_layer.layer1.color // "green"')
    LAYER2_COLOR=$(echo "$CONFIG" | jq -r '.multi_layer.layer2.color // "orange"')
    LAYER3_COLOR=$(echo "$CONFIG" | jq -r '.multi_layer.layer3.color // "red"')

    # Calculate multipliers dynamically based on thresholds
    LAYER1_MULTIPLIER=$(awk "BEGIN {printf \"%.2f\", 100 / $LAYER1_THRESHOLD}")
    LAYER2_MULTIPLIER=$(awk "BEGIN {printf \"%.2f\", 100 / ($LAYER2_THRESHOLD - $LAYER1_THRESHOLD)}")
    LAYER3_MULTIPLIER=$(awk "BEGIN {printf \"%.2f\", 100 / ($LAYER3_THRESHOLD - $LAYER2_THRESHOLD)}")

    # Daily layer settings - load thresholds and colors
    DAILY_LAYER1_THRESHOLD=$(echo "$CONFIG" | jq -r '.daily_layer.layer1.threshold_percent // 4.76')
    DAILY_LAYER2_THRESHOLD=$(echo "$CONFIG" | jq -r '.daily_layer.layer2.threshold_percent // 9.52')
    DAILY_LAYER3_THRESHOLD=$(echo "$CONFIG" | jq -r '.daily_layer.layer3.threshold_percent // 14.29')

    DAILY_LAYER1_COLOR=$(echo "$CONFIG" | jq -r '.daily_layer.layer1.color // "green"')
    DAILY_LAYER2_COLOR=$(echo "$CONFIG" | jq -r '.daily_layer.layer2.color // "orange"')
    DAILY_LAYER3_COLOR=$(echo "$CONFIG" | jq -r '.daily_layer.layer3.color // "red"')

    # Calculate daily multipliers dynamically based on thresholds
    DAILY_LAYER1_MULTIPLIER=$(awk "BEGIN {printf \"%.2f\", 100 / $DAILY_LAYER1_THRESHOLD}")
    DAILY_LAYER2_MULTIPLIER=$(awk "BEGIN {printf \"%.2f\", 100 / ($DAILY_LAYER2_THRESHOLD - $DAILY_LAYER1_THRESHOLD)}")
    DAILY_LAYER3_MULTIPLIER=$(awk "BEGIN {printf \"%.2f\", 100 / ($DAILY_LAYER3_THRESHOLD - $DAILY_LAYER2_THRESHOLD)}")

    # Section toggles (use 'if null' to avoid treating false as falsy)
    SHOW_DIRECTORY=$(echo "$CONFIG" | jq -r 'if .sections.show_directory == null then "true" else .sections.show_directory | tostring end')
    SHOW_CONTEXT=$(echo "$CONFIG" | jq -r 'if .sections.show_context == null then "true" else .sections.show_context | tostring end')
    SHOW_FIVE_HOUR_WINDOW=$(echo "$CONFIG" | jq -r 'if .sections.show_five_hour_window == null then "true" else .sections.show_five_hour_window | tostring end')
    SHOW_DAILY=$(echo "$CONFIG" | jq -r 'if .sections.show_daily == null then "true" else .sections.show_daily | tostring end')
    SHOW_WEEKLY=$(echo "$CONFIG" | jq -r 'if .sections.show_weekly == null then "true" else .sections.show_weekly | tostring end')
    SHOW_TIMER=$(echo "$CONFIG" | jq -r 'if .sections.show_timer == null then "true" else .sections.show_timer | tostring end')
    SHOW_SESSIONS=$(echo "$CONFIG" | jq -r 'if .sections.show_sessions == null then "true" else .sections.show_sessions | tostring end')

    # Tracking settings
    WEEKLY_SCHEME=$(echo "$CONFIG" | jq -r '.tracking.weekly_scheme // "ccusage"')
    OFFICIAL_RESET_DATE_ISO=$(echo "$CONFIG" | jq -r '.tracking.official_reset_date // ""')
    WEEKLY_BASELINE_PCT=$(echo "$CONFIG" | jq -r '.tracking.weekly_baseline_percent // 0')
    CACHE_DURATION=$(echo "$CONFIG" | jq -r '.tracking.cache_duration_seconds // 300')

    # Convert official reset date to Unix timestamp if provided
    if [ -n "$OFFICIAL_RESET_DATE_ISO" ]; then
        OFFICIAL_RESET_DATE=$(date -j -f "%Y-%m-%dT%H:%M:%S%z" "$OFFICIAL_RESET_DATE_ISO" +%s 2>/dev/null || \
                              date -d "$OFFICIAL_RESET_DATE_ISO" +%s 2>/dev/null || echo "")
    else
        OFFICIAL_RESET_DATE=""
    fi

    # Color codes
    ORANGE_CODE=$(echo "$CONFIG" | jq -r '.colors.orange // "\\033[1;38;5;208m"' | sed 's/\\\\/\\/g')
    RED_CODE=$(echo "$CONFIG" | jq -r '.colors.red // "\\033[1;31m"' | sed 's/\\\\/\\/g')
    PINK_CODE=$(echo "$CONFIG" | jq -r '.colors.pink // "\\033[38;5;225m"' | sed 's/\\\\/\\/g')
    GREEN_CODE=$(echo "$CONFIG" | jq -r '.colors.green // "\\033[38;5;194m"' | sed 's/\\\\/\\/g')
    PURPLE_CODE=$(echo "$CONFIG" | jq -r '.colors.purple // "\\033[35m"' | sed 's/\\\\/\\/g')
    CYAN_CODE=$(echo "$CONFIG" | jq -r '.colors.cyan // "\\033[96m"' | sed 's/\\\\/\\/g')
    RESET_CODE=$(echo "$CONFIG" | jq -r '.colors.reset // "\\033[0m"' | sed 's/\\\\/\\/g')
else
    # Default configuration (fallback if config file doesn't exist)
    USER_PLAN="max5x"
    WEEKLY_LIMIT_PRO=300
    WEEKLY_LIMIT_MAX5X=500
    WEEKLY_LIMIT_MAX20X=850
    CONTEXT_LIMIT=168
    COST_LIMIT=140
    TOKEN_LIMIT=220000
    CLAUDE_PROJECTS_PATH="~/.claude/projects/"
    BAR_LENGTH=10
    TRANSCRIPT_TAIL_LINES=200
    SESSION_ACTIVITY_THRESHOLD=5
    CCUSAGE_VERSION="17.1.0"
    LAYER1_THRESHOLD=30
    LAYER2_THRESHOLD=50
    LAYER3_THRESHOLD=100
    LAYER1_COLOR="green"
    LAYER2_COLOR="orange"
    LAYER3_COLOR="red"
    # Calculate multipliers dynamically
    LAYER1_MULTIPLIER=$(awk "BEGIN {printf \"%.2f\", 100 / $LAYER1_THRESHOLD}")
    LAYER2_MULTIPLIER=$(awk "BEGIN {printf \"%.2f\", 100 / ($LAYER2_THRESHOLD - $LAYER1_THRESHOLD)}")
    LAYER3_MULTIPLIER=$(awk "BEGIN {printf \"%.2f\", 100 / ($LAYER3_THRESHOLD - $LAYER2_THRESHOLD)}")
    # Default daily layer settings
    DAILY_LAYER1_THRESHOLD=4.76
    DAILY_LAYER2_THRESHOLD=9.52
    DAILY_LAYER3_THRESHOLD=14.29
    DAILY_LAYER1_COLOR="green"
    DAILY_LAYER2_COLOR="orange"
    DAILY_LAYER3_COLOR="red"
    # Calculate daily multipliers dynamically
    DAILY_LAYER1_MULTIPLIER=$(awk "BEGIN {printf \"%.2f\", 100 / $DAILY_LAYER1_THRESHOLD}")
    DAILY_LAYER2_MULTIPLIER=$(awk "BEGIN {printf \"%.2f\", 100 / ($DAILY_LAYER2_THRESHOLD - $DAILY_LAYER1_THRESHOLD)}")
    DAILY_LAYER3_MULTIPLIER=$(awk "BEGIN {printf \"%.2f\", 100 / ($DAILY_LAYER3_THRESHOLD - $DAILY_LAYER2_THRESHOLD)}")
    # Default section toggles (all strings for consistency)
    SHOW_DIRECTORY="true"
    SHOW_CONTEXT="true"
    SHOW_FIVE_HOUR_WINDOW="true"
    SHOW_DAILY="true"
    SHOW_WEEKLY="true"
    SHOW_TIMER="true"
    SHOW_SESSIONS="true"
    # Default tracking settings
    WEEKLY_BASELINE_PCT=0
    CACHE_DURATION=300
    # Default color codes (fallback only - customize via config.json)
    ORANGE_CODE='\033[38;5;208m'
    RED_CODE='\033[31m'
    PINK_CODE='\033[38;5;225m'
    GREEN_CODE='\033[38;5;194m'
    PURPLE_CODE='\033[35m'
    CYAN_CODE='\033[96m'
    RESET_CODE='\033[0m'
fi

# Helper function: map color name to ANSI code
get_color_code() {
    case "$1" in
        "orange") echo "$ORANGE_CODE" ;;
        "red") echo "$RED_CODE" ;;
        "pink") echo "$PINK_CODE" ;;
        "green") echo "$GREEN_CODE" ;;
        "purple") echo "$PURPLE_CODE" ;;
        "cyan") echo "$CYAN_CODE" ;;
        *) echo "$GREEN_CODE" ;;  # Default fallback
    esac
}

# Determine weekly limit based on plan
case "$USER_PLAN" in
    "pro")
        WEEKLY_LIMIT=$WEEKLY_LIMIT_PRO
        ;;
    "max5x")
        WEEKLY_LIMIT=$WEEKLY_LIMIT_MAX5X
        ;;
    "max20x")
        WEEKLY_LIMIT=$WEEKLY_LIMIT_MAX20X
        ;;
    *)
        WEEKLY_LIMIT=$WEEKLY_LIMIT_MAX5X  # Default fallback
        ;;
esac

# Extract basic information from JSON
CURRENT_DIR=$(echo "$input" | jq -r '.workspace.current_dir // "~"')
DIR_NAME="${CURRENT_DIR##*/}"
# Sanitize DIR_NAME to prevent ANSI injection
DIR_NAME=$(printf '%s' "$DIR_NAME" | tr -d '\000-\037\177')
TRANSCRIPT_PATH=$(echo "$input" | jq -r '.transcript_path // ""')

# ====================================================================================
# SECTION CALCULATIONS (Conditional based on toggles)
# ====================================================================================

# Get 5-hour window data from ccusage (needed by 5-HOUR WINDOW and/or TIMER sections)
# Only fetch if at least one of these sections is enabled
if [ "$SHOW_FIVE_HOUR_WINDOW" = "true" ] || [ "$SHOW_TIMER" = "true" ]; then
    # Use --offline for faster execution with cached pricing
    # Filter out npm warnings and capture only the JSON
    WINDOW_DATA=$(cd ~ && npx --yes "ccusage@${CCUSAGE_VERSION}" blocks --active --json --token-limit $TOKEN_LIMIT --offline 2>/dev/null | awk '/^{/,0')

    if [ -n "$WINDOW_DATA" ] && [ "$WINDOW_DATA" != "null" ]; then
        # Parse window data
        BLOCK=$(echo "$WINDOW_DATA" | jq -r '.blocks[0] // empty')

        if [ -n "$BLOCK" ]; then
            # ========================================================================
            # 5-HOUR WINDOW SECTION (conditional)
            # ========================================================================
            if [ "$SHOW_FIVE_HOUR_WINDOW" = "true" ]; then
                # Extract cost and projection
                COST=$(echo "$BLOCK" | jq -r '.costUSD // 0')
                PROJECTED_COST=$(echo "$BLOCK" | jq -r '.projection.totalCost // 0')

                # Multi-layer progress bar (using config-defined settings)
                # Calculate actual percentage
                ACTUAL_PCT=$(awk "BEGIN {printf \"%.2f\", ($COST / $COST_LIMIT) * 100}")

                # Determine layer and calculate visual progress
                if (( $(awk "BEGIN {print ($ACTUAL_PCT <= $LAYER1_THRESHOLD)}") )); then
                    # Layer 1: 0-threshold% actual → 0-100% visual
                    VISUAL_PCT=$(awk "BEGIN {printf \"%.2f\", $ACTUAL_PCT * $LAYER1_MULTIPLIER}")
                    BAR_COLOR="$LAYER1_COLOR"
                elif (( $(awk "BEGIN {print ($ACTUAL_PCT <= $LAYER2_THRESHOLD)}") )); then
                    # Layer 2: threshold1-threshold2% actual → 0-100% visual
                    VISUAL_PCT=$(awk "BEGIN {printf \"%.2f\", ($ACTUAL_PCT - $LAYER1_THRESHOLD) * $LAYER2_MULTIPLIER}")
                    BAR_COLOR="$LAYER2_COLOR"
                else
                    # Layer 3: threshold2-threshold3% actual → 0-100% visual
                    VISUAL_PCT=$(awk "BEGIN {printf \"%.2f\", ($ACTUAL_PCT - $LAYER2_THRESHOLD) * $LAYER3_MULTIPLIER}")
                    if (( $(awk "BEGIN {print ($VISUAL_PCT > 100)}") )); then
                        VISUAL_PCT=100
                    fi
                    BAR_COLOR="$LAYER3_COLOR"
                fi

                # Calculate filled blocks based on visual percentage
                FILLED=$(awk "BEGIN {printf \"%.0f\", ($VISUAL_PCT / 100) * $BAR_LENGTH}")
                if [ $FILLED -gt $BAR_LENGTH ]; then
                    FILLED=$BAR_LENGTH
                fi

                # Calculate projected position using CURRENT layer's multiplier for consistent scale
                PROJECTED_POS=-1
                PROJECTED_BAR_COLOR="$LAYER1_COLOR"
                if [ -n "$PROJECTED_COST" ] && [ "$PROJECTED_COST" != "0" ]; then
                    PROJECTED_ACTUAL_PCT=$(awk "BEGIN {printf \"%.2f\", ($PROJECTED_COST / $COST_LIMIT) * 100}")

                    # Determine projection color based on which layer it falls into
                    if (( $(awk "BEGIN {print ($PROJECTED_ACTUAL_PCT <= $LAYER1_THRESHOLD)}") )); then
                        PROJECTED_BAR_COLOR="$LAYER1_COLOR"
                    elif (( $(awk "BEGIN {print ($PROJECTED_ACTUAL_PCT <= $LAYER2_THRESHOLD)}") )); then
                        PROJECTED_BAR_COLOR="$LAYER2_COLOR"
                    else
                        PROJECTED_BAR_COLOR="$LAYER3_COLOR"
                    fi

                    # Calculate visual position using CURRENT layer's multiplier (same scale as current bar)
                    if [ "$BAR_COLOR" = "$LAYER1_COLOR" ]; then
                        PROJECTED_VISUAL_PCT=$(awk "BEGIN {printf \"%.2f\", $PROJECTED_ACTUAL_PCT * $LAYER1_MULTIPLIER}")
                    elif [ "$BAR_COLOR" = "$LAYER2_COLOR" ]; then
                        PROJECTED_VISUAL_PCT=$(awk "BEGIN {printf \"%.2f\", ($PROJECTED_ACTUAL_PCT - $LAYER1_THRESHOLD) * $LAYER2_MULTIPLIER}")
                    else
                        PROJECTED_VISUAL_PCT=$(awk "BEGIN {printf \"%.2f\", ($PROJECTED_ACTUAL_PCT - $LAYER2_THRESHOLD) * $LAYER3_MULTIPLIER}")
                    fi

                    if (( $(awk "BEGIN {print ($PROJECTED_VISUAL_PCT > 100)}") )); then
                        PROJECTED_VISUAL_PCT=100
                    fi

                    PROJECTED_POS=$(awk "BEGIN {printf \"%.0f\", ($PROJECTED_VISUAL_PCT / 100) * $BAR_LENGTH}")
                    if [ $PROJECTED_POS -gt $BAR_LENGTH ]; then
                        PROJECTED_POS=$BAR_LENGTH
                    fi

                    # Don't show separator if it's at same position as current
                    if [ $PROJECTED_POS -eq $FILLED ]; then
                        PROJECTED_POS=-1
                    fi
                fi

                # Set projected separator color from config
                PROJECTED_COLOR=$(get_color_code "$PROJECTED_BAR_COLOR")

                # Set current progress bar color from config
                CURRENT_COLOR=$(get_color_code "$BAR_COLOR")

                # Build progress bar with colored projection separator
                PROGRESS_BAR="["
                for ((i=0; i<BAR_LENGTH; i++)); do
                    if [ $i -lt $FILLED ]; then
                        PROGRESS_BAR="${PROGRESS_BAR}█"
                    elif [ $i -eq $PROJECTED_POS ]; then
                        # Projection separator uses current layer color (displayed on current bar)
                        PROGRESS_BAR="${PROGRESS_BAR}${RESET_CODE}${CURRENT_COLOR}│${RESET_CODE}${CURRENT_COLOR}"
                    else
                        PROGRESS_BAR="${PROGRESS_BAR}░"
                    fi
                done

                # Handle separator at end position (when PROJECTED_POS == BAR_LENGTH)
                # This occurs when projection crosses layer boundary and is capped
                if [ $PROJECTED_POS -eq $BAR_LENGTH ]; then
                    PROGRESS_BAR="${PROGRESS_BAR}${RESET_CODE}${CURRENT_COLOR}│${RESET_CODE}${CURRENT_COLOR}"
                fi

                PROGRESS_BAR="${PROGRESS_BAR}]"

                # Calculate cost percentage
                COST_PERCENTAGE=$(awk "BEGIN {printf \"%.0f\", ($COST / $COST_LIMIT) * 100}")

                # Format cost
                COST_FMT=$(printf "\$%.0f/\$%d" $COST $COST_LIMIT)

                # Set progress bar color based on layer
                PROGRESS_COLOR=$(get_color_code "$BAR_COLOR")
            fi

            # ========================================================================
            # TIMER SECTION (conditional)
            # ========================================================================
            if [ "$SHOW_TIMER" = "true" ]; then
                # Extract time data
                REMAINING_MINS=$(echo "$BLOCK" | jq -r '.projection.remainingMinutes // 0')
                END_TIME=$(echo "$BLOCK" | jq -r '.endTime // ""')

                # Format countdown
                HOURS=$((REMAINING_MINS / 60))
                MINS=$((REMAINING_MINS % 60))
                TIME_LEFT="${MINS}m"
                if [ $HOURS -gt 0 ]; then
                    TIME_LEFT="${HOURS}h ${MINS}m"
                fi

                # Get current time with minutes (format: 5:45PM)
                CURRENT_TIME=$(date "+%-l:%M%p" 2>/dev/null || date "+%I:%M%p" | sed 's/^0//')

                # Format reset time (simplified format: 10PM - no minutes)
                if [ -n "$END_TIME" ]; then
                    # Try GNU date first (Linux), then macOS date
                    RESET_TIME=$(date -d "$END_TIME" "+%-l%p" 2>/dev/null)
                    if [ -z "$RESET_TIME" ]; then
                        # Fallback to macOS date
                        END_TIME_CLEAN=$(echo "$END_TIME" | sed 's/\.[0-9]*Z$//')
                        RESET_TIME=$(date -j -f "%Y-%m-%dT%H:%M:%S" "$END_TIME_CLEAN" "+%-l%p" 2>/dev/null || echo "")
                    fi
                else
                    RESET_TIME=""
                fi

                # Dim color for secondary info (50% opacity effect)
                DIM_CODE="\033[2m"

                # Format reset info: [current]/[reset] (remaining) with dimmed secondary parts
                if [ -n "$RESET_TIME" ]; then
                    RESET_INFO="$CURRENT_TIME${DIM_CODE}/$RESET_TIME ($TIME_LEFT)${RESET_CODE}"
                else
                    RESET_INFO="$TIME_LEFT"
                fi
            fi
        fi
    fi
fi

# ====================================================================================
# CONTEXT SECTION (independent)
# ====================================================================================
if [ "$SHOW_CONTEXT" = "true" ] && [ -f "$TRANSCRIPT_PATH" ]; then
    # Calculate context window usage from transcript
    # Use ccusage method: latest assistant message only
    # Separate cached (system overhead) vs fresh (conversation) context
    # Get the LATEST assistant message (last N lines for performance)
    # Extract token types and calculate cached vs fresh
    TOKEN_DATA=$(tail -$TRANSCRIPT_TAIL_LINES "$TRANSCRIPT_PATH" | \
        grep '"role":"assistant"' | \
        tail -1 | \
        awk '
        {
            input = 0
            cache_creation = 0
            cache_read = 0

            # Extract input_tokens (fresh conversation)
            if (match($0, /"input_tokens":[0-9]+/)) {
                input = substr($0, RSTART, RLENGTH)
                gsub(/.*:/, "", input)
            }

            # Extract cache_creation_input_tokens (cached)
            if (match($0, /"cache_creation_input_tokens":[0-9]+/)) {
                cache_creation = substr($0, RSTART, RLENGTH)
                gsub(/.*:/, "", cache_creation)
            }

            # Extract cache_read_input_tokens (cached)
            if (match($0, /"cache_read_input_tokens":[0-9]+/)) {
                cache_read = substr($0, RSTART, RLENGTH)
                gsub(/.*:/, "", cache_read)
            }

            # Cached = cache_creation + cache_read (system overhead)
            cached = cache_creation + cache_read
            # Fresh = input_tokens (active conversation)
            fresh = input
            # Total context
            total = cached + fresh

            # Output: cached(k) fresh(k) total(k)
            print int(cached / 1000) " " int(fresh / 1000) " " int(total / 1000)
        }')

    # Parse the output
    CACHED_TOKENS=$(echo "$TOKEN_DATA" | awk '{print $1}')
    FRESH_TOKENS=$(echo "$TOKEN_DATA" | awk '{print $2}')
    CONTEXT_TOKENS=$(echo "$TOKEN_DATA" | awk '{print $3}')

    # Fallback if no data found
    if [ -z "$CONTEXT_TOKENS" ]; then
        CACHED_TOKENS=0
        FRESH_TOKENS=0
        CONTEXT_TOKENS=0
    fi

    # Create context progress bar (same length as cost bar)
    CTX_BAR_LENGTH=$BAR_LENGTH

    # Calculate total filled blocks
    CTX_FILLED=$(awk "BEGIN {printf \"%.0f\", ($CONTEXT_TOKENS / $CONTEXT_LIMIT) * $CTX_BAR_LENGTH}")
    if [ $CTX_FILLED -gt $CTX_BAR_LENGTH ]; then
        CTX_FILLED=$CTX_BAR_LENGTH
    fi

    CTX_EMPTY=$((CTX_BAR_LENGTH - CTX_FILLED))

    # Build simple progress bar
    CTX_PROGRESS_BAR="["

    # Pink blocks for filled
    for ((i=0; i<CTX_FILLED; i++)); do
        CTX_PROGRESS_BAR="${CTX_PROGRESS_BAR}█"
    done

    # Gray blocks for empty
    for ((i=0; i<CTX_EMPTY; i++)); do
        CTX_PROGRESS_BAR="${CTX_PROGRESS_BAR}░"
    done

    CTX_PROGRESS_BAR="${CTX_PROGRESS_BAR}]"

    # Format context - separate total from breakdown
    CTX_TOTAL=$(printf "%dk/%dk" $CONTEXT_TOKENS $CONTEXT_LIMIT)
    CTX_BREAKDOWN=$(printf "%dk+%dk" $CACHED_TOKENS $FRESH_TOKENS)
fi

# ====================================================================================
# WEEKLY SECTION (independent)
# ====================================================================================
if [ "$SHOW_WEEKLY" = "true" ]; then
    # Get weekly usage based on configured tracking scheme
    if [ "$WEEKLY_SCHEME" = "ccusage_r" ] && [ -n "$OFFICIAL_RESET_DATE" ] && type get_official_weekly_cost &>/dev/null; then
        # Use ccusage costs filtered by official Anthropic reset schedule
        WEEK_COST=$(get_official_weekly_cost "$OFFICIAL_RESET_DATE" "$CACHE_DURATION")
    else
        # Use ccusage with ISO weeks (default)
        WEEKLY_DATA=$(cd ~ && npx --yes "ccusage@${CCUSAGE_VERSION}" weekly --json --offline 2>/dev/null | awk '/^{/,0')
        WEEK_COST=$(echo "$WEEKLY_DATA" | jq -r '.weekly[-1].totalCost // 0')
    fi

    # Apply baseline offset to account for untracked costs (deleted transcripts)
    if [ "$(awk "BEGIN {print ($WEEKLY_BASELINE_PCT != 0)}")" = "1" ]; then
        BASELINE_COST=$(awk "BEGIN {printf \"%.2f\", ($WEEKLY_LIMIT * $WEEKLY_BASELINE_PCT) / 100}")
        WEEK_COST=$(awk "BEGIN {printf \"%.2f\", $WEEK_COST + $BASELINE_COST}")
    fi

    WEEKLY_PCT=$(awk "BEGIN {printf \"%.0f\", ($WEEK_COST / $WEEKLY_LIMIT) * 100}")
fi

# ====================================================================================
# DAILY SECTION (independent)
# ====================================================================================
if [ "$SHOW_DAILY" = "true" ] && [ -n "$OFFICIAL_RESET_DATE" ] && type get_daily_cost &>/dev/null; then
    # Use daily cost tracking based on official reset time
    DAILY_COST=$(get_daily_cost "$OFFICIAL_RESET_DATE" "$CACHE_DURATION")

    # Get daily period boundaries for projection calculation
    DAILY_PERIOD_DATA=$(get_daily_period "$OFFICIAL_RESET_DATE")
    DAILY_PERIOD_START=$(echo "$DAILY_PERIOD_DATA" | jq -r '.start')
    DAILY_CURRENT_TIME=$(echo "$DAILY_PERIOD_DATA" | jq -r '.end')

    # Calculate projection for end of day
    DAILY_ELAPSED=$((DAILY_CURRENT_TIME - DAILY_PERIOD_START))
    DAILY_TOTAL_PERIOD=86400  # 24 hours in seconds

    # Project daily cost (extrapolate to full 24-hour period)
    if [ $DAILY_ELAPSED -gt 0 ]; then
        DAILY_PROJECTED_COST=$(awk "BEGIN {printf \"%.2f\", ($DAILY_COST / $DAILY_ELAPSED) * $DAILY_TOTAL_PERIOD}")
    else
        DAILY_PROJECTED_COST=0
    fi

    # Calculate daily percentage (against weekly limit)
    DAILY_PCT=$(awk "BEGIN {printf \"%.2f\", ($DAILY_COST / $WEEKLY_LIMIT) * 100}")

    # Build daily progress bar (multi-layer visualization)
    # Determine layer and calculate visual progress
    if (( $(awk "BEGIN {print ($DAILY_PCT <= $DAILY_LAYER1_THRESHOLD)}") )); then
        # Layer 1: 0-threshold% actual → 0-100% visual
        DAILY_VISUAL_PCT=$(awk "BEGIN {printf \"%.2f\", $DAILY_PCT * $DAILY_LAYER1_MULTIPLIER}")
        DAILY_BAR_COLOR="$DAILY_LAYER1_COLOR"
    elif (( $(awk "BEGIN {print ($DAILY_PCT <= $DAILY_LAYER2_THRESHOLD)}") )); then
        # Layer 2: threshold1-threshold2% actual → 0-100% visual
        DAILY_VISUAL_PCT=$(awk "BEGIN {printf \"%.2f\", ($DAILY_PCT - $DAILY_LAYER1_THRESHOLD) * $DAILY_LAYER2_MULTIPLIER}")
        DAILY_BAR_COLOR="$DAILY_LAYER2_COLOR"
    else
        # Layer 3: threshold2-threshold3% actual → 0-100% visual
        DAILY_VISUAL_PCT=$(awk "BEGIN {printf \"%.2f\", ($DAILY_PCT - $DAILY_LAYER2_THRESHOLD) * $DAILY_LAYER3_MULTIPLIER}")
        if (( $(awk "BEGIN {print ($DAILY_VISUAL_PCT > 100)}") )); then
            DAILY_VISUAL_PCT=100
        fi
        DAILY_BAR_COLOR="$DAILY_LAYER3_COLOR"
    fi

    # Calculate filled blocks based on visual percentage
    DAILY_FILLED=$(awk "BEGIN {printf \"%.0f\", ($DAILY_VISUAL_PCT / 100) * $BAR_LENGTH}")
    if [ $DAILY_FILLED -gt $BAR_LENGTH ]; then
        DAILY_FILLED=$BAR_LENGTH
    fi

    # Calculate projected position using CURRENT layer's multiplier for consistent scale
    DAILY_PROJECTED_POS=-1
    DAILY_PROJECTED_BAR_COLOR="$DAILY_LAYER1_COLOR"
    if [ -n "$DAILY_PROJECTED_COST" ] && [ "$DAILY_PROJECTED_COST" != "0" ]; then
        DAILY_PROJECTED_ACTUAL_PCT=$(awk "BEGIN {printf \"%.2f\", ($DAILY_PROJECTED_COST / $WEEKLY_LIMIT) * 100}")

        # Determine projection color based on which layer it falls into
        if (( $(awk "BEGIN {print ($DAILY_PROJECTED_ACTUAL_PCT <= $DAILY_LAYER1_THRESHOLD)}") )); then
            DAILY_PROJECTED_BAR_COLOR="$DAILY_LAYER1_COLOR"
        elif (( $(awk "BEGIN {print ($DAILY_PROJECTED_ACTUAL_PCT <= $DAILY_LAYER2_THRESHOLD)}") )); then
            DAILY_PROJECTED_BAR_COLOR="$DAILY_LAYER2_COLOR"
        else
            DAILY_PROJECTED_BAR_COLOR="$DAILY_LAYER3_COLOR"
        fi

        # Calculate visual position using CURRENT layer's multiplier (same scale as current bar)
        if [ "$DAILY_BAR_COLOR" = "$DAILY_LAYER1_COLOR" ]; then
            DAILY_PROJECTED_VISUAL_PCT=$(awk "BEGIN {printf \"%.2f\", $DAILY_PROJECTED_ACTUAL_PCT * $DAILY_LAYER1_MULTIPLIER}")
        elif [ "$DAILY_BAR_COLOR" = "$DAILY_LAYER2_COLOR" ]; then
            DAILY_PROJECTED_VISUAL_PCT=$(awk "BEGIN {printf \"%.2f\", ($DAILY_PROJECTED_ACTUAL_PCT - $DAILY_LAYER1_THRESHOLD) * $DAILY_LAYER2_MULTIPLIER}")
        else
            DAILY_PROJECTED_VISUAL_PCT=$(awk "BEGIN {printf \"%.2f\", ($DAILY_PROJECTED_ACTUAL_PCT - $DAILY_LAYER2_THRESHOLD) * $DAILY_LAYER3_MULTIPLIER}")
        fi

        if (( $(awk "BEGIN {print ($DAILY_PROJECTED_VISUAL_PCT > 100)}") )); then
            DAILY_PROJECTED_VISUAL_PCT=100
        fi

        DAILY_PROJECTED_POS=$(awk "BEGIN {printf \"%.0f\", ($DAILY_PROJECTED_VISUAL_PCT / 100) * $BAR_LENGTH}")
        if [ $DAILY_PROJECTED_POS -gt $BAR_LENGTH ]; then
            DAILY_PROJECTED_POS=$BAR_LENGTH
        fi

        # Don't show separator if it's at same position as current
        if [ $DAILY_PROJECTED_POS -eq $DAILY_FILLED ]; then
            DAILY_PROJECTED_POS=-1
        fi
    fi

    # Set projected separator color from config
    DAILY_PROJECTED_COLOR=$(get_color_code "$DAILY_PROJECTED_BAR_COLOR")

    # Set current progress bar color from config
    DAILY_COLOR=$(get_color_code "$DAILY_BAR_COLOR")

    # Build progress bar with colored projection separator
    DAILY_PROGRESS_BAR="["
    for ((i=0; i<BAR_LENGTH; i++)); do
        if [ $i -lt $DAILY_FILLED ]; then
            DAILY_PROGRESS_BAR="${DAILY_PROGRESS_BAR}█"
        elif [ $i -eq $DAILY_PROJECTED_POS ]; then
            # Projection separator uses current layer color (displayed on current bar)
            DAILY_PROGRESS_BAR="${DAILY_PROGRESS_BAR}${RESET_CODE}${DAILY_COLOR}│${RESET_CODE}${DAILY_COLOR}"
        else
            DAILY_PROGRESS_BAR="${DAILY_PROGRESS_BAR}░"
        fi
    done

    # Handle separator at end position (when DAILY_PROJECTED_POS == BAR_LENGTH)
    # This occurs when projection crosses layer boundary and is capped
    if [ $DAILY_PROJECTED_POS -eq $BAR_LENGTH ]; then
        DAILY_PROGRESS_BAR="${DAILY_PROGRESS_BAR}${RESET_CODE}${DAILY_COLOR}│${RESET_CODE}${DAILY_COLOR}"
    fi

    DAILY_PROGRESS_BAR="${DAILY_PROGRESS_BAR}]"

    # Format daily percentage for display (rounded to whole number)
    DAILY_PCT_DISPLAY=$(awk "BEGIN {printf \"%.0f\", $DAILY_PCT}")
fi

# ====================================================================================
# SESSIONS SECTION (independent)
# ====================================================================================
if [ "$SHOW_SESSIONS" = "true" ]; then
    # Count concurrent Claude Code sessions (projects with activity in last N minutes)
    # Expand tilde in path
    PROJECTS_PATH="${CLAUDE_PROJECTS_PATH/#\~/$HOME}"
    ACTIVE_SESSIONS=$(find "$PROJECTS_PATH" -name "*.jsonl" -type f -mmin -$SESSION_ACTIVITY_THRESHOLD 2>/dev/null | \
        xargs -I {} dirname {} 2>/dev/null | sort -u | wc -l | tr -d ' ')
fi

# ====================================================================================
# BUILD STATUSLINE
# ====================================================================================
STATUSLINE_SECTIONS=()

# Directory section
[[ "$SHOW_DIRECTORY" == "true" ]] && STATUSLINE_SECTIONS+=("${ORANGE_CODE}${DIR_NAME}${RESET_CODE}")

[[ "$SHOW_CONTEXT" == "true" ]] && [[ -n "${CTX_TOTAL:-}" ]] && STATUSLINE_SECTIONS+=("${PINK_CODE}${CTX_TOTAL} ${CTX_PROGRESS_BAR}${RESET_CODE}")
[[ "$SHOW_FIVE_HOUR_WINDOW" == "true" ]] && [[ -n "${COST_FMT:-}" ]] && STATUSLINE_SECTIONS+=("${PROGRESS_COLOR}${COST_FMT} ${PROGRESS_BAR} ${COST_PERCENTAGE}%${RESET_CODE}")

# Add daily section if enabled and configured
if [[ "$SHOW_DAILY" == "true" ]] && [[ -n "${DAILY_PROGRESS_BAR:-}" ]]; then
    STATUSLINE_SECTIONS+=("${DAILY_COLOR}daily ${DAILY_PROGRESS_BAR} ${DAILY_PCT_DISPLAY}%${RESET_CODE}")
fi

[[ "$SHOW_WEEKLY" == "true" ]] && [[ -n "${WEEKLY_PCT:-}" ]] && STATUSLINE_SECTIONS+=("weekly ${WEEKLY_PCT}%")
[[ "$SHOW_TIMER" == "true" ]] && [[ -n "${RESET_INFO:-}" ]] && STATUSLINE_SECTIONS+=("${PURPLE_CODE}${RESET_INFO}${RESET_CODE}")
[[ "$SHOW_SESSIONS" == "true" ]] && [[ -n "${ACTIVE_SESSIONS:-}" ]] && STATUSLINE_SECTIONS+=("${CYAN_CODE}×${ACTIVE_SESSIONS}${RESET_CODE}")

# Join sections with separator
STATUSLINE=""
FIRST=true
for section in "${STATUSLINE_SECTIONS[@]}"; do
    if [[ "$FIRST" == "true" ]]; then
        STATUSLINE="$section"
        FIRST=false
    else
        STATUSLINE="$STATUSLINE | $section"
    fi
done

# Display statusline
if [ -n "$STATUSLINE" ]; then
    printf '%b\n' "$STATUSLINE"
else
    # Fallback if no sections enabled
    echo "$DIR_NAME | No active window"
fi
