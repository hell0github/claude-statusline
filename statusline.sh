#!/bin/bash
set -euo pipefail
input=$(cat)

# Configuration file path
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/statusline-config.json"

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

    # Multi-layer settings - load thresholds
    LAYER1_THRESHOLD=$(echo "$CONFIG" | jq -r '.multi_layer.layer1.threshold_percent // 30')
    LAYER2_THRESHOLD=$(echo "$CONFIG" | jq -r '.multi_layer.layer2.threshold_percent // 50')
    LAYER3_THRESHOLD=$(echo "$CONFIG" | jq -r '.multi_layer.layer3.threshold_percent // 100')

    # Calculate multipliers dynamically based on thresholds
    LAYER1_MULTIPLIER=$(awk "BEGIN {printf \"%.2f\", 100 / $LAYER1_THRESHOLD}")
    LAYER2_MULTIPLIER=$(awk "BEGIN {printf \"%.2f\", 100 / ($LAYER2_THRESHOLD - $LAYER1_THRESHOLD)}")
    LAYER3_MULTIPLIER=$(awk "BEGIN {printf \"%.2f\", 100 / ($LAYER3_THRESHOLD - $LAYER2_THRESHOLD)}")

    # Section toggles
    SHOW_DIRECTORY=$(echo "$CONFIG" | jq -r '.sections.show_directory // true')
    SHOW_CONTEXT=$(echo "$CONFIG" | jq -r '.sections.show_context // true')
    SHOW_COST=$(echo "$CONFIG" | jq -r '.sections.show_cost // true')
    SHOW_WEEKLY=$(echo "$CONFIG" | jq -r '.sections.show_weekly // true')
    SHOW_TIMER=$(echo "$CONFIG" | jq -r '.sections.show_timer // true')
    SHOW_SESSIONS=$(echo "$CONFIG" | jq -r '.sections.show_sessions // true')

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
    # Calculate multipliers dynamically
    LAYER1_MULTIPLIER=$(awk "BEGIN {printf \"%.2f\", 100 / $LAYER1_THRESHOLD}")
    LAYER2_MULTIPLIER=$(awk "BEGIN {printf \"%.2f\", 100 / ($LAYER2_THRESHOLD - $LAYER1_THRESHOLD)}")
    LAYER3_MULTIPLIER=$(awk "BEGIN {printf \"%.2f\", 100 / ($LAYER3_THRESHOLD - $LAYER2_THRESHOLD)}")
    # Default section toggles
    SHOW_DIRECTORY=true
    SHOW_CONTEXT=true
    SHOW_COST=true
    SHOW_WEEKLY=true
    SHOW_TIMER=true
    SHOW_SESSIONS=true
    # Default color codes
    ORANGE_CODE='\033[1;38;5;208m'
    RED_CODE='\033[1;31m'
    PINK_CODE='\033[38;5;225m'
    GREEN_CODE='\033[38;5;194m'
    PURPLE_CODE='\033[35m'
    CYAN_CODE='\033[96m'
    RESET_CODE='\033[0m'
fi

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

# Get 5-hour window data from ccusage
# Use --offline for faster execution with cached pricing
# Filter out npm warnings and capture only the JSON
WINDOW_DATA=$(cd ~ && npx --yes "ccusage@${CCUSAGE_VERSION}" blocks --active --json --token-limit $TOKEN_LIMIT --offline 2>/dev/null | awk '/^{/,0')

if [ -n "$WINDOW_DATA" ] && [ "$WINDOW_DATA" != "null" ]; then
    # Parse window data
    BLOCK=$(echo "$WINDOW_DATA" | jq -r '.blocks[0] // empty')

    if [ -n "$BLOCK" ]; then
        # Calculate context window usage from transcript
        # Use ccusage method: latest assistant message only
        # Separate cached (system overhead) vs fresh (conversation) context
        if [ -f "$TRANSCRIPT_PATH" ]; then
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
        else
            CACHED_TOKENS=0
            FRESH_TOKENS=0
            CONTEXT_TOKENS=0
        fi

        # Extract cost and projection
        COST=$(echo "$BLOCK" | jq -r '.costUSD // 0')
        PROJECTED_COST=$(echo "$BLOCK" | jq -r '.projection.totalCost // 0')

        # Get weekly usage
        WEEKLY_DATA=$(cd ~ && npx --yes "ccusage@${CCUSAGE_VERSION}" weekly --json --offline 2>/dev/null | awk '/^{/,0')
        WEEK_COST=$(echo "$WEEKLY_DATA" | jq -r '.weekly[-1].totalCost // 0')
        WEEKLY_PCT=$(awk "BEGIN {printf \"%.0f\", ($WEEK_COST / $WEEKLY_LIMIT) * 100}")

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

        # Format reset time (simplified format: 2AM, 10PM, etc)
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

        # Multi-layer progress bar (using config-defined settings)
        # Calculate actual percentage
        ACTUAL_PCT=$(awk "BEGIN {printf \"%.2f\", ($COST / $COST_LIMIT) * 100}")

        # Determine layer and calculate visual progress
        if (( $(awk "BEGIN {print ($ACTUAL_PCT <= $LAYER1_THRESHOLD)}") )); then
            # Layer 1: 0-threshold% actual → 0-100% visual
            VISUAL_PCT=$(awk "BEGIN {printf \"%.2f\", $ACTUAL_PCT * $LAYER1_MULTIPLIER}")
            BAR_COLOR="GREEN"
        elif (( $(awk "BEGIN {print ($ACTUAL_PCT <= $LAYER2_THRESHOLD)}") )); then
            # Layer 2: threshold1-threshold2% actual → 0-100% visual
            VISUAL_PCT=$(awk "BEGIN {printf \"%.2f\", ($ACTUAL_PCT - $LAYER1_THRESHOLD) * $LAYER2_MULTIPLIER}")
            BAR_COLOR="ORANGE"
        else
            # Layer 3: threshold2-threshold3% actual → 0-100% visual
            VISUAL_PCT=$(awk "BEGIN {printf \"%.2f\", ($ACTUAL_PCT - $LAYER2_THRESHOLD) * $LAYER3_MULTIPLIER}")
            if (( $(awk "BEGIN {print ($VISUAL_PCT > 100)}") )); then
                VISUAL_PCT=100
            fi
            BAR_COLOR="RED"
        fi

        # Calculate filled blocks based on visual percentage
        FILLED=$(awk "BEGIN {printf \"%.0f\", ($VISUAL_PCT / 100) * $BAR_LENGTH}")
        if [ $FILLED -gt $BAR_LENGTH ]; then
            FILLED=$BAR_LENGTH
        fi

        # Calculate projected position with same multi-layer logic
        PROJECTED_POS=-1
        PROJECTED_BAR_COLOR="GREEN"
        if [ -n "$PROJECTED_COST" ] && [ "$PROJECTED_COST" != "0" ]; then
            PROJECTED_ACTUAL_PCT=$(awk "BEGIN {printf \"%.2f\", ($PROJECTED_COST / $COST_LIMIT) * 100}")

            # Apply same layer logic to projection
            if (( $(awk "BEGIN {print ($PROJECTED_ACTUAL_PCT <= $LAYER1_THRESHOLD)}") )); then
                PROJECTED_VISUAL_PCT=$(awk "BEGIN {printf \"%.2f\", $PROJECTED_ACTUAL_PCT * $LAYER1_MULTIPLIER}")
                PROJECTED_BAR_COLOR="GREEN"
            elif (( $(awk "BEGIN {print ($PROJECTED_ACTUAL_PCT <= $LAYER2_THRESHOLD)}") )); then
                PROJECTED_VISUAL_PCT=$(awk "BEGIN {printf \"%.2f\", ($PROJECTED_ACTUAL_PCT - $LAYER1_THRESHOLD) * $LAYER2_MULTIPLIER}")
                PROJECTED_BAR_COLOR="ORANGE"
            else
                PROJECTED_VISUAL_PCT=$(awk "BEGIN {printf \"%.2f\", ($PROJECTED_ACTUAL_PCT - $LAYER2_THRESHOLD) * $LAYER3_MULTIPLIER}")
                if (( $(awk "BEGIN {print ($PROJECTED_VISUAL_PCT > 100)}") )); then
                    PROJECTED_VISUAL_PCT=100
                fi
                PROJECTED_BAR_COLOR="RED"
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

        # Set projected separator color
        case "$PROJECTED_BAR_COLOR" in
            "GREEN")
                PROJECTED_COLOR="$GREEN_CODE"
                ;;
            "ORANGE")
                PROJECTED_COLOR="$ORANGE_CODE"
                ;;
            "RED")
                PROJECTED_COLOR="$RED_CODE"
                ;;
            *)
                PROJECTED_COLOR="$GREEN_CODE"
                ;;
        esac

        # Set current progress bar color
        case "$BAR_COLOR" in
            "GREEN")
                CURRENT_COLOR="$GREEN_CODE"
                ;;
            "ORANGE")
                CURRENT_COLOR="$ORANGE_CODE"
                ;;
            "RED")
                CURRENT_COLOR="$RED_CODE"
                ;;
            *)
                CURRENT_COLOR="$GREEN_CODE"
                ;;
        esac

        # Build progress bar with colored projection separator
        PROGRESS_BAR="["
        for ((i=0; i<BAR_LENGTH; i++)); do
            if [ $i -lt $FILLED ]; then
                PROGRESS_BAR="${PROGRESS_BAR}█"
            elif [ $i -eq $PROJECTED_POS ]; then
                # Projection separator with its own layer color
                PROGRESS_BAR="${PROGRESS_BAR}${RESET_CODE}${PROJECTED_COLOR}│${RESET_CODE}${CURRENT_COLOR}"
            else
                PROGRESS_BAR="${PROGRESS_BAR}░"
            fi
        done
        PROGRESS_BAR="${PROGRESS_BAR}]"

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

        # Calculate cost percentage
        COST_PERCENTAGE=$(awk "BEGIN {printf \"%.0f\", ($COST / $COST_LIMIT) * 100}")

        # Format cost
        COST_FMT=$(printf "\$%.0f/\$%d" $COST $COST_LIMIT)

        # Format reset info
        if [ -n "$RESET_TIME" ]; then
            RESET_INFO="$RESET_TIME ($TIME_LEFT)"
        else
            RESET_INFO="$TIME_LEFT"
        fi

        # Count concurrent Claude Code sessions (projects with activity in last N minutes)
        # Expand tilde in path
        PROJECTS_PATH="${CLAUDE_PROJECTS_PATH/#\~/$HOME}"
        ACTIVE_SESSIONS=$(find "$PROJECTS_PATH" -name "*.jsonl" -type f -mmin -$SESSION_ACTIVITY_THRESHOLD 2>/dev/null | \
            xargs -I {} dirname {} 2>/dev/null | sort -u | wc -l | tr -d ' ')

        # Set progress bar color based on layer
        case "$BAR_COLOR" in
            "GREEN")
                PROGRESS_COLOR="$GREEN_CODE"
                ;;
            "ORANGE")
                PROGRESS_COLOR="$ORANGE_CODE"
                ;;
            "RED")
                PROGRESS_COLOR="$RED_CODE"
                ;;
            *)
                PROGRESS_COLOR="$GREEN_CODE"
                ;;
        esac

        # Build statusline conditionally based on section toggles
        STATUSLINE_SECTIONS=()

        [[ "$SHOW_DIRECTORY" == "true" ]] && STATUSLINE_SECTIONS+=("${ORANGE_CODE}${DIR_NAME}${RESET_CODE}")
        [[ "$SHOW_CONTEXT" == "true" ]] && STATUSLINE_SECTIONS+=("${PINK_CODE}${CTX_TOTAL} ${CTX_PROGRESS_BAR}${RESET_CODE}")
        [[ "$SHOW_COST" == "true" ]] && STATUSLINE_SECTIONS+=("${PROGRESS_COLOR}${COST_FMT} ${PROGRESS_BAR} ${COST_PERCENTAGE}%${RESET_CODE}")
        [[ "$SHOW_WEEKLY" == "true" ]] && STATUSLINE_SECTIONS+=("weekly ${WEEKLY_PCT}%")
        [[ "$SHOW_TIMER" == "true" ]] && STATUSLINE_SECTIONS+=("${PURPLE_CODE}${RESET_INFO}${RESET_CODE}")
        [[ "$SHOW_SESSIONS" == "true" ]] && STATUSLINE_SECTIONS+=("${CYAN_CODE}×${ACTIVE_SESSIONS}${RESET_CODE}")

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
        printf '%b\n' "$STATUSLINE"
    else
        # Fallback: No active window
        echo "$DIR_NAME | No active window"
    fi
else
    # Fallback: ccusage failed or no data
    echo "$DIR_NAME | Window tracking unavailable"
fi