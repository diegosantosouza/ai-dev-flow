#!/usr/bin/env bash
# render.sh — Substitutes template placeholders in all .tmpl files under SRC_DIR
# and writes rendered files (without the .tmpl suffix) to DST_DIR.
#
# Required env vars:
#   SERVICE_NAME   — lowercase service name, e.g. "fulfillment"
#   SRC_DIR        — directory containing .tmpl files
#   DST_DIR        — output directory (will be created if needed)
#
# Optional env vars:
#   SERVICE_UPPER  — auto-computed from SERVICE_NAME if not set
#   SERVICE_PASCAL — auto-computed from SERVICE_NAME if not set
#   SERVICE_PREFIX — auto-computed from SERVICE_NAME if not set
#   EXPORTED_JOB   — defaults to "${SERVICE_NAME}-api"

set -euo pipefail

: "${SERVICE_NAME:?SERVICE_NAME is required}"
: "${SRC_DIR:?SRC_DIR is required}"
: "${DST_DIR:?DST_DIR is required}"

SERVICE_UPPER="${SERVICE_UPPER:-$(echo "$SERVICE_NAME" | tr '[:lower:]' '[:upper:]' | tr '-' '_')}"
SERVICE_PREFIX="${SERVICE_PREFIX:-${SERVICE_NAME}.}"
EXPORTED_JOB="${EXPORTED_JOB:-${SERVICE_NAME}-api}"

# PascalCase: capitalize first letter of each word separated by - or _
SERVICE_PASCAL="${SERVICE_PASCAL:-$(python3 -c "
import re, sys
s = sys.argv[1]
print(''.join(w.capitalize() for w in re.split(r'[-_]', s)))
" "$SERVICE_NAME")}"

echo "[render] SERVICE_NAME=${SERVICE_NAME}"
echo "[render] SERVICE_UPPER=${SERVICE_UPPER}"
echo "[render] SERVICE_PASCAL=${SERVICE_PASCAL}"
echo "[render] SERVICE_PREFIX=${SERVICE_PREFIX}"
echo "[render] EXPORTED_JOB=${EXPORTED_JOB}"

find "$SRC_DIR" -type f -name "*.tmpl" | while read -r tmpl; do
    rel="${tmpl#$SRC_DIR/}"
    out_rel="${rel%.tmpl}"
    dst="${DST_DIR}/${out_rel}"
    dst_dir="$(dirname "$dst")"
    mkdir -p "$dst_dir"

    sed \
        -e "s|{{SERVICE_NAME}}|${SERVICE_NAME}|g" \
        -e "s|{{SERVICE_UPPER}}|${SERVICE_UPPER}|g" \
        -e "s|{{SERVICE_PASCAL}}|${SERVICE_PASCAL}|g" \
        -e "s|{{SERVICE_PREFIX}}|${SERVICE_PREFIX}|g" \
        -e "s|{{EXPORTED_JOB}}|${EXPORTED_JOB}|g" \
        "$tmpl" > "$dst"

    echo "[render] wrote ${dst}"
done
