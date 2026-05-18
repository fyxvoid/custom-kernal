#!/usr/bin/env bash
# Compare two benchmark CSV files (stock vs. custom kernel)
# Usage: ./compare_results.sh <stock.csv> <custom.csv>

set -euo pipefail

[[ $# -ge 2 ]] || { echo "Usage: $0 <stock.csv> <custom.csv>"; exit 1; }

STOCK="$1"
CUSTOM="$2"

GRN='\033[0;32m'; RED='\033[0;31m'; YLW='\033[0;33m'; BLU='\033[0;34m'; NC='\033[0m'

printf "\n%-45s %15s %15s %10s\n" "Metric" "Stock" "Custom" "Change"
printf "%s\n" "$(printf '%.0s-' {1..90})"

declare -A STOCK_VALS UNITS

while IFS=',' read -r metric value unit; do
    [[ "$metric" == "metric" ]] && continue
    STOCK_VALS["$metric"]="$value"
    UNITS["$metric"]="$unit"
done < "$STOCK"

while IFS=',' read -r metric value unit; do
    [[ "$metric" == "metric" ]] && continue

    stock_val="${STOCK_VALS[$metric]:-N/A}"
    unit_str="${UNITS[$metric]:-}"

    if [[ "$stock_val" =~ ^[0-9.]+$ ]] && [[ "$value" =~ ^[0-9.]+$ ]]; then
        if (( $(echo "$stock_val > 0" | bc -l) )); then
            pct=$(echo "scale=1; ($value - $stock_val) * 100 / $stock_val" | bc)
            abs_pct=${pct#-}

            if (( $(echo "$pct < 0" | bc -l) )); then
                color=$GRN  # decrease = improvement for most metrics
                change="${pct}%"
            else
                color=$RED
                change="+${pct}%"
            fi

            printf "${color}%-45s %15s %15s %10s${NC} %s\n" \
                "$metric" "${stock_val} ${unit_str}" "${value} ${unit_str}" "$change" ""
        else
            printf "%-45s %15s %15s %10s\n" "$metric" "$stock_val" "$value" "N/A"
        fi
    else
        printf "${YLW}%-45s %15s %15s %10s${NC}\n" \
            "$metric" "$stock_val" "$value" "(non-numeric)"
    fi
done < "$CUSTOM"

echo ""
echo "Green = improvement over stock, Red = regression."
