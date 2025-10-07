#!/bin/bash
#
# statusline-layers.sh - Generic multi-layer calculation for cc-statusline
#
# Provides reusable functions for calculating layer metrics (thresholds, visual percentages,
# colors, and filled blocks) for progress bars with 2-layer or 3-layer visualization.
#
# Author: hell0github
# License: MIT

# ====================================================================================
# THREE-LAYER CALCULATION
# ====================================================================================
# Calculates layer metrics for a 3-layer visualization system
#
# Usage: calculate_three_layer_metrics <value> <base_threshold> <layer1_mult> <layer2_mult> <layer3_mult> <layer1_color> <layer2_color> <layer3_color> <bar_length>
#
# Arguments:
#   value          - Current value to evaluate (e.g., ACTUAL_PCT, CONTEXT_TOKENS)
#   base_threshold - Base threshold value (e.g., COST_LIMIT, CONTEXT_LIMIT)
#   layer1_mult    - Layer 1 threshold multiplier
#   layer2_mult    - Layer 2 threshold multiplier
#   layer3_mult    - Layer 3 threshold multiplier
#   layer1_color   - Layer 1 color name
#   layer2_color   - Layer 2 color name
#   layer3_color   - Layer 3 color name
#   bar_length     - Progress bar length in blocks
#
# Returns (pipe-separated): layer_num|visual_pct|color_name|filled_blocks
#   layer_num      - Which layer (1, 2, or 3)
#   visual_pct     - Visual percentage (0-100) scaled for current layer
#   color_name     - Color name for the current layer
#   filled_blocks  - Number of filled blocks for the progress bar
#
# Example:
#   result=$(calculate_three_layer_metrics 15.5 50 0.3 0.5 1.0 "green" "orange" "red" 10)
#   IFS='|' read layer visual color filled <<< "$result"
#   # layer=2, visual=62.00, color=orange, filled=6
calculate_three_layer_metrics() {
    local value=$1
    local base=$2
    local layer1_mult=$3
    local layer2_mult=$4
    local layer3_mult=$5
    local layer1_color=$6
    local layer2_color=$7
    local layer3_color=$8
    local bar_length=$9

    # Calculate layer thresholds from base and multipliers
    local layer1_threshold=$(awk "BEGIN {printf \"%.2f\", $base * $layer1_mult}")
    local layer2_threshold=$(awk "BEGIN {printf \"%.2f\", $base * $layer2_mult}")
    local layer3_threshold=$(awk "BEGIN {printf \"%.2f\", $base * $layer3_mult}")

    # Calculate visual scale multipliers (how much to scale each layer to 0-100%)
    local layer1_multiplier=$(awk "BEGIN {printf \"%.2f\", 100 / $layer1_threshold}")
    local layer2_multiplier=$(awk "BEGIN {printf \"%.2f\", 100 / ($layer2_threshold - $layer1_threshold)}")
    local layer3_multiplier=$(awk "BEGIN {printf \"%.2f\", 100 / ($layer3_threshold - $layer2_threshold)}")

    # Determine which layer the value falls into and calculate visual percentage
    local layer_num
    local visual_pct
    local color_name

    if (( $(awk "BEGIN {print ($value <= $layer1_threshold)}") )); then
        # Layer 1: 0 to layer1_threshold → 0-100% visual
        layer_num=1
        visual_pct=$(awk "BEGIN {printf \"%.2f\", $value * $layer1_multiplier}")
        color_name="$layer1_color"
    elif (( $(awk "BEGIN {print ($value <= $layer2_threshold)}") )); then
        # Layer 2: layer1_threshold to layer2_threshold → 0-100% visual
        layer_num=2
        visual_pct=$(awk "BEGIN {printf \"%.2f\", ($value - $layer1_threshold) * $layer2_multiplier}")
        color_name="$layer2_color"
    else
        # Layer 3: layer2_threshold to layer3_threshold → 0-100% visual
        layer_num=3
        visual_pct=$(awk "BEGIN {printf \"%.2f\", ($value - $layer2_threshold) * $layer3_multiplier}")

        # Cap at 100% if value exceeds layer3_threshold
        if (( $(awk "BEGIN {print ($visual_pct > 100)}") )); then
            visual_pct=100
        fi

        color_name="$layer3_color"
    fi

    # Calculate filled blocks based on visual percentage
    local filled_blocks=$(awk "BEGIN {printf \"%.0f\", ($visual_pct / 100) * $bar_length}")

    # Cap filled blocks at bar length
    if [ $filled_blocks -gt $bar_length ]; then
        filled_blocks=$bar_length
    fi

    # Ensure at least 1 block when in layer 2 or 3 (visual feedback for non-zero usage)
    if [ $layer_num -gt 1 ] && [ $filled_blocks -eq 0 ]; then
        filled_blocks=1
    fi

    # Return structured result
    echo "${layer_num}|${visual_pct}|${color_name}|${filled_blocks}"
}

# ====================================================================================
# TWO-LAYER CALCULATION
# ====================================================================================
# Calculates layer metrics for a 2-layer visualization system
#
# Usage: calculate_two_layer_metrics <value> <base_threshold> <layer1_mult> <layer2_mult> <layer1_color> <layer2_color> <bar_length>
#
# Arguments:
#   value          - Current value to evaluate (e.g., DAILY_PCT)
#   base_threshold - Base threshold value (e.g., recommend value, weekly/7)
#   layer1_mult    - Layer 1 threshold multiplier
#   layer2_mult    - Layer 2 threshold multiplier
#   layer1_color   - Layer 1 color name
#   layer2_color   - Layer 2 color name
#   bar_length     - Progress bar length in blocks
#
# Returns (pipe-separated): layer_num|visual_pct|color_name|filled_blocks
#   layer_num      - Which layer (1 or 2)
#   visual_pct     - Visual percentage (0-100) scaled for current layer
#   color_name     - Color name for the current layer
#   filled_blocks  - Number of filled blocks for the progress bar
#
# Example:
#   result=$(calculate_two_layer_metrics 18.5 14.29 1.0 1.5 "green" "orange" 10)
#   IFS='|' read layer visual color filled <<< "$result"
#   # layer=2, visual=43.55, color=orange, filled=4
calculate_two_layer_metrics() {
    local value=$1
    local base=$2
    local layer1_mult=$3
    local layer2_mult=$4
    local layer1_color=$5
    local layer2_color=$6
    local bar_length=$7

    # Calculate layer thresholds from base and multipliers
    local layer1_threshold=$(awk "BEGIN {printf \"%.2f\", $base * $layer1_mult}")
    local layer2_threshold=$(awk "BEGIN {printf \"%.2f\", $base * $layer2_mult}")

    # Calculate visual scale multipliers (how much to scale each layer to 0-100%)
    local layer1_multiplier=$(awk "BEGIN {printf \"%.2f\", 100 / $layer1_threshold}")
    local layer2_multiplier=$(awk "BEGIN {printf \"%.2f\", 100 / ($layer2_threshold - $layer1_threshold)}")

    # Determine which layer the value falls into and calculate visual percentage
    local layer_num
    local visual_pct
    local color_name

    if (( $(awk "BEGIN {print ($value <= $layer1_threshold)}") )); then
        # Layer 1: 0 to layer1_threshold → 0-100% visual
        layer_num=1
        visual_pct=$(awk "BEGIN {printf \"%.2f\", $value * $layer1_multiplier}")
        color_name="$layer1_color"
    else
        # Layer 2: layer1_threshold to layer2_threshold → 0-100% visual
        layer_num=2
        visual_pct=$(awk "BEGIN {printf \"%.2f\", ($value - $layer1_threshold) * $layer2_multiplier}")

        # Cap at 100% if value exceeds layer2_threshold
        if (( $(awk "BEGIN {print ($visual_pct > 100)}") )); then
            visual_pct=100
        fi

        color_name="$layer2_color"
    fi

    # Calculate filled blocks based on visual percentage
    local filled_blocks=$(awk "BEGIN {printf \"%.0f\", ($visual_pct / 100) * $bar_length}")

    # Cap filled blocks at bar length
    if [ $filled_blocks -gt $bar_length ]; then
        filled_blocks=$bar_length
    fi

    # Return structured result
    echo "${layer_num}|${visual_pct}|${color_name}|${filled_blocks}"
}

# ====================================================================================
# PROJECTION CALCULATION (for sections with projection support)
# ====================================================================================
# Calculates projection metrics for a value that will be displayed on the same scale
# as the current progress bar.
#
# This function is used by sections that show a projection separator (5-hour window, daily).
# It determines which layer the projected value falls into and calculates its visual position
# using the CURRENT layer's multiplier for consistent scaling.
#
# Usage: calculate_projection_metrics <projected_value> <current_value> <current_layer> <base_threshold> <layer_mults...> <layer_colors...> <bar_length> <num_layers>
#
# For 3-layer:
#   calculate_projection_metrics "$proj_val" "$curr_val" "$curr_layer" "$base" "$mult1" "$mult2" "$mult3" "$color1" "$color2" "$color3" "$bar_len" "3"
#
# For 2-layer:
#   calculate_projection_metrics "$proj_val" "$curr_val" "$curr_layer" "$base" "$mult1" "$mult2" "" "$color1" "$color2" "" "$bar_len" "2"
#
# Returns (pipe-separated): projected_pos|projected_color_name|show_separator
#   projected_pos       - Block position for projection separator (0 to bar_length)
#   projected_color_name - Color name for projection
#   show_separator      - "1" if separator should be shown, "0" if not (projection == current)
calculate_projection_metrics() {
    local projected_value=$1
    local current_value=$2
    local current_layer=$3
    local base=$4
    local layer1_mult=$5
    local layer2_mult=$6
    local layer3_mult=$7    # Empty for 2-layer
    local layer1_color=$8
    local layer2_color=$9
    local layer3_color=${10}  # Empty for 2-layer
    local bar_length=${11}
    local num_layers=${12}  # "2" or "3"

    # Don't show separator if projection equals current cost
    if (( $(awk "BEGIN {print ($projected_value == $current_value)}") )); then
        echo "-1||0"
        return
    fi

    # Calculate layer thresholds
    local layer1_threshold=$(awk "BEGIN {printf \"%.2f\", $base * $layer1_mult}")
    local layer2_threshold=$(awk "BEGIN {printf \"%.2f\", $base * $layer2_mult}")
    local layer3_threshold
    if [ "$num_layers" = "3" ]; then
        layer3_threshold=$(awk "BEGIN {printf \"%.2f\", $base * $layer3_mult}")
    fi

    # Calculate visual scale multipliers
    local layer1_multiplier=$(awk "BEGIN {printf \"%.2f\", 100 / $layer1_threshold}")
    local layer2_multiplier=$(awk "BEGIN {printf \"%.2f\", 100 / ($layer2_threshold - $layer1_threshold)}")
    local layer3_multiplier
    if [ "$num_layers" = "3" ]; then
        layer3_multiplier=$(awk "BEGIN {printf \"%.2f\", 100 / ($layer3_threshold - $layer2_threshold)}")
    fi

    # Determine which layer the projection falls into
    local projected_color_name
    local projected_visual_pct

    if [ "$num_layers" = "3" ]; then
        # 3-layer logic
        if (( $(awk "BEGIN {print ($projected_value <= $layer1_threshold)}") )); then
            projected_color_name="$layer1_color"
        elif (( $(awk "BEGIN {print ($projected_value <= $layer2_threshold)}") )); then
            projected_color_name="$layer2_color"
        else
            projected_color_name="$layer3_color"
        fi

        # Calculate visual position using CURRENT layer's multiplier for consistent scale
        if [ "$current_layer" = "1" ]; then
            projected_visual_pct=$(awk "BEGIN {printf \"%.2f\", $projected_value * $layer1_multiplier}")
        elif [ "$current_layer" = "2" ]; then
            projected_visual_pct=$(awk "BEGIN {printf \"%.2f\", ($projected_value - $layer1_threshold) * $layer2_multiplier}")
        else
            projected_visual_pct=$(awk "BEGIN {printf \"%.2f\", ($projected_value - $layer2_threshold) * $layer3_multiplier}")
        fi
    else
        # 2-layer logic
        if (( $(awk "BEGIN {print ($projected_value <= $layer1_threshold)}") )); then
            projected_color_name="$layer1_color"
        else
            projected_color_name="$layer2_color"
        fi

        # Calculate visual position using CURRENT layer's multiplier
        if [ "$current_layer" = "1" ]; then
            projected_visual_pct=$(awk "BEGIN {printf \"%.2f\", $projected_value * $layer1_multiplier}")
        else
            projected_visual_pct=$(awk "BEGIN {printf \"%.2f\", ($projected_value - $layer1_threshold) * $layer2_multiplier}")
        fi
    fi

    # Cap visual percentage at 100%
    if (( $(awk "BEGIN {print ($projected_visual_pct > 100)}") )); then
        projected_visual_pct=100
    fi

    # Calculate block position
    local projected_pos=$(awk "BEGIN {printf \"%.0f\", ($projected_visual_pct / 100) * $bar_length}")

    # Cap at bar length
    if [ $projected_pos -gt $bar_length ]; then
        projected_pos=$bar_length
    fi

    # Return structured result
    echo "${projected_pos}|${projected_color_name}|1"
}
