#!/usr/bin/env bash
# Weekly Usage Calibrator - Aligns statusline with Anthropic official usage
#
# Purpose: Updates weekly_baseline_percent to compensate for untracked costs:
#   - Deleted/compacted transcripts (clear/compact commands)
#   - Extended context usage (Sonnet 4 [1m] pricing differences)
#   - Any costs not captured by ccusage
#
# Usage: ./calibrate_weekly_usage.sh <official_usage_percent>
# Example: ./calibrate_weekly_usage.sh 18.5

set -euo pipefail

# Colors
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[1;93m'
CYAN='\033[96m'
BOLD='\033[1m'
RESET='\033[0m'

# Resolve script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_FILE="$PROJECT_ROOT/config/config.json"
UTILS_FILE="$PROJECT_ROOT/src/statusline-utils.sh"
WEEKLY_CACHE="$PROJECT_ROOT/data/.official_weekly_cache"

# Validate dependencies
if ! command -v jq &>/dev/null; then
    echo -e "${RED}Error: jq is required but not installed${RESET}" >&2
    echo "Install with: brew install jq (macOS) or apt-get install jq (Linux)" >&2
    exit 1
fi

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo -e "${RED}Error: Config file not found: $CONFIG_FILE${RESET}" >&2
    exit 1
fi

if [[ ! -f "$UTILS_FILE" ]]; then
    echo -e "${RED}Error: Utils file not found: $UTILS_FILE${RESET}" >&2
    exit 1
fi

# Parse arguments
if [[ $# -ne 1 ]]; then
    echo -e "${YELLOW}Usage: $0 <official_usage_percent>${RESET}" >&2
    echo ""
    echo "Example: $0 18.5" >&2
    echo ""
    echo "Steps to calibrate:"
    echo "  1. Check Anthropic console for current weekly usage percentage"
    echo "  2. Run this script with that percentage"
    echo "  3. Statusline will now match official usage"
    exit 1
fi

OFFICIAL_PCT="$1"

# Validate official percentage
if ! [[ "$OFFICIAL_PCT" =~ ^[0-9]+(\.[0-9]+)?$ ]] || (($(echo "$OFFICIAL_PCT < 0" | bc -l))); then
    echo -e "${RED}Error: Invalid percentage '$OFFICIAL_PCT' (must be >= 0)${RESET}" >&2
    exit 1
fi

if (($(echo "$OFFICIAL_PCT > 100" | bc -l))); then
    echo -e "${YELLOW}Warning: Usage exceeds 100% ($OFFICIAL_PCT%)${RESET}" >&2
fi

# Load configuration
WEEKLY_SCHEME=$(jq -r '.tracking.weekly_scheme // "ccusage"' "$CONFIG_FILE")
OFFICIAL_RESET_DATE=$(jq -r '.tracking.official_reset_date // ""' "$CONFIG_FILE")
CURRENT_BASELINE=$(jq -r '.tracking.weekly_baseline_percent // 0' "$CONFIG_FILE")
USER_PLAN=$(jq -r '.user.plan // "max20x"' "$CONFIG_FILE")

# Validate prerequisites
if [[ "$WEEKLY_SCHEME" != "ccusage_r" ]]; then
    echo -e "${RED}Error: Calibration requires tracking.weekly_scheme = 'ccusage_r'${RESET}" >&2
    echo "Current scheme: $WEEKLY_SCHEME" >&2
    echo "" >&2
    echo "To enable:" >&2
    echo "  1. Set tracking.weekly_scheme to 'ccusage_r' in config.json" >&2
    echo "  2. Set tracking.official_reset_date (e.g., '2025-10-08T15:00:00-07:00')" >&2
    exit 1
fi

if [[ -z "$OFFICIAL_RESET_DATE" ]]; then
    echo -e "${RED}Error: tracking.official_reset_date not configured${RESET}" >&2
    echo "Set this in config.json to match Anthropic console reset time" >&2
    exit 1
fi

# Source utilities to get current tracked usage
source "$UTILS_FILE"

echo -e "${CYAN}${BOLD}=== Weekly Usage Calibrator ===${RESET}"
echo ""
echo -e "Configuration:"
echo -e "  Plan: ${BOLD}$USER_PLAN${RESET}"
echo -e "  Reset Date: ${BOLD}$OFFICIAL_RESET_DATE${RESET}"
echo -e "  Current Baseline: ${BOLD}${CURRENT_BASELINE}%${RESET}"
echo ""

# Get current tracked usage (without baseline)
echo -e "${CYAN}Calculating current tracked usage...${RESET}"

# Calculate tracked percentage from ccusage_r
WEEKLY_COST=$(get_official_weekly_cost "$OFFICIAL_RESET_DATE" 0)

# Get weekly limit based on plan
case "$USER_PLAN" in
    "pro")
        WEEKLY_LIMIT=$(jq -r '.limits.weekly.pro // 300' "$CONFIG_FILE")
        ;;
    "max5x")
        WEEKLY_LIMIT=$(jq -r '.limits.weekly.max5x // 500' "$CONFIG_FILE")
        ;;
    "max20x")
        WEEKLY_LIMIT=$(jq -r '.limits.weekly.max20x // 850' "$CONFIG_FILE")
        ;;
    *)
        echo -e "${RED}Error: Unknown plan '$USER_PLAN'${RESET}" >&2
        exit 1
        ;;
esac

# Calculate tracked percentage (raw, without baseline)
TRACKED_PCT=$(echo "scale=2; ($WEEKLY_COST / $WEEKLY_LIMIT) * 100" | bc)

echo -e "  Tracked Cost: ${BOLD}\$$WEEKLY_COST${RESET} / \$$WEEKLY_LIMIT"
echo -e "  Tracked Percentage: ${BOLD}${TRACKED_PCT}%${RESET} (without baseline)"
echo ""

# Calculate new baseline
GAP=$(echo "scale=2; $OFFICIAL_PCT - $TRACKED_PCT" | bc)
NEW_BASELINE="$GAP"

echo -e "${YELLOW}${BOLD}Calibration Summary:${RESET}"
echo -e "  Official Usage (Anthropic): ${BOLD}${OFFICIAL_PCT}%${RESET}"
echo -e "  Tracked Usage (ccusage_r):  ${BOLD}${TRACKED_PCT}%${RESET}"
echo -e "  Gap (untracked costs):      ${BOLD}${GAP}%${RESET}"
echo ""
echo -e "  Old Baseline: ${BOLD}${CURRENT_BASELINE}%${RESET}"
echo -e "  New Baseline: ${BOLD}${NEW_BASELINE}%${RESET}"
echo ""

# Warn if gap is unusually large
if (($(echo "${GAP#-} > 20" | bc -l))); then
    echo -e "${YELLOW}Warning: Large gap detected (${GAP}%)${RESET}"
    echo "This may indicate:"
    echo "  - Significant untracked transcript deletions"
    echo "  - Extended context usage (e.g., Sonnet 4 [1m])"
    echo "  - Misconfigured official_reset_date"
    echo ""
fi

# Confirm update
read -p "Update baseline to ${NEW_BASELINE}%? [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Calibration cancelled${RESET}"
    exit 0
fi

# Update config
echo -e "${CYAN}Updating config...${RESET}"

TMP_CONFIG=$(mktemp)
jq --arg baseline "$NEW_BASELINE" \
   '.tracking.weekly_baseline_percent = ($baseline | tonumber)' \
   "$CONFIG_FILE" > "$TMP_CONFIG"

if [[ $? -eq 0 ]]; then
    mv "$TMP_CONFIG" "$CONFIG_FILE"
    echo -e "${GREEN}✓ Config updated${RESET}"
else
    rm -f "$TMP_CONFIG"
    echo -e "${RED}Error updating config${RESET}" >&2
    exit 1
fi

# Clear cache to force refresh
if [[ -f "$WEEKLY_CACHE" ]]; then
    rm -f "$WEEKLY_CACHE"
    echo -e "${GREEN}✓ Weekly cache cleared${RESET}"
fi

# Calculate new displayed percentage
NEW_DISPLAYED=$(echo "scale=2; $TRACKED_PCT + $NEW_BASELINE" | bc)

echo ""
echo -e "${GREEN}${BOLD}=== Calibration Complete ===${RESET}"
echo -e "  Baseline updated: ${BOLD}${CURRENT_BASELINE}%${RESET} → ${BOLD}${NEW_BASELINE}%${RESET}"
echo -e "  Statusline will now show: ${BOLD}${NEW_DISPLAYED}%${RESET} (matches official ${OFFICIAL_PCT}%)"
echo ""
echo -e "${CYAN}Note: Recalibrate weekly after reset or when drift is detected${RESET}"
