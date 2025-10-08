#!/bin/bash
#
# statusline-cache.sh - Unified cache management for cc-statusline
#
# Provides centralized cache validation and dependency tracking to ensure
# cached values are invalidated when configuration changes.
#
# Author: hell0github
# License: MIT

# ====================================================================================
# CACHE ARCHITECTURE
# ====================================================================================
#
# The statusline uses multiple cache files to improve performance by avoiding
# redundant external calls (ccusage, jq parsing, etc.).
#
# CACHE FILES:
# ------------
# 1. data/.daily_cache
#    Format: timestamp|period_start|period_end|daily_cost
#    Purpose: Cache daily cost calculation
#    Invalidation: Period change OR time-based (cache_duration)
#    Dependencies: weekly_limit, weekly_baseline_pct
#
# 2. data/.official_weekly_cache
#    Format: timestamp|period_start|period_end|weekly_cost
#    Purpose: Cache weekly cost calculation (ccusage_r scheme)
#    Invalidation: Period change OR time-based (cache_duration)
#    Dependencies: weekly_limit, weekly_baseline_pct
#
# 3. data/.weekly_recommend_cache
#    Format: timestamp|cycle_start|recommend_value
#    Purpose: Cache recommended daily usage calculation
#    Invalidation: Cycle change OR time-based (cache_duration)
#    Dependencies: weekly_limit, weekly_baseline_pct, daily_cost
#
# 4. data/.cache_deps (NEW)
#    Format: JSON with config dependencies
#    Purpose: Track configuration values that affect cached data
#    Invalidation: Manual (when config changes)
#
# INVALIDATION RULES:
# -------------------
# - Period/Cycle Change: Cached data is for a different time period
# - Time-Based: Cached data is older than cache_duration
# - Dependency Change: Config values that affect calculation have changed
# - Data Corruption: Cached value fails validation (not a number, wrong format)
#
# BENEFITS:
# ---------
# - Avoid redundant ccusage calls (expensive: ~200-500ms each)
# - Consistent data across sections (same weekly_cost used by weekly and daily)
# - Graceful degradation (cache miss → recalculate)
# - Atomic writes (tmp file → mv for crash safety)
#
# ====================================================================================

# ====================================================================================
# CACHE DEPENDENCY TRACKING
# ====================================================================================

# Get cache dependency file path
get_cache_deps_file() {
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    echo "$script_dir/../data/.cache_deps"
}

# Save current configuration dependencies to cache deps file
# This allows detecting when config changes invalidate cached data
# Usage: save_cache_dependencies <weekly_limit> <weekly_baseline_pct>
save_cache_dependencies() {
    local weekly_limit=$1
    local weekly_baseline_pct=$2
    local cache_deps_file=$(get_cache_deps_file)

    # Create JSON with current config state
    cat > "${cache_deps_file}.tmp" <<EOF
{
  "version": "1.0",
  "updated": $(date +%s),
  "dependencies": {
    "weekly_limit": $weekly_limit,
    "weekly_baseline_pct": $weekly_baseline_pct
  }
}
EOF
    mv "${cache_deps_file}.tmp" "$cache_deps_file"
}

# Check if cached data dependencies are still valid
# Returns 0 if valid, 1 if dependencies changed (cache should be invalidated)
# Usage: validate_cache_dependencies <weekly_limit> <weekly_baseline_pct>
validate_cache_dependencies() {
    local weekly_limit=$1
    local weekly_baseline_pct=$2
    local cache_deps_file=$(get_cache_deps_file)

    # If no deps file exists, create it (first run)
    if [[ ! -f "$cache_deps_file" ]]; then
        save_cache_dependencies "$weekly_limit" "$weekly_baseline_pct"
        return 0  # Valid (just created)
    fi

    # Read cached dependencies
    local cached_limit=$(jq -r '.dependencies.weekly_limit' "$cache_deps_file" 2>/dev/null)
    local cached_baseline=$(jq -r '.dependencies.weekly_baseline_pct' "$cache_deps_file" 2>/dev/null)

    # Check if dependencies match
    if [[ "$cached_limit" == "$weekly_limit" ]] && \
       [[ "$cached_baseline" == "$weekly_baseline_pct" ]]; then
        return 0  # Valid
    else
        # Dependencies changed - update cache deps file and invalidate caches
        save_cache_dependencies "$weekly_limit" "$weekly_baseline_pct"
        return 1  # Invalid
    fi
}

# Invalidate all cache files (call when dependencies change)
# Usage: invalidate_all_caches
invalidate_all_caches() {
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local data_dir="$script_dir/../data"

    # Remove all cache files (they will be regenerated on next access)
    rm -f "$data_dir/.daily_cache"
    rm -f "$data_dir/.official_weekly_cache"
    rm -f "$data_dir/.weekly_recommend_cache"
}

# Validate cache dependencies and invalidate if needed
# This should be called early in statusline.sh with current config values
# Usage: check_and_update_cache_deps <weekly_limit> <weekly_baseline_pct>
check_and_update_cache_deps() {
    local weekly_limit=$1
    local weekly_baseline_pct=$2

    if ! validate_cache_dependencies "$weekly_limit" "$weekly_baseline_pct"; then
        # Dependencies changed - invalidate all caches
        invalidate_all_caches
    fi
}
