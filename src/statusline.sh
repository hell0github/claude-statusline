#!/bin/bash
set -euo pipefail
trap 'echo "ERROR in statusline.sh" >&2; exit 1' ERR
input=$(cat)

# Configuration file path
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/../config/config.json"

# Source utility functions for ccusage_r support (optional)
if [ -f "$SCRIPT_DIR/statusline-utils.sh" ]; then
    source "$SCRIPT_DIR/statusline-utils.sh"
fi

# Source layer calculation functions
if [ -f "$SCRIPT_DIR/statusline-layers.sh" ]; then
    source "$SCRIPT_DIR/statusline-layers.sh"
fi

# Source cache management functions
if [ -f "$SCRIPT_DIR/statusline-cache.sh" ]; then
    source "$SCRIPT_DIR/statusline-cache.sh"
fi

# ====================================================================================
# CONFIG VALIDATION
# ====================================================================================
validate_config() {
    local config_json=$1
    local errors=()

    # Helper function to check if a field exists and is not null
    check_required() {
        local field=$1
        local value=$(echo "$config_json" | jq -r "$field")
        if [[ "$value" == "null" || -z "$value" ]]; then
            errors+=("Missing required field: $field")
            return 1
        fi
        return 0
    }

    # Helper function to validate numeric range
    check_numeric_range() {
        local field=$1
        local min=$2
        local max=$3
        local value=$(echo "$config_json" | jq -r "$field")
        if [[ "$value" != "null" && -n "$value" ]]; then
            if (( $(awk "BEGIN {print ($value < $min || $value > $max)}") )); then
                errors+=("Field $field=$value is out of range [$min, $max]")
            fi
        fi
    }

    # Validate user plan
    check_required ".user.plan"
    local plan=$(echo "$config_json" | jq -r '.user.plan')
    if [[ "$plan" != "pro" && "$plan" != "max5x" && "$plan" != "max20x" ]]; then
        errors+=("Invalid user.plan: $plan (must be 'pro', 'max5x', or 'max20x')")
    fi

    # Validate limits
    check_required ".limits.weekly.$plan"
    check_required ".limits.cost"
    check_required ".limits.context"
    check_numeric_range ".limits.cost" 0 1000
    check_numeric_range ".limits.context" 0 1000

    # Validate multi-layer settings (5-hour window)
    check_required ".multi_layer.layer1.threshold_multiplier"
    check_required ".multi_layer.layer2.threshold_multiplier"
    check_required ".multi_layer.layer3.threshold_multiplier"
    check_numeric_range ".multi_layer.layer1.threshold_multiplier" 0 2
    check_numeric_range ".multi_layer.layer2.threshold_multiplier" 0 2
    check_numeric_range ".multi_layer.layer3.threshold_multiplier" 0 5

    check_required ".multi_layer.layer1.color"
    check_required ".multi_layer.layer2.color"
    check_required ".multi_layer.layer3.color"

    # Validate daily layer settings
    check_required ".daily_layer.layer1.threshold_multiplier"
    check_required ".daily_layer.layer2.threshold_multiplier"
    check_numeric_range ".daily_layer.layer1.threshold_multiplier" 0 2
    check_numeric_range ".daily_layer.layer2.threshold_multiplier" 0 5

    check_required ".daily_layer.layer1.color"
    check_required ".daily_layer.layer2.color"

    # Validate context layer settings
    check_required ".context_layer.layer1.threshold_multiplier"
    check_required ".context_layer.layer2.threshold_multiplier"
    check_required ".context_layer.layer3.threshold_multiplier"
    check_numeric_range ".context_layer.layer1.threshold_multiplier" 0 5
    check_numeric_range ".context_layer.layer2.threshold_multiplier" 0 5
    check_numeric_range ".context_layer.layer3.threshold_multiplier" 0 5

    check_required ".context_layer.layer1.color"
    check_required ".context_layer.layer2.color"
    check_required ".context_layer.layer3.color"

    # Validate display settings
    check_required ".display.bar_length"
    check_numeric_range ".display.bar_length" 5 50

    # Validate weekly scheme
    local weekly_scheme=$(echo "$config_json" | jq -r '.tracking.weekly_scheme')
    if [[ "$weekly_scheme" != "ccusage" && "$weekly_scheme" != "ccusage_r" && "$weekly_scheme" != "null" ]]; then
        errors+=("Invalid tracking.weekly_scheme: $weekly_scheme (must be 'ccusage' or 'ccusage_r')")
    fi

    # Validate official_reset_date if weekly_scheme is ccusage_r
    if [[ "$weekly_scheme" == "ccusage_r" ]]; then
        local reset_date=$(echo "$config_json" | jq -r '.tracking.official_reset_date')
        if [[ "$reset_date" == "null" || -z "$reset_date" ]]; then
            errors+=("tracking.official_reset_date is required when weekly_scheme is 'ccusage_r'")
        fi
    fi

    # Validate payment_cycle_start_date if show_monthly is true
    local show_monthly=$(echo "$config_json" | jq -r '.sections.show_monthly')
    if [[ "$show_monthly" == "true" ]]; then
        local payment_cycle=$(echo "$config_json" | jq -r '.tracking.payment_cycle_start_date')
        if [[ "$payment_cycle" == "null" || -z "$payment_cycle" ]]; then
            errors+=("tracking.payment_cycle_start_date is required when sections.show_monthly is true")
        fi
    fi

    # Validate color codes (basic check for ANSI format)
    local color_names=("orange" "bright_orange" "dim_orange" "red" "dim_red" "pink" "dim_pink" "bright_pink" "green" "dim_green" "purple" "cyan" "dim_blue" "reset")
    for color in "${color_names[@]}"; do
        check_required ".colors.$color"
    done

    # Report errors
    if [ ${#errors[@]} -gt 0 ]; then
        echo "❌ Configuration validation failed:" >&2
        for error in "${errors[@]}"; do
            echo "  - $error" >&2
        done
        echo "" >&2
        echo "Please check your config file: $CONFIG_FILE" >&2
        echo "See config.example.json for reference." >&2
        exit 1
    fi
}

# Load configuration from JSON file if it exists
if [ -f "$CONFIG_FILE" ]; then
    CONFIG=$(cat "$CONFIG_FILE")

    # Validate configuration before using it
    validate_config "$CONFIG"

    # User Configuration
    USER_PLAN=$(echo "$CONFIG" | jq -r '.user.plan')

    # Limits
    WEEKLY_LIMIT_PRO=$(echo "$CONFIG" | jq -r '.limits.weekly.pro')
    WEEKLY_LIMIT_MAX5X=$(echo "$CONFIG" | jq -r '.limits.weekly.max5x')
    WEEKLY_LIMIT_MAX20X=$(echo "$CONFIG" | jq -r '.limits.weekly.max20x')
    CONTEXT_LIMIT=$(echo "$CONFIG" | jq -r '.limits.context')
    COST_LIMIT=$(echo "$CONFIG" | jq -r '.limits.cost')
    TOKEN_LIMIT=$(echo "$CONFIG" | jq -r '.limits.token')

    # Paths
    CLAUDE_PROJECTS_PATH=$(echo "$CONFIG" | jq -r '.paths.claude_projects')

    # Display settings
    BAR_LENGTH=$(echo "$CONFIG" | jq -r '.display.bar_length')
    TRANSCRIPT_TAIL_LINES=$(echo "$CONFIG" | jq -r '.display.transcript_tail_lines')
    SESSION_ACTIVITY_THRESHOLD=$(echo "$CONFIG" | jq -r '.display.session_activity_threshold_minutes')
    SHOW_LABELS=$(echo "$CONFIG" | jq -r 'if .display.show_labels == null then "true" else .display.show_labels | tostring end')

    # ccusage version
    CCUSAGE_VERSION=$(echo "$CONFIG" | jq -r '.ccusage_version')

    # Multi-layer settings (5-hour window)
    LAYER1_THRESHOLD_MULT=$(echo "$CONFIG" | jq -r '.multi_layer.layer1.threshold_multiplier')
    LAYER2_THRESHOLD_MULT=$(echo "$CONFIG" | jq -r '.multi_layer.layer2.threshold_multiplier')
    LAYER3_THRESHOLD_MULT=$(echo "$CONFIG" | jq -r '.multi_layer.layer3.threshold_multiplier')

    LAYER1_COLOR=$(echo "$CONFIG" | jq -r '.multi_layer.layer1.color')
    LAYER2_COLOR=$(echo "$CONFIG" | jq -r '.multi_layer.layer2.color')
    LAYER3_COLOR=$(echo "$CONFIG" | jq -r '.multi_layer.layer3.color')

    # Daily layer settings
    DAILY_LAYER1_THRESHOLD_MULT=$(echo "$CONFIG" | jq -r '.daily_layer.layer1.threshold_multiplier')
    DAILY_LAYER2_THRESHOLD_MULT=$(echo "$CONFIG" | jq -r '.daily_layer.layer2.threshold_multiplier')

    DAILY_LAYER1_COLOR=$(echo "$CONFIG" | jq -r '.daily_layer.layer1.color')
    DAILY_LAYER2_COLOR=$(echo "$CONFIG" | jq -r '.daily_layer.layer2.color')

    # Context layer settings
    CTX_LAYER1_THRESHOLD_MULT=$(echo "$CONFIG" | jq -r '.context_layer.layer1.threshold_multiplier')
    CTX_LAYER2_THRESHOLD_MULT=$(echo "$CONFIG" | jq -r '.context_layer.layer2.threshold_multiplier')
    CTX_LAYER3_THRESHOLD_MULT=$(echo "$CONFIG" | jq -r '.context_layer.layer3.threshold_multiplier')

    CTX_LAYER1_COLOR=$(echo "$CONFIG" | jq -r '.context_layer.layer1.color')
    CTX_LAYER2_COLOR=$(echo "$CONFIG" | jq -r '.context_layer.layer2.color')
    CTX_LAYER3_COLOR=$(echo "$CONFIG" | jq -r '.context_layer.layer3.color')

    # Section toggles (use 'if null' to avoid treating false as falsy)
    SHOW_DIRECTORY=$(echo "$CONFIG" | jq -r 'if .sections.show_directory == null then "true" else .sections.show_directory | tostring end')
    SHOW_CONTEXT=$(echo "$CONFIG" | jq -r 'if .sections.show_context == null then "true" else .sections.show_context | tostring end')
    SHOW_FIVE_HOUR_WINDOW=$(echo "$CONFIG" | jq -r 'if .sections.show_five_hour_window == null then "true" else .sections.show_five_hour_window | tostring end')
    SHOW_DAILY=$(echo "$CONFIG" | jq -r 'if .sections.show_daily == null then "true" else .sections.show_daily | tostring end')
    SHOW_WEEKLY=$(echo "$CONFIG" | jq -r 'if .sections.show_weekly == null then "true" else .sections.show_weekly | tostring end')
    SHOW_MONTHLY=$(echo "$CONFIG" | jq -r 'if .sections.show_monthly == null then "false" else .sections.show_monthly | tostring end')
    SHOW_TIMER=$(echo "$CONFIG" | jq -r 'if .sections.show_timer == null then "true" else .sections.show_timer | tostring end')
    SHOW_TOKEN_RATE=$(echo "$CONFIG" | jq -r 'if .sections.show_token_rate == null then "true" else .sections.show_token_rate | tostring end')
    SHOW_SESSIONS=$(echo "$CONFIG" | jq -r 'if .sections.show_sessions == null then "true" else .sections.show_sessions | tostring end')
    WEEKLY_DISPLAY_MODE=$(echo "$CONFIG" | jq -r '.sections.weekly_display_mode')

    # Tracking settings
    WEEKLY_SCHEME=$(echo "$CONFIG" | jq -r '.tracking.weekly_scheme')
    OFFICIAL_RESET_DATE=$(echo "$CONFIG" | jq -r '.tracking.official_reset_date')
    PAYMENT_CYCLE_START_DATE=$(echo "$CONFIG" | jq -r '.tracking.payment_cycle_start_date')
    WEEKLY_BASELINE_PCT=$(echo "$CONFIG" | jq -r '.tracking.weekly_baseline_percent')
    CACHE_DURATION=$(echo "$CONFIG" | jq -r '.tracking.cache_duration_seconds')

    # Color codes (trust config is complete, no fallbacks)
    ORANGE_CODE=$(echo "$CONFIG" | jq -r '.colors.orange' | sed 's/\\\\/\\/g')
    BRIGHT_ORANGE_CODE=$(echo "$CONFIG" | jq -r '.colors.bright_orange' | sed 's/\\\\/\\/g')
    DIM_ORANGE_CODE=$(echo "$CONFIG" | jq -r '.colors.dim_orange' | sed 's/\\\\/\\/g')
    RED_CODE=$(echo "$CONFIG" | jq -r '.colors.red' | sed 's/\\\\/\\/g')
    DIM_RED_CODE=$(echo "$CONFIG" | jq -r '.colors.dim_red' | sed 's/\\\\/\\/g')
    PINK_CODE=$(echo "$CONFIG" | jq -r '.colors.pink' | sed 's/\\\\/\\/g')
    DIM_PINK_CODE=$(echo "$CONFIG" | jq -r '.colors.dim_pink' | sed 's/\\\\/\\/g')
    BRIGHT_PINK_CODE=$(echo "$CONFIG" | jq -r '.colors.bright_pink' | sed 's/\\\\/\\/g')
    GREEN_CODE=$(echo "$CONFIG" | jq -r '.colors.green' | sed 's/\\\\/\\/g')
    DIM_GREEN_CODE=$(echo "$CONFIG" | jq -r '.colors.dim_green' | sed 's/\\\\/\\/g')
    PURPLE_CODE=$(echo "$CONFIG" | jq -r '.colors.purple' | sed 's/\\\\/\\/g')
    CYAN_CODE=$(echo "$CONFIG" | jq -r '.colors.cyan' | sed 's/\\\\/\\/g')
    DIM_BLUE_CODE=$(echo "$CONFIG" | jq -r '.colors.dim_blue' | sed 's/\\\\/\\/g')
    RESET_CODE=$(echo "$CONFIG" | jq -r '.colors.reset' | sed 's/\\\\/\\/g')
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
    SHOW_LABELS="true"
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
    # Default daily layer settings (two-layer system)
    DAILY_LAYER1_THRESHOLD=14.29
    DAILY_LAYER2_THRESHOLD=21.44
    DAILY_LAYER1_COLOR="green"
    DAILY_LAYER2_COLOR="orange"
    # Calculate daily multipliers dynamically
    DAILY_LAYER1_MULTIPLIER=$(awk "BEGIN {printf \"%.2f\", 100 / $DAILY_LAYER1_THRESHOLD}")
    DAILY_LAYER2_MULTIPLIER=$(awk "BEGIN {printf \"%.2f\", 100 / ($DAILY_LAYER2_THRESHOLD - $DAILY_LAYER1_THRESHOLD)}")
    # Default section toggles (all strings for consistency)
    SHOW_DIRECTORY="true"
    SHOW_CONTEXT="true"
    SHOW_FIVE_HOUR_WINDOW="true"
    SHOW_DAILY="true"
    SHOW_WEEKLY="true"
    SHOW_MONTHLY="false"
    SHOW_TIMER="true"
    SHOW_TOKEN_RATE="true"
    SHOW_SESSIONS="true"
    # Default tracking settings
    WEEKLY_BASELINE_PCT=0
    CACHE_DURATION=300
    PAYMENT_CYCLE_START_DATE=""

    # Default color codes
    ORANGE_CODE='\033[1;93m'
    BRIGHT_ORANGE_CODE='\033[38;5;208m'
    DIM_ORANGE_CODE='\033[2;38;5;208m'
    RED_CODE='\033[31m'
    DIM_RED_CODE='\033[2;31m'
    PINK_CODE='\033[38;5;225m'
    DIM_PINK_CODE='\033[2;38;5;225m'
    BRIGHT_PINK_CODE='\033[1;38;5;225m'
    GREEN_CODE='\033[38;5;194m'
    DIM_GREEN_CODE='\033[2;38;5;194m'
    PURPLE_CODE='\033[35m'
    CYAN_CODE='\033[96m'
    DIM_BLUE_CODE='\033[94m'
    RESET_CODE='\033[0m'

    # Default layer multipliers
    LAYER1_THRESHOLD_MULT=0.3
    LAYER2_THRESHOLD_MULT=0.5
    LAYER3_THRESHOLD_MULT=1.0

    DAILY_LAYER1_THRESHOLD_MULT=1.0
    DAILY_LAYER2_THRESHOLD_MULT=1.5

    CTX_LAYER1_THRESHOLD_MULT=1.0
    CTX_LAYER2_THRESHOLD_MULT=2.0
    CTX_LAYER3_THRESHOLD_MULT=3.0

    # Default layer colors
    LAYER1_COLOR="green"
    LAYER2_COLOR="orange"
    LAYER3_COLOR="red"

    DAILY_LAYER1_COLOR="green"
    DAILY_LAYER2_COLOR="orange"

    CTX_LAYER1_COLOR="dim_pink"
    CTX_LAYER2_COLOR="dim_orange"
    CTX_LAYER3_COLOR="dim_red"
fi

# Helper function: map color name to ANSI code
get_color_code() {
    case "$1" in
        "orange") echo "$ORANGE_CODE" ;;
        "bright_orange") echo "$BRIGHT_ORANGE_CODE" ;;
        "dim_orange") echo "$DIM_ORANGE_CODE" ;;
        "red") echo "$RED_CODE" ;;
        "dim_red") echo "$DIM_RED_CODE" ;;
        "pink") echo "$PINK_CODE" ;;
        "dim_pink") echo "$DIM_PINK_CODE" ;;
        "bright_pink") echo "$BRIGHT_PINK_CODE" ;;
        "green") echo "$GREEN_CODE" ;;
        "dim_green") echo "$DIM_GREEN_CODE" ;;
        "purple") echo "$PURPLE_CODE" ;;
        "cyan") echo "$CYAN_CODE" ;;
        *) echo "$GREEN_CODE" ;;
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

# ====================================================================================
# CACHE DEPENDENCY VALIDATION
# ====================================================================================
# Validate that cached data dependencies haven't changed
# If weekly_limit or weekly_baseline_pct changed, invalidate all caches
if type check_and_update_cache_deps &>/dev/null; then
    check_and_update_cache_deps "$WEEKLY_LIMIT" "$WEEKLY_BASELINE_PCT"
fi

# ====================================================================================
# THREE-STAGE PIPELINE ARCHITECTURE
# ====================================================================================
# This statusline follows a three-stage pipeline for data flow:
#
# STAGE 1: DATA COLLECTION
#   - Parse input (workspace, transcript_path)
#   - Fetch external data (ccusage, transcript tokens, timestamps)
#   - All external process calls happen here
#   - Conditional: only collect data for enabled sections
#
# STAGE 2: COMPUTATION
#   - Calculate derived metrics (percentages, layers, projections)
#   - Determine visual properties (colors, filled blocks)
#   - Apply layer calculation functions
#   - No external calls, pure computation on collected data
#
# STAGE 3: RENDERING
#   - Build progress bars and formatted strings
#   - Assemble statusline sections
#   - Apply colors and formatting codes
#   - Output final statusline string
#
# Benefits:
#   - Clear separation of concerns
#   - Easier to test individual stages
#   - Obvious data dependencies
#   - Conditional evaluation for performance
# ====================================================================================

# ====================================================================================
# STAGE 1: DATA COLLECTION
# ====================================================================================

# Extract basic information from JSON input
CURRENT_DIR=$(echo "$input" | jq -r '.workspace.current_dir // "~"')
DIR_NAME="${CURRENT_DIR##*/}"
# Sanitize DIR_NAME to prevent ANSI injection
DIR_NAME=$(printf '%s' "$DIR_NAME" | tr -d '\000-\037\177')
TRANSCRIPT_PATH=$(echo "$input" | jq -r '.transcript_path // ""')

# Get 5-hour window data from ccusage (needed by 5-HOUR WINDOW, TIMER, and/or TOKEN_RATE sections)
# Only fetch if at least one of these sections is enabled
if [ "$SHOW_FIVE_HOUR_WINDOW" = "true" ] || [ "$SHOW_TIMER" = "true" ] || [ "$SHOW_TOKEN_RATE" = "true" ]; then
    # Use --offline for faster execution with cached pricing
    # Filter out npm warnings and capture only the JSON
    WINDOW_DATA=$(cd ~ && npx --yes "ccusage@${CCUSAGE_VERSION}" blocks --active --json --token-limit $TOKEN_LIMIT --offline 2>/dev/null | awk '/^{/,0')

    if [ -n "$WINDOW_DATA" ] && [ "$WINDOW_DATA" != "null" ]; then
        # Parse window data
        BLOCK=$(echo "$WINDOW_DATA" | jq -r '.blocks[0] // empty')

        if [ -n "$BLOCK" ]; then
            # Extract cost and projection data (needed by daily projection)
            COST=$(echo "$BLOCK" | jq -r '.costUSD // 0')

            # Extract burn rate data for more accurate projection
            COST_PER_HOUR=$(echo "$BLOCK" | jq -r '.burnRate.costPerHour // 0')
            REMAINING_MINUTES=$(echo "$BLOCK" | jq -r '.projection.remainingMinutes // 0')
            TOKENS_PER_MINUTE=$(echo "$BLOCK" | jq -r '.burnRate.tokensPerMinuteForIndicator // 0')

            # Calculate burn-rate based projection (more accurate for recent activity)
            # Formula: current_cost + (burn_rate × remaining_time)
            if [ "$COST_PER_HOUR" != "0" ] && [ "$REMAINING_MINUTES" != "0" ]; then
                PROJECTED_COST=$(awk "BEGIN {printf \"%.2f\", $COST + ($COST_PER_HOUR * $REMAINING_MINUTES / 60)}")
            else
                # Fallback to ccusage's linear projection if burn rate unavailable
                PROJECTED_COST=$(echo "$BLOCK" | jq -r '.projection.totalCost // 0')
            fi

            # ========================================================================
            # 5-HOUR WINDOW SECTION (conditional display)
            # ========================================================================
            if [ "$SHOW_FIVE_HOUR_WINDOW" = "true" ]; then

                # --- STAGE 2: COMPUTATION ---
                # Calculate actual percentage
                ACTUAL_PCT=$(awk "BEGIN {printf \"%.2f\", ($COST / $COST_LIMIT) * 100}")

                # Calculate layer metrics using generic function
                LAYER_RESULT=$(calculate_three_layer_metrics \
                    "$ACTUAL_PCT" \
                    "$COST_LIMIT" \
                    "$LAYER1_THRESHOLD_MULT" \
                    "$LAYER2_THRESHOLD_MULT" \
                    "$LAYER3_THRESHOLD_MULT" \
                    "$LAYER1_COLOR" \
                    "$LAYER2_COLOR" \
                    "$LAYER3_COLOR" \
                    "$BAR_LENGTH")
                IFS='|' read -r LAYER_NUM VISUAL_PCT BAR_COLOR FILLED <<< "$LAYER_RESULT"

                # Calculate layer thresholds and multipliers (needed for projection logic below)
                LAYER1_THRESHOLD=$(awk "BEGIN {printf \"%.2f\", $COST_LIMIT * $LAYER1_THRESHOLD_MULT}")
                LAYER2_THRESHOLD=$(awk "BEGIN {printf \"%.2f\", $COST_LIMIT * $LAYER2_THRESHOLD_MULT}")
                LAYER3_THRESHOLD=$(awk "BEGIN {printf \"%.2f\", $COST_LIMIT * $LAYER3_THRESHOLD_MULT}")
                LAYER1_MULTIPLIER=$(awk "BEGIN {printf \"%.2f\", 100 / $LAYER1_THRESHOLD}")
                LAYER2_MULTIPLIER=$(awk "BEGIN {printf \"%.2f\", 100 / ($LAYER2_THRESHOLD - $LAYER1_THRESHOLD)}")
                LAYER3_MULTIPLIER=$(awk "BEGIN {printf \"%.2f\", 100 / ($LAYER3_THRESHOLD - $LAYER2_THRESHOLD)}")

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

                # --- STAGE 3: RENDERING ---
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

            # ========================================================================
            # TOKEN RATE SECTION (conditional)
            # ========================================================================
            if [ "$SHOW_TOKEN_RATE" = "true" ]; then
                # TOKENS_PER_MINUTE already extracted above (billable tokens only)
                if [ -n "$TOKENS_PER_MINUTE" ] && [ "$TOKENS_PER_MINUTE" != "0" ]; then
                    # Format token rate (e.g., 928/min or 1.2k/min)
                    if (( $(awk "BEGIN {print ($TOKENS_PER_MINUTE >= 1000)}") )); then
                        # Display in thousands for large rates
                        TOKEN_RATE_DISPLAY=$(awk "BEGIN {printf \"%.1fk\", $TOKENS_PER_MINUTE / 1000}")
                    else
                        # Display as integer for small rates
                        TOKEN_RATE_DISPLAY=$(awk "BEGIN {printf \"%.0f\", $TOKENS_PER_MINUTE}")
                    fi
                    TOKEN_RATE="${TOKEN_RATE_DISPLAY}/min"
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

    # Calculate layer metrics using generic function
    CTX_LAYER_RESULT=$(calculate_three_layer_metrics \
        "$CONTEXT_TOKENS" \
        "$CONTEXT_LIMIT" \
        "$CTX_LAYER1_THRESHOLD_MULT" \
        "$CTX_LAYER2_THRESHOLD_MULT" \
        "$CTX_LAYER3_THRESHOLD_MULT" \
        "$CTX_LAYER1_COLOR" \
        "$CTX_LAYER2_COLOR" \
        "$CTX_LAYER3_COLOR" \
        "$BAR_LENGTH")
    IFS='|' read -r CTX_LAYER_NUM CTX_VISUAL_PCT CTX_COLOR_NAME CTX_FILLED <<< "$CTX_LAYER_RESULT"

    # Get color code from color name
    CTX_COLOR=$(get_color_code "$CTX_COLOR_NAME")

    # Create context progress bar (same length as cost bar)
    CTX_BAR_LENGTH=$BAR_LENGTH

    CTX_EMPTY=$((CTX_BAR_LENGTH - CTX_FILLED))

    # Build progress bar
    CTX_PROGRESS_BAR="["

    for ((i=0; i<CTX_FILLED; i++)); do
        CTX_PROGRESS_BAR="${CTX_PROGRESS_BAR}█"
    done

    for ((i=0; i<CTX_EMPTY; i++)); do
        CTX_PROGRESS_BAR="${CTX_PROGRESS_BAR}░"
    done

    CTX_PROGRESS_BAR="${CTX_PROGRESS_BAR}]"

    # Format context - separate total from breakdown
    CTX_TOTAL=$(printf "%dk/%dk" $CONTEXT_TOKENS $CONTEXT_LIMIT)
    CTX_BREAKDOWN=$(printf "%dk+%dk" $CACHED_TOKENS $FRESH_TOKENS)
fi

# ====================================================================================
# SHARED WEEKLY/DAILY SECTION DATA (integrated weekly tracker)
# ====================================================================================
if [ "$SHOW_WEEKLY" = "true" ] || [ "$SHOW_DAILY" = "true" ]; then
    # Get weekly usage based on configured tracking scheme (shared data source)
    if [ "$WEEKLY_SCHEME" = "ccusage_r" ] && [ -n "$OFFICIAL_RESET_DATE" ] && type get_official_weekly_cost &>/dev/null; then
        # Use ccusage costs filtered by official Anthropic reset schedule
        # Convert ISO timestamp to Unix format
        RESET_TIMESTAMP=$(iso_to_timestamp "$OFFICIAL_RESET_DATE")
        WEEK_COST_RAW=$(get_official_weekly_cost "$RESET_TIMESTAMP" "$CACHE_DURATION")
    else
        # Use ccusage with ISO weeks (default)
        WEEKLY_DATA=$(cd ~ && npx --yes "ccusage@${CCUSAGE_VERSION}" weekly --json --offline 2>/dev/null | awk '/^{/,0')
        WEEK_COST_RAW=$(echo "$WEEKLY_DATA" | jq -r '.weekly[-1].totalCost // 0')
    fi

    # Save raw cost for recommendation calculation (without baseline)
    WEEK_COST=$WEEK_COST_RAW

    # Apply baseline offset to account for untracked costs (for display only)
    if [ "$(awk "BEGIN {print ($WEEKLY_BASELINE_PCT != 0)}")" = "1" ]; then
        BASELINE_COST=$(awk "BEGIN {printf \"%.2f\", ($WEEKLY_LIMIT * $WEEKLY_BASELINE_PCT) / 100}")
        WEEK_COST=$(awk "BEGIN {printf \"%.2f\", $WEEK_COST + $BASELINE_COST}")
    fi

    WEEKLY_PCT=$(awk "BEGIN {printf \"%.0f\", ($WEEK_COST / $WEEKLY_LIMIT) * 100}")
fi

# ====================================================================================
# WEEKLY_DAILY_TRACKER (daily subsection - shows daily usage)
# ====================================================================================
# Calculate daily cost if daily is shown OR if weekly recommend mode needs it
if [ -n "$OFFICIAL_RESET_DATE" ] && type get_daily_cost &>/dev/null; then
    if [ "$SHOW_DAILY" = "true" ] || ([ "$SHOW_WEEKLY" = "true" ] && [ "$WEEKLY_DISPLAY_MODE" = "recommend" ]); then
        # Use daily cost tracking based on official reset time
        # Convert ISO timestamp to Unix format (reuse RESET_TIMESTAMP if already computed)
        if [ -z "${RESET_TIMESTAMP:-}" ]; then
            RESET_TIMESTAMP=$(iso_to_timestamp "$OFFICIAL_RESET_DATE")
        fi
        DAILY_COST=$(get_daily_cost "$RESET_TIMESTAMP" "$CACHE_DURATION")

        # Calculate daily percentage (needed for display and/or recommend calculation)
        DAILY_PCT=$(awk "BEGIN {printf \"%.2f\", ($DAILY_COST / $WEEKLY_LIMIT) * 100}")
    fi
fi

# Build daily visualization (only if SHOW_DAILY is enabled)
if [ "$SHOW_DAILY" = "true" ] && [ -n "${DAILY_COST:-}" ]; then

    # Calculate projection to end of current 5-hour window
    # Formula: daily_cost - current_window_cost + projected_window_cost
    # This gives us: accumulated daily usage + what the current session will add
    if [ -n "${COST:-}" ] && [ -n "${PROJECTED_COST:-}" ]; then
        # We have 5-hour window data available
        DAILY_PROJECTED_COST=$(awk "BEGIN {printf \"%.2f\", $DAILY_COST - $COST + $PROJECTED_COST}")
    else
        # No active 5-hour window, daily projection = current daily cost
        DAILY_PROJECTED_COST=$DAILY_COST
    fi

    # Calculate daily base threshold and layer thresholds
    if [ "$SHOW_WEEKLY" = "true" ] && [ "$WEEKLY_DISPLAY_MODE" = "recommend" ] && [ -n "${WEEKLY_DISPLAY_VALUE:-}" ]; then
        # Dynamic mode: base = recommend value
        DAILY_BASE_THRESHOLD=$WEEKLY_DISPLAY_VALUE
    else
        # Static mode: base = weekly_limit / 7
        DAILY_BASE_THRESHOLD=$(awk "BEGIN {printf \"%.2f\", ($WEEKLY_LIMIT / 7.0) / $WEEKLY_LIMIT * 100}")
    fi

    # Calculate layer metrics using generic function
    DAILY_LAYER_RESULT=$(calculate_two_layer_metrics \
        "$DAILY_PCT" \
        "$DAILY_BASE_THRESHOLD" \
        "$DAILY_LAYER1_THRESHOLD_MULT" \
        "$DAILY_LAYER2_THRESHOLD_MULT" \
        "$DAILY_LAYER1_COLOR" \
        "$DAILY_LAYER2_COLOR" \
        "$BAR_LENGTH")
    IFS='|' read -r DAILY_LAYER_NUM DAILY_VISUAL_PCT DAILY_BAR_COLOR DAILY_FILLED <<< "$DAILY_LAYER_RESULT"

    # Calculate layer thresholds and multipliers (needed for projection logic below)
    DAILY_USE_LAYER1_THRESHOLD=$(awk "BEGIN {printf \"%.2f\", $DAILY_BASE_THRESHOLD * $DAILY_LAYER1_THRESHOLD_MULT}")
    DAILY_USE_LAYER2_THRESHOLD=$(awk "BEGIN {printf \"%.2f\", $DAILY_BASE_THRESHOLD * $DAILY_LAYER2_THRESHOLD_MULT}")
    DAILY_USE_LAYER1_MULTIPLIER=$(awk "BEGIN {printf \"%.2f\", 100 / $DAILY_USE_LAYER1_THRESHOLD}")
    DAILY_USE_LAYER2_MULTIPLIER=$(awk "BEGIN {printf \"%.2f\", 100 / ($DAILY_USE_LAYER2_THRESHOLD - $DAILY_USE_LAYER1_THRESHOLD)}")

    # Calculate projected position using CURRENT layer's multiplier for consistent scale
    DAILY_PROJECTED_POS=-1
    DAILY_PROJECTED_BAR_COLOR="$DAILY_LAYER1_COLOR"
    if [ -n "$DAILY_PROJECTED_COST" ] && [ "$DAILY_PROJECTED_COST" != "0" ]; then
        DAILY_PROJECTED_ACTUAL_PCT=$(awk "BEGIN {printf \"%.2f\", ($DAILY_PROJECTED_COST / $WEEKLY_LIMIT) * 100}")

        # Determine projection color based on which layer it falls into
        if (( $(awk "BEGIN {print ($DAILY_PROJECTED_ACTUAL_PCT <= $DAILY_USE_LAYER1_THRESHOLD)}") )); then
            DAILY_PROJECTED_BAR_COLOR="$DAILY_LAYER1_COLOR"
        else
            DAILY_PROJECTED_BAR_COLOR="$DAILY_LAYER2_COLOR"
        fi

        # Calculate visual position using CURRENT layer's multiplier (same scale as current bar)
        if [ "$DAILY_BAR_COLOR" = "$DAILY_LAYER1_COLOR" ]; then
            DAILY_PROJECTED_VISUAL_PCT=$(awk "BEGIN {printf \"%.2f\", $DAILY_PROJECTED_ACTUAL_PCT * $DAILY_USE_LAYER1_MULTIPLIER}")
        else
            DAILY_PROJECTED_VISUAL_PCT=$(awk "BEGIN {printf \"%.2f\", ($DAILY_PROJECTED_ACTUAL_PCT - $DAILY_USE_LAYER1_THRESHOLD) * $DAILY_USE_LAYER2_MULTIPLIER}")
        fi

        if (( $(awk "BEGIN {print ($DAILY_PROJECTED_VISUAL_PCT > 100)}") )); then
            DAILY_PROJECTED_VISUAL_PCT=100
        fi

        DAILY_PROJECTED_POS=$(awk "BEGIN {printf \"%.0f\", ($DAILY_PROJECTED_VISUAL_PCT / 100) * $BAR_LENGTH}")
        if [ $DAILY_PROJECTED_POS -gt $BAR_LENGTH ]; then
            DAILY_PROJECTED_POS=$BAR_LENGTH
        fi

        # Don't show separator if projection equals current cost (no actual projection)
        # Use cost comparison instead of position to handle rounding cases
        if (( $(awk "BEGIN {print ($DAILY_PROJECTED_COST == $DAILY_COST)}") )); then
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
# WEEKLY_TRACKER (weekly subsection - shows weekly usage/avail/recommend)
# ====================================================================================
if [ "$SHOW_WEEKLY" = "true" ] && [ -n "${WEEKLY_PCT:-}" ]; then
    # Calculate display value and label based on mode
    case "$WEEKLY_DISPLAY_MODE" in
        "avail")
            WEEKLY_DISPLAY_VALUE=$(awk "BEGIN {printf \"%.0f\", 100 - $WEEKLY_PCT}")
            WEEKLY_LABEL="avail"
            ;;
        "recommend")
            # Calculate recommended daily usage for stable budgeting
            # Formula: (weekly_limit - usage_from_weekly_start_to_daily_cycle_start) / cycles_left
            # This gives budget available at current daily cycle start (e.g., 3pm today)
            # Stays stable throughout the day, updates only at daily cycle reset

            if [ -z "${RESET_TIMESTAMP:-}" ] && [ -n "$OFFICIAL_RESET_DATE" ] && type iso_to_timestamp &>/dev/null; then
                RESET_TIMESTAMP=$(iso_to_timestamp "$OFFICIAL_RESET_DATE")
            fi

            if [ -n "${RESET_TIMESTAMP:-}" ] && type get_anthropic_period &>/dev/null && type get_daily_period &>/dev/null; then
                # Get weekly and daily period boundaries
                PERIOD_DATA=$(get_anthropic_period "$RESET_TIMESTAMP")
                WEEKLY_START=$(echo "$PERIOD_DATA" | jq -r '.start')
                NEXT_RESET=$(echo "$PERIOD_DATA" | jq -r '.end')

                DAILY_PERIOD=$(get_daily_period "$RESET_TIMESTAMP")
                DAILY_CYCLE_START=$(echo "$DAILY_PERIOD" | jq -r '.start')

                # Calculate usage from weekly start to current daily cycle start
                # This captures all completed daily cycles in the week
                WEEKLY_START_ISO=$(timestamp_to_iso "$WEEKLY_START")
                DAILY_CYCLE_START_ISO=$(timestamp_to_iso "$DAILY_CYCLE_START")

                # Query ccusage blocks for costs between weekly start and daily cycle start
                BLOCKS_DATA=$(cd ~ && npx --yes ccusage blocks --json --offline 2>/dev/null | awk '/^{/,0')

                if [ -n "$BLOCKS_DATA" ] && [ "$BLOCKS_DATA" != "null" ]; then
                    COST_BEFORE_CYCLE=$(echo "$BLOCKS_DATA" | jq -r --arg start "$WEEKLY_START_ISO" --arg end "$DAILY_CYCLE_START_ISO" '
                        [.blocks[] |
                         select(
                           (.startTime >= $start) and
                           (.startTime < $end)
                         ) |
                         .costUSD
                        ] | add // 0
                    ')

                    # Weekly available at current daily cycle start
                    WEEKLY_AVAIL_AT_CYCLE_START=$(awk "BEGIN {printf \"%.2f\", $WEEKLY_LIMIT - $COST_BEFORE_CYCLE}")
                    WEEKLY_AVAIL_PCT=$(awk "BEGIN {printf \"%.2f\", ($WEEKLY_AVAIL_AT_CYCLE_START / $WEEKLY_LIMIT) * 100}")

                    # Calculate cycles left from now to NEXT reset
                    CURRENT_TIME=$(date +%s)
                    TIME_UNTIL_RESET=$((NEXT_RESET - CURRENT_TIME))
                    CYCLES_LEFT=$(awk "BEGIN {hours = $TIME_UNTIL_RESET / 3600; cycles = hours / 24; print (cycles == int(cycles)) ? int(cycles) : int(cycles) + 1}")

                    if [ "$CYCLES_LEFT" -gt 0 ]; then
                        WEEKLY_DISPLAY_VALUE=$(awk "BEGIN {printf \"%.0f\", $WEEKLY_AVAIL_PCT / $CYCLES_LEFT}")
                    else
                        WEEKLY_DISPLAY_VALUE="0"
                    fi
                else
                    # Fallback to usage if data unavailable
                    WEEKLY_DISPLAY_VALUE="$WEEKLY_PCT"
                fi
            else
                # Fallback to usage if data unavailable
                WEEKLY_DISPLAY_VALUE="$WEEKLY_PCT"
            fi
            WEEKLY_LABEL="recom"
            ;;
        *)
            # Default: usage mode
            WEEKLY_DISPLAY_VALUE="$WEEKLY_PCT"
            WEEKLY_LABEL="weekly"
            ;;
    esac

    # Match color with daily section if daily is enabled, otherwise use layer logic
    if [ "$SHOW_DAILY" = "true" ] && [ -n "${DAILY_BAR_COLOR:-}" ]; then
        # Use same color as daily section
        WEEKLY_COLOR=$(get_color_code "$DAILY_BAR_COLOR")
    else
        # Apply layer logic directly to weekly percentage using static base
        WEEKLY_STATIC_BASE=$(awk "BEGIN {printf \"%.2f\", ($WEEKLY_LIMIT / 7.0) / $WEEKLY_LIMIT * 100}")
        WEEKLY_LAYER1=$(awk "BEGIN {printf \"%.2f\", $WEEKLY_STATIC_BASE * $DAILY_LAYER1_THRESHOLD_MULT}")

        if (( $(awk "BEGIN {print ($WEEKLY_PCT <= $WEEKLY_LAYER1)}") )); then
            WEEKLY_COLOR=$(get_color_code "$DAILY_LAYER1_COLOR")
        else
            WEEKLY_COLOR=$(get_color_code "$DAILY_LAYER2_COLOR")
        fi
    fi
fi

# ====================================================================================
# MONTHLY COST SECTION (independent)
# ====================================================================================
if [ "$SHOW_MONTHLY" = "true" ] && [ -n "$PAYMENT_CYCLE_START_DATE" ] && type get_monthly_cost &>/dev/null; then
    # Convert payment cycle start date to Unix timestamp
    PAYMENT_CYCLE_TIMESTAMP=$(iso_to_timestamp "$PAYMENT_CYCLE_START_DATE")

    # Get monthly cost with caching
    MONTHLY_COST=$(get_monthly_cost "$PAYMENT_CYCLE_TIMESTAMP" "$CACHE_DURATION")

    # Format monthly cost display
    if [ -n "$MONTHLY_COST" ] && [ "$MONTHLY_COST" != "0" ]; then
        MONTHLY_COST_DISPLAY=$(awk "BEGIN {printf \"%.0f\", $MONTHLY_COST}")
    fi
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
# STAGE 3: RENDERING - FINAL ASSEMBLY
# ====================================================================================
# Assemble all computed sections into the final statusline output.
# Each section has already completed its own data→compute→render pipeline.
# This stage conditionally includes sections based on:
#   - Section toggle settings (show_*)
#   - Data availability (presence of computed values)
# ====================================================================================

STATUSLINE_SECTIONS=()

# Directory section
[[ "$SHOW_DIRECTORY" == "true" ]] && STATUSLINE_SECTIONS+=("${ORANGE_CODE}${DIR_NAME}${RESET_CODE}")

[[ "$SHOW_CONTEXT" == "true" ]] && [[ -n "${CTX_TOTAL:-}" ]] && STATUSLINE_SECTIONS+=("${CTX_COLOR}${CTX_TOTAL} ${CTX_PROGRESS_BAR}${RESET_CODE}")
[[ "$SHOW_FIVE_HOUR_WINDOW" == "true" ]] && [[ -n "${COST_FMT:-}" ]] && STATUSLINE_SECTIONS+=("${PROGRESS_COLOR}${COST_FMT} ${PROGRESS_BAR} ${COST_PERCENTAGE}%${RESET_CODE}")

# Add daily/weekly combined or separate sections
if [[ "$SHOW_DAILY" == "true" ]] && [[ "$SHOW_WEEKLY" == "true" ]] && [[ "$WEEKLY_DISPLAY_MODE" == "recommend" ]] && [[ -n "${DAILY_PROGRESS_BAR:-}" ]] && [[ -n "${WEEKLY_DISPLAY_VALUE:-}" ]]; then
    # Combined mode: daily [bar] actual/recommend% $actual/$recommend (with dimmed portions)
    DIM_CODE="\033[2m"

    # Calculate recommend daily cost from precise dollar amount (not rounded percentage)
    # This avoids rounding error: $850/7 = $121 (not 14% × $850 = $119)
    if [ -n "${WEEKLY_AVAIL_AT_CYCLE_START:-}" ] && [ -n "${CYCLES_LEFT:-}" ] && [ "$CYCLES_LEFT" -gt 0 ]; then
        RECOMMEND_DAILY_COST=$(awk "BEGIN {printf \"%.0f\", $WEEKLY_AVAIL_AT_CYCLE_START / $CYCLES_LEFT}")
    else
        # Fallback to percentage-based calculation
        RECOMMEND_DAILY_COST=$(awk "BEGIN {printf \"%.0f\", ($WEEKLY_DISPLAY_VALUE / 100) * $WEEKLY_LIMIT}")
    fi

    DAILY_COST_DISPLAY=$(awk "BEGIN {printf \"%.0f\", $DAILY_COST}")

    # Conditionally show "daily " label
    if [[ "$SHOW_LABELS" == "true" ]]; then
        STATUSLINE_SECTIONS+=("${DAILY_COLOR}daily ${DAILY_PROGRESS_BAR} ${DAILY_PCT_DISPLAY}${DIM_CODE}/${WEEKLY_DISPLAY_VALUE}% \$${DAILY_COST_DISPLAY}/\$${RECOMMEND_DAILY_COST}${RESET_CODE}")
    else
        STATUSLINE_SECTIONS+=("${DAILY_COLOR}${DAILY_PROGRESS_BAR} ${DAILY_PCT_DISPLAY}${DIM_CODE}/${WEEKLY_DISPLAY_VALUE}% \$${DAILY_COST_DISPLAY}/\$${RECOMMEND_DAILY_COST}${RESET_CODE}")
    fi
elif [[ "$SHOW_DAILY" == "true" ]] && [[ -n "${DAILY_PROGRESS_BAR:-}" ]]; then
    # Daily only
    if [[ "$SHOW_LABELS" == "true" ]]; then
        STATUSLINE_SECTIONS+=("${DAILY_COLOR}daily ${DAILY_PROGRESS_BAR} ${DAILY_PCT_DISPLAY}%${RESET_CODE}")
    else
        STATUSLINE_SECTIONS+=("${DAILY_COLOR}${DAILY_PROGRESS_BAR} ${DAILY_PCT_DISPLAY}%${RESET_CODE}")
    fi
fi

# Weekly section (only if not already combined with daily)
if [[ "$SHOW_WEEKLY" == "true" ]] && [[ -n "${WEEKLY_DISPLAY_VALUE:-}" ]]; then
    if [[ "$SHOW_DAILY" != "true" ]] || [[ "$WEEKLY_DISPLAY_MODE" != "recommend" ]]; then
        # Conditionally show weekly label
        if [[ "$SHOW_LABELS" == "true" ]]; then
            STATUSLINE_SECTIONS+=("${WEEKLY_COLOR}${WEEKLY_LABEL} ${WEEKLY_DISPLAY_VALUE}%${RESET_CODE}")
        else
            STATUSLINE_SECTIONS+=("${WEEKLY_COLOR}${WEEKLY_DISPLAY_VALUE}%${RESET_CODE}")
        fi
    fi
fi

# Monthly cost section (between weekly and timer)
if [[ "$SHOW_MONTHLY" == "true" ]] && [[ -n "${MONTHLY_COST_DISPLAY:-}" ]]; then
    # Conditionally show "total " label
    if [[ "$SHOW_LABELS" == "true" ]]; then
        STATUSLINE_SECTIONS+=("${DIM_BLUE_CODE}total \$${MONTHLY_COST_DISPLAY}${RESET_CODE}")
    else
        STATUSLINE_SECTIONS+=("${DIM_BLUE_CODE}\$${MONTHLY_COST_DISPLAY}${RESET_CODE}")
    fi
fi

[[ "$SHOW_TIMER" == "true" ]] && [[ -n "${RESET_INFO:-}" ]] && STATUSLINE_SECTIONS+=("${PURPLE_CODE}${RESET_INFO}${RESET_CODE}")
[[ "$SHOW_TOKEN_RATE" == "true" ]] && [[ -n "${TOKEN_RATE:-}" ]] && STATUSLINE_SECTIONS+=("${CYAN_CODE}${TOKEN_RATE}${RESET_CODE}")
[[ "$SHOW_SESSIONS" == "true" ]] && [[ -n "${ACTIVE_SESSIONS:-}" ]] && STATUSLINE_SECTIONS+=("${CYAN_CODE}×${ACTIVE_SESSIONS}${RESET_CODE}")

# Join sections with separator
# Define dimmed separator
DIM_CODE="\033[2m"
SEPARATOR=" ${DIM_CODE}|${RESET_CODE} "

STATUSLINE=""
FIRST=true
for section in "${STATUSLINE_SECTIONS[@]}"; do
    if [[ "$FIRST" == "true" ]]; then
        STATUSLINE="$section"
        FIRST=false
    else
        STATUSLINE="$STATUSLINE$SEPARATOR$section"
    fi
done

# Display statusline
if [ -n "$STATUSLINE" ]; then
    printf '%b\n' "$STATUSLINE"
else
    # Fallback if no sections enabled
    echo "$DIR_NAME | No active window"
fi
