#!/usr/bin/env bash
# validate.sh — Validates generated files after otel-bootstrap runs.
# Run from the target service's root directory.
#
# Checks:
#   1. All Grafana dashboard JSONs are valid
#   2. No unreplaced {{SERVICE_*}} placeholders remain
#
# Exit code: 0 = all OK, 1 = at least one check failed

set -euo pipefail

TARGET_DIR="${TARGET_DIR:-$(pwd)}"
ERRORS=0

# ── 1. Grafana JSON validation ─────────────────────────────────────────────
DASH_DIR="${TARGET_DIR}/deploy/grafana/dashboards"
if [ -d "$DASH_DIR" ]; then
    for f in "$DASH_DIR"/*.json; do
        [ -f "$f" ] || continue
        if jq . "$f" > /dev/null 2>&1; then
            echo "OK  JSON valid: $(basename "$f")"
        else
            echo "ERR JSON invalid: $f"
            ERRORS=$((ERRORS + 1))
        fi
    done
else
    echo "SKIP No $DASH_DIR found"
fi

# ── 2. Unreplaced placeholders ─────────────────────────────────────────────
echo ""
echo "Checking for unreplaced {{SERVICE_*}} placeholders..."
PLACEHOLDER_FILES=$(grep -rl '{{SERVICE_' \
    "${TARGET_DIR}/deploy/grafana" \
    "${TARGET_DIR}/src/shared/tracer" \
    "${TARGET_DIR}/internal/otel" \
    2>/dev/null || true)

if [ -n "$PLACEHOLDER_FILES" ]; then
    echo "ERR Unreplaced placeholders found in:"
    echo "$PLACEHOLDER_FILES"
    ERRORS=$((ERRORS + 1))
else
    echo "OK  No unreplaced placeholders"
fi

# ── Summary ───────────────────────────────────────────────────────────────
echo ""
if [ "$ERRORS" -eq 0 ]; then
    echo "✓ All validation checks passed"
    exit 0
else
    echo "✗ ${ERRORS} validation error(s) found"
    exit 1
fi
